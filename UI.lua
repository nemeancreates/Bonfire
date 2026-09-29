local _, ns = ...
local Bonfire = ns.Bonfire
local Ledger = ns.Ledger

-- One small window with two modes: nearby fires (browse/host) and your table.
local UI = {}
ns.UI = UI

local ROWS = 10
local frame, rows, buttons, stake

local function Button(parent, label, width, onClick)
	local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
	b:SetSize(width, 22)
	b:SetText(label)
	b:SetScript("OnClick", onClick)
	return b
end

-- A secure button so the click can use the campfire kit. Protected in combat, so
-- anything that shows, hides or moves it has to check for lockdown first.
local function SecureButton(parent, label, width, onPost, onPre)
	local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate,SecureActionButtonTemplate")
	b:SetSize(width, 22)
	b:SetText(label)
	b:RegisterForClicks("AnyUp", "AnyDown")
	b:SetAttribute("type", "item")
	b:SetScript("PostClick", onPost)
	if onPre then b:SetScript("PreClick", onPre) end
	b.secure = true
	return b
end

local function Locked(b)
	return b.secure and InCombatLockdown()
end

local function Tooltip(widget, text)
	widget:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:SetText(type(text) == "function" and text() or text, 1, 1, 1, 1, true)
		GameTooltip:Show()
	end)
	widget:SetScript("OnLeave", GameTooltip_Hide)
end

local function StakeChanged()
	ns.Table:SetStake()
	UI:Refresh()
end

-- Row 1: [For fun | Gambling]  [-] 5(coin) [+] [coin] [Add]
-- Row 2: Bet: 5(gold) 20(silver)  (confirmed?)          [Clear] [Confirm bet]
local function BuildStake()
	local db = Bonfire.db.global.stake
	stake = CreateFrame("Frame", nil, frame)
	stake:SetSize(356, 52)
	stake:SetPoint("BOTTOMLEFT", 12, 38)

	stake.mode = Button(stake, "", 96, function()
		db.forFun = not db.forFun
		StakeChanged()
	end)
	stake.mode:SetPoint("TOPLEFT")
	Tooltip(stake.mode, "For fun: no gold, just the game.\nGambling: everyone trades their stake to the host before a round.")

	local function Step(sign)
		return function()
			local step = IsShiftKeyDown() and ns.STAKE_STEP_BIG or ns.STAKE_STEP
			db.amount = math.max(ns.STAKE_STEP, math.min(ns.STAKE_MAX, db.amount + sign * step))
			UI:Refresh()
		end
	end
	stake.less = Button(stake, "-", 24, Step(-1))
	stake.less:SetPoint("LEFT", stake.mode, "RIGHT", 8, 0)
	stake.amount = stake:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	stake.amount:SetPoint("LEFT", stake.less, "RIGHT", 4, 0)
	stake.amount:SetWidth(56)
	stake.more = Button(stake, "+", 24, Step(1))
	stake.more:SetPoint("LEFT", stake.amount, "RIGHT", 4, 0)
	stake.unit = Button(stake, "", 36, function()
		db.unit = db.unit % #ns.COIN_UNITS + 1
		UI:Refresh()
	end)
	stake.unit:SetPoint("LEFT", stake.more, "RIGHT", 4, 0)
	stake.add = Button(stake, "Add", 48, function()
		local coins = db.amount * ns.COIN_UNITS[db.unit].copper
		db.total = math.min(ns.BET_CAP, db.total + coins)
		UI:Refresh()
	end)
	stake.add:SetPoint("LEFT", stake.unit, "RIGHT", 4, 0)

	stake.confirm = Button(stake, "Confirm bet", 100, function()
		db.confirmed = db.total
		StakeChanged()
	end)
	stake.confirm:SetPoint("BOTTOMRIGHT")
	stake.clear = Button(stake, "Clear", 50, function()
		db.total = 0
		UI:Refresh()
	end)
	stake.clear:SetPoint("RIGHT", stake.confirm, "LEFT", -4, 0)
	stake.total = stake:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	stake.total:SetPoint("BOTTOMLEFT", 2, 6)
	stake.total:SetPoint("RIGHT", stake.clear, "LEFT", -6, 0)
	stake.total:SetJustifyH("LEFT")

	local stepTip = ("Steps of %d, Shift-click for %d."):format(ns.STAKE_STEP, ns.STAKE_STEP_BIG)
	Tooltip(stake.less, stepTip)
	Tooltip(stake.more, stepTip)
	Tooltip(stake.unit, function() return "Coin: " .. ns.COIN_UNITS[db.unit].name .. " (click to change)" end)
	Tooltip(stake.add, "Adds this amount to your bet. Switch coin type and add again to mix gold, silver and copper.")
	Tooltip(stake.clear, "Start the bet over.")
	Tooltip(stake.confirm, "Locks in this bet for your table.")
