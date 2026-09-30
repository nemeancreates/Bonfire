local _, ns = ...
local Bonfire = ns.Bonfire
local Ledger = ns.Ledger

-- One small window with two modes: nearby fires (browse/host) and your table.
local UI = {}
ns.UI = UI

local ROWS = 10
local frame, rows, buttons, stake, pickButtons

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

UI.Button, UI.Tooltip = Button, Tooltip

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
			db.amount = math.max(ns.STAKE_STEP, math.min(ns.COIN_UNITS[db.unit].max, db.amount + sign * step))
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
		db.amount = math.min(db.amount, ns.COIN_UNITS[db.unit].max)
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
	if db.total == 0 and db.confirmed > 0 then
		stake.total:SetText(("Stake: %s  |cff999999Add coins, then Confirm, to change it|r"):format(ns.CoinString(db.confirmed)))
	else
		stake.total:SetText(("Bet: %s  %s"):format(db.total > 0 and ns.CoinString(db.total) or "|cff999999nothing yet|r",
			pending and "|cffffaa33(not confirmed)|r" or (db.total > 0 and "|cff66ff66confirmed|r" or "")))
	end
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
	frame:SetSize(380, 440)
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

	frame.money = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	frame.money:SetPoint("TOPLEFT", 14, -64)
	frame.money:SetPoint("RIGHT", -14, 0)
	frame.money:SetJustifyH("LEFT")
	frame.money:SetTextColor(0.8, 0.85, 0.7)

	frame.notice = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	frame.notice:SetPoint("BOTTOMLEFT", 14, 36)
	frame.notice:SetPoint("RIGHT", frame, "RIGHT", -14, 0)
	frame.notice:SetJustifyH("LEFT")
	frame.notice:SetTextColor(1, 0.4, 0.3)

	rows = {}
	for i = 1, ROWS do
		local row = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		row:SetPoint("TOPLEFT", 16, -68 - i * 22)
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
		oddroll = Button(frame, "Roll", 100, function() Table:OmoRoll() end),
		next = Button(frame, "Trade next", 150, function(self) ns.Trade:Open(self.name) end),
		pay = Button(frame, "Pay host", 130, function() Table:PayHost() end),
		cashout = Button(frame, "Cash out", 80, function() Table:CashOut() end),
		leave = Button(frame, "Leave", 90, function() Table:Leave() end),
	}
	buttons.leave:SetPoint("BOTTOMRIGHT", -12, 10)
	Tooltip(buttons.here, function()
		if ns.AtCampfire() then return "Open a table at the campfire you're standing at." end
		return "Hosting unlocks at your own campfire, or at anyone else's once you've rested there about a minute and have the Welcoming Campfire buff. You can also light one with a Basic Campfire Kit. /bf host skips this check."
	end)
	Tooltip(buttons.light, "Uses your Basic Campfire Kit. Your table opens as soon as the fire is lit.")
	Tooltip(buttons.stoke, function()
		local t = Table.current
		return ("Deal in everyone who's ready and start %s."):format(ns.GameName(t and t.game or "embers"))
	end)
	Tooltip(buttons.oddroll, "Rolls your die. Everyone rolls at once, and the host reads the rolls from chat.")
	Tooltip(buttons.leave, function()
		local t = Table.current
		if t and Table:IsHosting() then
			if t.state == "settling" then return "The table closes once everyone who's owed money has been paid back." end
			if Table:CanPass() then return "Leave the table. The player who joined first takes over as host while the fire burns." end
			return "Close the table for good. On a gold table you pay everyone back first."
		end
		return "Leave the table. You fold whatever you have in this round."
	end)
	Tooltip(buttons.next, "Open a trade with the next player in the queue. Both of you still click Trade.")

	BuildStake()

	-- The Odd Man Out: a number to pick, 1 to 20, in two rows (only as many as the die shows).
	pickButtons = {}
	for i = 1, 20 do
		local b = Button(frame, tostring(i), 32, function() Table:MakePick(i) end)
		b:SetPoint("BOTTOMLEFT", 12 + ((i - 1) % 10) * 34, 92 - math.floor((i - 1) / 10) * 26)
		b:Hide()
		pickButtons[i] = b
	end

	-- The game picker: a button that opens the list of games. Greyed entries aren't playable yet.
	UI.gameButton = Button(frame, "", 210, function() UI.gameMenu:SetShown(not UI.gameMenu:IsShown()) end)
	UI.gameButton:SetPoint("BOTTOMLEFT", 12, 94)
	Tooltip(UI.gameButton, "The game your table plays. Everyone at the fire plays it.")
	UI.gameMenu = CreateFrame("Frame", nil, UI.gameButton)
	UI.gameMenu:SetFrameStrata("DIALOG")
	UI.gameMenu:SetSize(218, #ns.GAME_LIST * 24 + 8)
	UI.gameMenu:SetPoint("BOTTOMLEFT", UI.gameButton, "TOPLEFT", 0, 2)
	local menuBg = UI.gameMenu:CreateTexture(nil, "BACKGROUND")
	menuBg:SetAllPoints()
	menuBg:SetColorTexture(0.1, 0.07, 0.03, 0.97)
	for i, entry in ipairs(ns.GAME_LIST) do
		local item = Button(UI.gameMenu, "", 210, function()
			Table:SetGame(entry.key)
			UI.gameMenu:Hide()
			UI:Refresh()
		end)
		item:SetPoint("TOPLEFT", 4, -4 - (i - 1) * 24)
		local label = ns.GameName(entry.key)
		item:SetText(entry.ready and label or ("|cff888888" .. label .. " (soon)|r"))
		item:SetEnabled(entry.ready)
		Tooltip(item, entry.blurb)
	end
	UI.gameMenu:Hide()
	UI.gameButton:Hide()

	-- Switches between the table and its side bets, when the table has a card.
	UI.viewButton = Button(frame, "Bets", 64, function()
		UI.view = UI.view == "bets" and "table" or "bets"
		UI:Refresh()
	end)
	UI.viewButton:SetHeight(20)
	UI.viewButton:SetPoint("TOPLEFT", 10, -4)
	Tooltip(UI.viewButton, function()
		local t = ns.Table.current
		if t and t.stake == 0 then return "Side bets use gold, so they're off on a For fun table. Switch to Gambling to use them." end
		return "Side bets for this table."
	end)
	UI.viewButton:Hide()
end

local function ClearRows()
	frame.burn:SetText("")
	frame.money:SetText("")
	for _, row in ipairs(rows) do
		row:SetText("")
		row.button:Hide()
	end
	for _, b in pairs(buttons) do
		if not Locked(b) then b:Hide() end
	end
	for _, b in ipairs(pickButtons) do b:Hide() end
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
	-- What the window can tell about a campfire near you: the buff, and how far the one you placed is.
	local buff, yards = ns.CampfireBuff(), ns.Table:PlacedDistance()
	local where = buff and ("You're at a campfire (" .. buff .. ").")
		or (yards and ("Your campfire is about %d yd away."):format(yards)) or ""
	frame.sub:SetText(#list == 0 and ((where ~= "" and (where .. " ") or "") .. "No other fires in range.") or where)
	local h = Bonfire.db.char.history
	if h and h.played > 0 then
		frame.money:SetText(("Your record: %d won, %d lost%s"):format(h.won, h.lost,
			(h.gained > 0 or h.spent > 0) and (", net " .. ns.SignedCoins(h.gained - h.spent)) or ""))
	end
	for i = 1, math.min(#list, ROWS) do
		local fire = list[i]
		local game = ns.Games[fire.game]
		local near = fire.distance and fire.distance <= ns.Table.FOLD_RANGE
		if fire.state == "camp" then
			-- A campfire someone lit, with no table yet: worth walking to, nothing to join.
			SetRow(i, ("%s's campfire  |cff999999no table yet  %s|r"):format(ns.Short(fire.host),
				fire.distance and ("%d yd"):format(fire.distance) or "far"))
		else
			SetRow(i, ("%s  %s  %d/%d %s  %s  |cff999999%s|r"):format(
					ns.Short(fire.host), game and game.name or "?", fire.seats or 0, fire.maxSeats or 0,
					ns.StakeBadge(fire.stake), ns.Coins(fire.stake), fire.distance and ("%d yd"):format(fire.distance) or "far"),
				"Join", function() ns.Table:Join(fire.host) end,
				near and fire.state ~= "settling" and (fire.seats or 0) < (fire.maxSeats or 0))
		end
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

-- The Odd Man Out: round, die, what to do now, and the clock.
local function OddSubtitle(gs)
	local left = gs.dl and gs.dl - GetServerTime()
	local clock = left and left >= 0 and ("  |cffffffff%ds|r"):format(left) or ""
	local reach = (gs.re or 0) > 0 and ("  |cffffcc33near misses count: within %d|r"):format(gs.re) or ""
	local wipe = gs.last and gs.last.w == 1 and "  |cffff6666wipeout, replaying|r" or ""
	local head = ("Round %d  |  d%d"):format(gs.r, gs.R)
	if gs.ph == "pick" then return head .. "  |  pick your number" .. clock end
	if gs.ph == "roll" then return head .. "  |  everyone roll!" .. clock .. reach .. wipe end
	return head
end

local function Subtitle(t)
	local gs = t.gs
	if t.state == "playing" and gs and t.game == "oddmanout" then
		return OddSubtitle(gs)
	elseif t.state == "playing" and gs then
		local last = ""
		if t.lastRoll == 1 then
			last = "   |cffff6666rolled a 1: fire out, unbanked pots lost|r"
		elseif t.lastRoll then
			last = ("   last roll: |cffffffff%d|r"):format(t.lastRoll)
		end
		return ("Round %d of %d%s"):format(gs.r, gs.R, last)
	elseif t.state == "settling" then
		return "Closing up: the host is paying everyone back."
	elseif t.winners and #t.winners > 0 then
		local names = {}
		for i, name in ipairs(t.winners) do names[i] = ns.Short(name) end
		local won = t.stake > 0 and t.share
			and ("  (" .. ns.Coins(t.share) .. " each, " .. ns.SignedCoins(t.share - t.stake) .. " profit)") or ""
		local wait = t.rematchAt and t.rematchAt - GetServerTime() or 0
		local nextGame = wait > 0 and ("  |cffffffffNext game in %ds: cash out now if you're done.|r"):format(wait) or ""
		return "Winner: |cff66ff66" .. table.concat(names, ", ") .. "|r" .. won .. nextGame
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

-- Who's holding what, in plain words, for the host and for each player.
local function MoneyLine(t)
	if t.stake == 0 then return "" end
	local me = ns.Me()
	if ns.Table:IsHosting() then
		local holding, incoming = 0, 0
		for _, name in ipairs(t.seats) do
			if name ~= me then holding = holding + math.max(0, Ledger.Balance(t, name)) end
		end
		for _, p in ipairs(Ledger.PayIns(t)) do incoming = incoming + p[2] end
		local parts = {}
		parts[#parts + 1] = holding > 0 and ("You're holding %s of players' credit; pay it out when they cash out."):format(ns.CoinString(holding))
			or "You aren't holding any player credit."
		if incoming > 0 then parts[#parts + 1] = ("Players still owe you %s to play."):format(ns.CoinString(incoming)) end
		return table.concat(parts, "  ")
	end
	local credit, owes = Ledger.Balance(t, me), Ledger.Owes(t, me)
	local r = t.tally and t.tally[me]
	local net = r and r.w + r.l > 0 and ("  Net here: " .. ns.SignedCoins(r.net)) or ""
	if owes > 0 and t.state ~= "settling" then
		return ("You owe the host %s to be dealt in.%s"):format(ns.CoinString(owes), net)
	elseif credit > 0 then
		return ("The host holds %s for you. Cash out to be paid.%s"):format(ns.CoinString(credit), net)
	end
	return "Nothing is being held for you." .. net
end

-- Queue of trades the host has to make: payouts first, then pay-ins.
local function NextTrade(t, payouts)
	if payouts[1] then return payouts[1][1], "Pay " .. ns.Short(payouts[1][1]) end
	if t.state == "settling" then return end
	local payins = Ledger.PayIns(t)
	if payins[1] then return payins[1][1], "Collect from " .. ns.Short(payins[1][1]) end
end

-- The Odd Man Out rows: who's in, who still owes a pick or roll, and who's out.
local function ShowOddRows(t, n, listed, Name)
	local gs, me = t.gs, ns.Me()
	local waiting, alive, outInfo, lastRoll = {}, {}, {}, {}
	for _, name in ipairs(gs.wait) do waiting[name] = true end
	for _, name in ipairs(gs.alive) do alive[name] = true end
	for _, o in ipairs(gs.out) do outInfo[o[1]] = o end
	if gs.last then
		for i, name in ipairs(gs.order) do
			if (gs.last.rl[i] or 0) > 0 then lastRoll[name] = gs.last.rl[i] end
		end
	end
	local mine = ns.Table.myPick
	local myPick = mine and (gs.ph ~= "pick" or mine.round == gs.r) and mine.n
	for _, name in ipairs(gs.order) do
		n = n + 1
		listed[name] = true
		local text
		if alive[name] then
			local status = waiting[name] and (gs.ph == "pick" and "|cffffaa33picking|r" or "|cffffaa33to roll|r") or "|cff66ff66ready|r"
			local extra = (name == me and myPick) and ("   your number |cffffffff%d|r"):format(myPick) or ""
			local rolled = lastRoll[name] and ("   last roll %d"):format(lastRoll[name]) or ""
			text = ("%s   %s%s|cff999999%s|r"):format(Name(name), status, extra, rolled)
		else
			local o = outInfo[name]
			text = ("%s   |cff888888%s%s|r"):format(Name(name), o and o[2] == 1 and "folded" or "knocked out",
				o and o[3] > 0 and ("  (picked " .. o[3] .. ")") or "")
		end
		SetRow(n, text)
	end
	return n
end

-- The Odd Man Out controls: the numbers to pick from, or the Roll button.
local function ShowOddControls(t, left)
	local gs, me = t.gs, ns.Me()
	if not gs then return end
	local alive, waitingMe = false, false
	for _, name in ipairs(gs.alive) do
		if name == me then alive = true end
	end
	for _, name in ipairs(gs.wait) do
		if name == me then waitingMe = true end
	end
	if not alive then return end
	if gs.ph == "pick" then
		local mine = ns.Table.myPick
		local picked = mine and mine.round == gs.r and mine.n
		for i, b in ipairs(pickButtons) do
			if i <= gs.R then
				b:SetText(i == picked and ("|cffffd100" .. i .. "|r") or tostring(i))
				b:Show()
			end
		end
	elseif gs.ph == "roll" then
		buttons.oddroll:SetText(("Roll d%d"):format(gs.R))
		buttons.oddroll:SetEnabled(waitingMe)
		left[#left + 1] = buttons.oddroll
	end
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
	frame.money:SetText(MoneyLine(t))
	frame.burn:SetText(BurnText(t))

	local n, listed = 0, {}
	local function Name(name)
		return name == me and ("|cffffd100" .. ns.Short(name) .. "|r") or ns.Short(name)
	end
	local function Trade(name) return function() ns.Trade:Open(name) end end

	if t.state == "playing" and t.gs and t.game == "oddmanout" then
		n = ShowOddRows(t, n, listed, Name)
	elseif t.state == "playing" and t.gs then
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
			local held = balance ~= 0 and ("  credit " .. ns.Coins(balance)) or ""
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
			local r = t.tally and t.tally[name]
			local record = r and r.w + r.l > 0
				and ("   |cff999999%dW %dL%s|r"):format(r.w, r.l, t.stake > 0 and (" net " .. ns.SignedCoins(r.net)) or "") or ""
			SetRow(n, ("%s   %s%s%s"):format(Name(name), status, held, record), hosting and label or nil, Trade(name))
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
			-- After a game the button becomes Rematch, held for a few seconds so players can cash out.
			local wait = t.rematchAt and t.rematchAt - GetServerTime() or 0
			local again = t.winners ~= nil
			local label = again and "Rematch" or (t.game == "embers" and "Stoke (Start)" or "Start")
			if wait > 0 then label = ("%s (%d)"):format(label, wait) end
			buttons.stoke:SetText(label)
			buttons.stoke:SetWidth(again and 110 or (t.game == "embers" and 110 or 70))
			buttons.stoke:SetEnabled(#Ledger.Eligible(t) >= 2 and wait <= 0)
			left[#left + 1] = buttons.stoke
			RefreshStake()
			stake:Show()
		elseif t.state == "playing" and t.game ~= "oddmanout" then
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
		if t.state == "settling" then
			buttons.leave:SetText(#payouts > 0 and "Pay everyone first" or "Close table")
			buttons.leave:SetWidth(130)
			buttons.leave:SetEnabled(#payouts == 0)
		else
			buttons.leave:SetText(passing and "Pass host & leave" or "Close table")
			buttons.leave:SetWidth(passing and 130 or 100)
			buttons.leave:SetEnabled(true)
		end
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
		buttons.leave:SetEnabled(true)
	end
	if t.state == "playing" and t.game == "oddmanout" then
		ShowOddControls(t, left)
	elseif t.state == "playing" then
		local canBank = false
		for _, p in ipairs(t.gs and t.gs.p or {}) do
			if p[1] == me then canBank = p[4] == 1 and p[3] > 0 end
		end
		buttons.bank:SetEnabled(canBank and GetTime() >= (Table.bankLockUntil or 0))
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
		if frame and frame:IsShown() and t then
			frame.burn:SetText(BurnText(t))
			if t.state == "open" and t.rematchAt and GetServerTime() <= t.rematchAt and UI.view ~= "bets" then
				UI:Refresh()  -- the rematch countdown
			end
			if t.state == "playing" and t.game == "oddmanout" and t.gs and UI.view ~= "bets" then
				frame.sub:SetText(Subtitle(t))  -- the pick and roll clock
			end
		end
		ns.BetsUI:Tick()
	end)
end

function UI:Refresh()
	if not frame or not frame:IsShown() then return end
	ClearRows()
	local t = ns.Table.current
	local market = t and t.market
	UI.viewButton:SetShown(market ~= nil)
	-- Side bets are gold bets: gray the tab out on a For fun table so it can't be used by accident.
	UI.viewButton:SetEnabled(market ~= nil and t.stake > 0)
	if not market or t.stake == 0 then UI.view = nil end
	-- The game picker: on the main menu, and at your own table between games.
	local inBets = market and UI.view == "bets"
	local pickable = not inBets and (not t or (ns.Table:IsHosting() and t.state == "open"))
	UI.gameButton:SetShown(pickable)
	if pickable then
		UI.gameButton:SetText(("Game: |cffffd100%s|r  v"):format(ns.GameName(t and t.game or ns.ChosenGame())))
	end
	if market and UI.view == "bets" then
		UI.viewButton:SetText("Table")
		frame.burn:SetText(BurnText(t))
		ns.BetsUI:Show(frame, t)
		buttons.leave:SetText(ns.Table:IsHosting() and "Close table" or "Leave")
		buttons.leave:SetWidth(100)
		buttons.leave:SetEnabled(true)
		buttons.leave:Show()
		return
	end
	ns.BetsUI:Hide()
	UI.viewButton:SetText("Bets")
	if t then ShowTable(t) else ShowFires() end
end

-- A red line near the bottom of the window for a few seconds, for when a click is refused.
function UI:Notice(text)
	if not frame or not frame:IsShown() then return end
	frame.notice:SetText(text)
	frame.noticeToken = (frame.noticeToken or 0) + 1
	local token = frame.noticeToken
	C_Timer.After(6, function()
		if frame.noticeToken == token then frame.notice:SetText("") end
	end)
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