end

local function RefreshStake()
	local db = Bonfire.db.global.stake
	local unit = ns.COIN_UNITS[db.unit]
	stake.mode:SetText(db.forFun and "For fun" or (ns.StakeBadge(1) .. " Gambling"))
	stake.amount:SetText(("%d|T%s:16:16:2:0|t"):format(db.amount, unit.icon))
	stake.unit:SetText(("|T%s:16:16|t"):format(unit.icon))
	local pending = db.total ~= db.confirmed
	stake.total:SetText(("Bet: %s  %s"):format(db.total > 0 and ns.CoinString(db.total) or "|cff999999nothing yet|r",
		pending and "|cffffaa33(not confirmed)|r" or (db.total > 0 and "|cff66ff66confirmed|r" or "")))
	stake.confirm:SetText(pending and "Confirm bet" or "Bet set")
	stake.confirm:SetEnabled(pending and db.total > 0)
	stake.clear:SetEnabled(db.total > 0)
	for _, w in ipairs({ stake.less, stake.amount, stake.more, stake.unit, stake.add, stake.confirm, stake.clear, stake.total }) do
		w:SetShown(not db.forFun)
	end
end

-- Off to the left by default so the fire, the campfire kit and the character stay in view.
function UI:Place()
	if not frame then return end
	local pos = Bonfire.db.global.pos
	frame:ClearAllPoints()
	if pos then
		frame:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4])
	else
		frame:SetPoint("LEFT", UIParent, "LEFT", 30, 40)
	end
end

local function Build()
	frame = CreateFrame("Frame", "BonfireFrame", UIParent, "BasicFrameTemplateWithInset")
	frame:SetSize(380, 400)
	UI:Place()
	frame:SetMovable(true)
	frame:EnableMouse(true)
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", frame.StartMoving)
	frame:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		local point, _, relPoint, x, y = self:GetPoint()
		Bonfire.db.global.pos = { point, relPoint, x, y }
	end)
	frame:SetClampedToScreen(true)
	frame:Hide()
	tinsert(UISpecialFrames, "BonfireFrame")

	local title = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	title:SetPoint("TOP", 0, -5)
	title:SetText("Bonfire")

	frame.burn = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	frame.burn:SetPoint("TOPRIGHT", -14, -30)

	frame.header = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	frame.header:SetPoint("TOPLEFT", 14, -32)
	frame.header:SetPoint("RIGHT", frame.burn, "LEFT", -8, 0)
	frame.header:SetJustifyH("LEFT")

	frame.sub = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	frame.sub:SetPoint("TOPLEFT", 14, -50)
	frame.sub:SetPoint("RIGHT", -14, 0)
	frame.sub:SetJustifyH("LEFT")

	rows = {}
	for i = 1, ROWS do
		local row = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		row:SetPoint("TOPLEFT", 16, -52 - i * 22)
		row:SetPoint("RIGHT", -86, 0)
		row:SetJustifyH("LEFT")
		row.button = Button(frame, "", 64, function(self) self.action() end)
		row.button:SetPoint("RIGHT", frame, "RIGHT", -14, 0)
		row.button:SetPoint("TOP", row, "TOP", 0, 5)
		rows[i] = row
	end

	local Table = ns.Table
	buttons = {
		here = Button(frame, "Host at this fire", 130, function() Table:Host() end),
		light = SecureButton(frame, "Light a fire", 110, function(self)
			if not InCombatLockdown() then self:SetAttribute("type", "item") end
			if ns.BetReady() then Table:Armed() end
		end, function(self)
			-- No confirmed bet on a gold table: don't use the kit, say why.
			if not ns.BetReady() and not InCombatLockdown() then
				self:SetAttribute("type", nil)
				Bonfire:Print("Add an amount and Confirm bet first, or switch to For fun.")
			end
		end),
		stoke = Button(frame, "Stoke", 70, function() Table:Start() end),
		roll = Button(frame, "Roll", 60, function() Table:Roll() end),
		bank = Button(frame, "Bank", 60, function() Table:Bank() end),
		next = Button(frame, "Trade next", 150, function(self) ns.Trade:Open(self.name) end),
		pay = Button(frame, "Pay host", 130, function() Table:PayHost() end),
		cashout = Button(frame, "Cash out", 80, function() Table:CashOut() end),
		leave = Button(frame, "Leave", 90, function() Table:Leave() end),
	}
	buttons.leave:SetPoint("BOTTOMRIGHT", -12, 10)
	Tooltip(buttons.here, function()
		if ns.AtCampfire() then return "Open a table at the campfire you're standing at." end
		return "Stand at a campfire, or carry a Basic Campfire Kit (craft it with Cooking) to light one. /bf host skips this check."
	end)
	Tooltip(buttons.light, "Uses your Basic Campfire Kit. Your table opens as soon as the fire is lit.")
	Tooltip(buttons.stoke, "Deal in everyone who's ready and start Embers.")
	Tooltip(buttons.leave, function()
		local t = Table.current
		if t and Table:IsHosting() then
			if t.state == "settling" then return "Put the fire out now, even if someone hasn't been paid back." end
			if Table:CanPass() then return "Leave the table. The player who joined first takes over as host while the fire burns." end
			return "Close the table for good. On a gold table you pay everyone back first."
		end
		return "Leave the table. You fold whatever you have in this round."
	end)
	Tooltip(buttons.next, "Open a trade with the next player in the queue. Both of you still click Trade.")

	BuildStake()
end

local function ClearRows()
	frame.burn:SetText("")
	for _, row in ipairs(rows) do
		row:SetText("")
		row.button:Hide()
	end
	for _, b in pairs(buttons) do
		if not Locked(b) then b:Hide() end
	end
	stake:Hide()
end

-- Shows the given bottom-left buttons in order.
local function LayoutLeft(list)
	local prev
	for _, b in ipairs(list) do
		if not Locked(b) then
			b:ClearAllPoints()
			if prev then b:SetPoint("LEFT", prev, "RIGHT", 4, 0) else b:SetPoint("BOTTOMLEFT", 12, 10) end
			b:Show()
		end
		prev = b
	end
end

local function SetRow(i, text, label, action, enabled)
	local row = rows[i]
	if not row then return end
	row:SetText(text)
	if label then
		row.button:SetText(label)
		row.button.action = action
		row.button:SetEnabled(enabled ~= false)
		row.button:Show()
	end
end

local function ShowFires()
	frame.header:SetText("Nearby fires")
	local list = ns.Beacon:List()
	frame.sub:SetText(#list == 0 and "No fires in range. Sit at a campfire and light one." or "")
	for i = 1, math.min(#list, ROWS) do
		local fire = list[i]
		local game = ns.Games[fire.game]
		local near = fire.distance and fire.distance <= ns.Table.FOLD_RANGE
		SetRow(i, ("%s  %s  %d/%d %s  %s  |cff999999%s|r"):format(
				ns.Short(fire.host), game and game.name or "?", fire.seats or 0, fire.maxSeats or 0,
				ns.StakeBadge(fire.stake), ns.Coins(fire.stake), fire.distance and ("%d yd"):format(fire.distance) or "far"),
			"Join", function() ns.Table:Join(fire.host) end,
			near and fire.state ~= "settling" and (fire.seats or 0) < (fire.maxSeats or 0))
	end
	RefreshStake()
	stake:Show()

	-- At a campfire: host there. Otherwise light one with the kit, or explain what's missing.
	local atFire, kit = ns.AtCampfire(), ns.FindCampfireKit()
	if not atFire and kit and not InCombatLockdown() then
		buttons.light:SetAttribute("item", kit)
		LayoutLeft({ buttons.light })
	else
		buttons.here:SetText(atFire and "Host at this fire" or "Light a fire")
		buttons.here:SetEnabled(atFire)
		LayoutLeft({ buttons.here })
	end
end

local STATUS = { [0] = "|cff66ccffbanked|r", [1] = "|cffffaa33stoking|r", [2] = "|cff888888left|r", [3] = "|cff888888left|r" }

local function Subtitle(t)
	local gs = t.gs
	if t.state == "playing" and gs then
		return ("Round %d of %d%s"):format(gs.r, gs.R, t.lastRoll and ("   last roll: |cffffffff%d|r"):format(t.lastRoll) or "")
	elseif t.state == "settling" then
		return "Closing up: the host is paying everyone back."
	elseif t.winners and #t.winners > 0 then
		local names = {}
		for i, name in ipairs(t.winners) do names[i] = ns.Short(name) end
		local won = t.stake > 0 and t.share and ("  (" .. ns.Coins(t.share) .. " each)") or ""
		return "Winner: |cff66ff66" .. table.concat(names, ", ") .. "|r" .. won
	elseif t.stake > 0 then
		return ("Stake %s. Pay the host to be dealt in."):format(ns.Coins(t.stake))
	end
	return ("For fun. Waiting for players (%d/%d)."):format(#t.seats, t.maxSeats)
end

-- Time left on the fire, white until the last few minutes.
local function BurnText(t)
	if not t or t.state == "settling" then return "" end
	if t.closing then return "|cffff6666last game|r" end
	local left = ns.Table:TimeLeft(t)
	if not left then return "" end
	if left <= 0 then return "|cffff6666burnt out|r" end
	local color = left <= 60 and "ff6666" or left <= 180 and "ffcc33" or "ffffff"
	return ("|cff%s%d:%02d|r"):format(color, math.floor(left / 60), left % 60)
end

-- Queue of trades the host has to make: payouts first, then pay-ins.
local function NextTrade(t, payouts)
	if payouts[1] then return payouts[1][1], "Pay " .. ns.Short(payouts[1][1]) end
	if t.state == "settling" then return end
	local payins = Ledger.PayIns(t)
	if payins[1] then return payins[1][1], "Collect from " .. ns.Short(payins[1][1]) end
end

local function ShowTable(t)
	local Table = ns.Table
	local hosting, me = Table:IsHosting(), ns.Me()
	local game = ns.Games[t.game]
	local payouts = hosting and Ledger.Payouts(t) or t.payouts
	local owed = {}
	for _, p in ipairs(payouts) do owed[p[1]] = p[2] end

	frame.header:SetText(("%s's fire  |cffffffff%s|r %s"):format(ns.Short(t.host), game and game.name or "?", ns.StakeBadge(t.stake)))
	frame.sub:SetText(Subtitle(t))
	frame.burn:SetText(BurnText(t))

	local n, listed = 0, {}
	local function Name(name)
		return name == me and ("|cffffd100" .. ns.Short(name) .. "|r") or ns.Short(name)
	end
	local function Trade(name) return function() ns.Trade:Open(name) end end

	if t.state == "playing" and t.gs then
		for _, p in ipairs(t.gs.p) do
			n = n + 1
			listed[p[1]] = true
			SetRow(n, ("%s   |cffffffff%d|r  +%d   %s"):format(Name(p[1]), p[2], p[3], STATUS[p[4]]))
		end
	end
	for _, name in ipairs(t.seats) do
		if not listed[name] then
			n = n + 1
			listed[name] = true
			local balance, owes = Ledger.Balance(t, name), Ledger.Owes(t, name)
			local held = balance ~= 0 and ("  held " .. ns.Coins(balance)) or ""
			local status, label
			if name == t.host then
				status = "|cffffd100host|r"
			elseif owed[name] then
				status, label = "|cff66ccffcashing out|r", "Pay"
			elseif owes > 0 then
				status, label = ("|cffff6666owes %s|r"):format(ns.Coins(owes)), "Collect"
			else
				status = t.state == "playing" and "|cff999999sitting out|r" or "|cff66ff66ready|r"
			end
			SetRow(n, ("%s   %s%s"):format(Name(name), status, held), hosting and label or nil, Trade(name))
		end
	end
	for _, p in ipairs(payouts) do
		if not listed[p[1]] then
			n = n + 1
			SetRow(n, ("%s  |cff888888(left)|r  owed %s"):format(Name(p[1]), ns.Coins(p[2])), hosting and "Pay" or nil, Trade(p[1]))
		end
	end

	local left = {}
	if hosting then
		if t.state == "open" then
			buttons.stoke:SetEnabled(#Ledger.Eligible(t) >= 2)
			left[#left + 1] = buttons.stoke
			RefreshStake()
			stake:Show()
		elseif t.state == "playing" then
			buttons.roll:SetEnabled(Table:CanRoll())
			left[#left + 1] = buttons.roll
		end
		local name, label = NextTrade(t, payouts)
		if name and t.state ~= "playing" then
			buttons.next.name = name
			buttons.next:SetText(label)
			left[#left + 1] = buttons.next
		end
		local passing = Table:CanPass()
		buttons.leave:SetText(t.state == "settling" and "Put it out" or (passing and "Pass host & leave" or "Close table"))
		buttons.leave:SetWidth(passing and t.state ~= "settling" and 130 or 100)
	else
		local owes = Ledger.Owes(t, me)
		if owes > 0 and t.state ~= "settling" then
			buttons.pay:SetText("Pay host " .. ns.Coins(owes))
			buttons.pay:SetWidth(math.max(90, buttons.pay:GetFontString():GetStringWidth() + 20))
			left[#left + 1] = buttons.pay
		end
		if Ledger.Balance(t, me) > 0 and not owed[me] and t.state ~= "settling" then
			left[#left + 1] = buttons.cashout
		end
		buttons.leave:SetText("Leave")
		buttons.leave:SetWidth(80)
	end
	if t.state == "playing" then
		local stoking = false
		for _, p in ipairs(t.gs and t.gs.p or {}) do
			if p[1] == me then stoking = p[4] == 1 end
		end
		buttons.bank:SetEnabled(stoking)
		left[#left + 1] = buttons.bank
	end
	LayoutLeft(left)
	buttons.leave:Show()
end

function UI:Enable()
	local function refresh() self:Refresh() end
	Bonfire:RegisterEvent("BAG_UPDATE_DELAYED", refresh)
	Bonfire:RegisterEvent("PLAYER_REGEN_ENABLED", refresh)
	Bonfire:RegisterEvent("UNIT_AURA", function(_, unit) if unit == "player" then self:Refresh() end end)
	-- The fire timer ticks every second without redrawing the whole window.
	C_Timer.NewTicker(1, function()
		local t = ns.Table.current
		if frame and frame:IsShown() and t then frame.burn:SetText(BurnText(t)) end
	end)
end

function UI:Refresh()
	if not frame or not frame:IsShown() then return end
	ClearRows()
	local t = ns.Table.current
	if t then ShowTable(t) else ShowFires() end
end

function UI:Show()
	if not frame then Build() end
	frame:Show()
	self:Refresh()
end

function UI:Toggle()
	if frame and frame:IsShown() then frame:Hide() else self:Show() end
end

ns.AddCommand("reset", "- put the Bonfire window back at its default spot", function()
	Bonfire.db.global.pos, Bonfire.db.global.rangePos = nil, nil
	UI:Place()
	ns.Range:Place()
end)
