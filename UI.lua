local _, ns = ...
local Bonfire = ns.Bonfire
local Ledger = ns.Ledger

-- One small window with two modes: nearby fires (browse/host) and your table.
local UI = {}
ns.UI = UI

local ROWS = 10
local frame, rows, buttons, stake, pickButtons, park

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
	tinsert(UISpecialFrames, "BonfireFrame")  -- Esc closes it
	-- The X closes it too, wired straight to Hide rather than through Blizzard's panel manager.
	local close = frame.CloseButton or _G.BonfireFrameCloseButton
	if close then close:SetScript("OnClick", function() frame:Hide() end) end

	-- Where the secure Light a fire button waits while the window doesn't show it. A secure
	-- button inside the window (or anchored to it) makes the whole window protected, and the game
	-- then won't let the X or Esc hide it in combat. Parked here, the window is an ordinary frame.
	park = CreateFrame("Frame")
	park:Hide()
	frame:SetScript("OnHide", function()
		local light = buttons and buttons.light
		if light and not InCombatLockdown() and light:GetParent() ~= park then
			light:Hide()
			light:ClearAllPoints()
			light:SetParent(park)
		end
	end)

	local title = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	title:SetPoint("TOP", 0, -5)
	title:SetText("Bonfire")

	frame.burn = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	frame.burn:SetPoint("TOPRIGHT", -14, -30)

	frame.header = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	frame.header:SetPoint("TOPLEFT", 14, -32)
	frame.header:SetPoint("RIGHT", frame.burn, "LEFT", -8, 0)
	frame.header:SetJustifyH("LEFT")
	frame.header:SetWordWrap(false)

	-- Two short lines under the header: what's happening (it may run to a second line), and the
	-- money, one line, stacked below it so the two can never print over each other.
	frame.sub = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	frame.sub:SetPoint("TOPLEFT", 14, -50)
	frame.sub:SetPoint("RIGHT", -14, 0)
	frame.sub:SetJustifyH("LEFT")
	frame.sub:SetMaxLines(2)

	frame.money = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	frame.money:SetPoint("TOPLEFT", frame.sub, "BOTTOMLEFT", 0, -2)
	frame.money:SetPoint("RIGHT", -14, 0)
	frame.money:SetJustifyH("LEFT")
	frame.money:SetWordWrap(false)
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
		row:SetWordWrap(false)
		row.button = Button(frame, "", 64, function(self) self.action() end)
		row.button:SetPoint("RIGHT", frame, "RIGHT", -14, 0)
		row.button:SetPoint("TOP", row, "TOP", 0, 5)
		rows[i] = row
	end

	local Table = ns.Table
	buttons = {
		here = Button(frame, "Host at this fire", 130, function() Table:Host() end),
		light = SecureButton(park, "Light a fire", 110, function(self)
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
		oddroll = Button(frame, "Roll", 120, function() Table:OmoRoll() end),
		next = Button(frame, "Trade next", 150, function(self) ns.Trade:Open(self.name) end),
		pay = Button(frame, "Pay host", 130, function() Table:PayHost() end),
		cashout = Button(frame, "Cash out", 80, function() Table:CashOut() end),
		leave = Button(frame, "Leave", 90, function() Table:Leave() end),
		history = Button(frame, "History", 80, function()
			UI.view = UI.view ~= "history" and "history" or nil
			UI:Refresh()
		end),
	}
	-- The Honest Broker's question after a table: two rows of one-click answers, on rows 2 and 4.
	local function Answer(label, field, value, x, row)
		local b = Button(frame, label, 60, function() UI:Answer(field, value) end)
		b.field, b.value, b.label = field, value, label
		b:SetPoint("TOPLEFT", frame, "TOPLEFT", x, -68 - row * 22 + 5)
		return b
	end
	buttons.fairYes = Answer("Yes", "t", 1, 130, 2)
	buttons.fairNo = Answer("No", "t", -1, 194, 2)
	buttons.paceQuick = Answer("Quick", "p", 1, 130, 4)
	buttons.paceOk = Answer("OK", "p", 2, 194, 4)
	buttons.paceSlow = Answer("Slow", "p", 3, 258, 4)
	buttons.rateDone = Button(frame, "Skip", 110, function() UI:EndRating() end)
	buttons.rateDone:SetPoint("BOTTOMRIGHT", -12, 10)
	Tooltip(buttons.fairYes, "They paid out what they held and ran the table straight.")
	Tooltip(buttons.fairNo, "Something was off: money not paid out, or a table that didn't feel honest.")
	Tooltip(buttons.paceSlow, "Games dragged: long waits between rolls or starts.")
	-- An invite from a host: Join (or why not yet) on the left, No thanks on the right.
	buttons.acceptInvite = Button(frame, "Join", 90, function()
		local invite = UI.invite
		if invite then Table:Join(invite.host) end
	end)
	buttons.declineInvite = Button(frame, "No thanks", 90, function()
		UI.invite = nil
		if UI.view == "invite" then UI.view = nil end
		UI:Refresh()
	end)
	buttons.declineInvite:SetPoint("BOTTOMRIGHT", -12, 10)
	buttons.report = Button(frame, "Report", 80, function() ns.Log:Report() end)
	Tooltip(buttons.report, "Print the passive log in chat: which Bonfire users your addon heard, by which path, and what happened lately. It's always kept, and stays on this computer.")
	buttons.settingsBack = Button(frame, "Back", 80, function()
		UI.view = nil
		UI:Refresh()
	end)
	buttons.settingsBack:SetPoint("BOTTOMRIGHT", -12, 10)
	buttons.leave:SetPoint("BOTTOMRIGHT", -12, 10)
	buttons.history:SetPoint("BOTTOMRIGHT", -12, 10)
	Tooltip(buttons.history, "Your games, side bets and gold at Bonfire tables. Kept per character.")
	Tooltip(buttons.here, function()
		if ns.AtCampfire() then return "Open a table at the campfire you're standing at." end
		return "Hosting unlocks at your own campfire, or at anyone else's once you've rested there about a minute and have the Welcoming Campfire buff. You can also light one with a Basic Campfire Kit. /bf host skips this check."
	end)
	Tooltip(buttons.light, "Uses your Basic Campfire Kit. Your table opens as soon as the fire is lit.")
	Tooltip(buttons.stoke, function()
		local t = Table.current
		local text = ("Deal in everyone who's ready and start %s."):format(ns.GameName(t and t.game or "embers"))
		if t and t.stake > 0 then
			text = text .. ("\n%d of %d players are paid up. Anyone who hasn't paid sits this game out."):format(#Ledger.Eligible(t), #t.seats)
		end
		return text
	end)
	Tooltip(buttons.oddroll, "Rolls your die once a round. It lights up once everyone has picked a number; then everyone rolls at once and the host reads the rolls from chat.")
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

	-- Two tabs in the title bar at any table: the table, and its side bets.
	local function ViewTab(label, view, x)
		local b = Button(frame, label, 56, function()
			UI.view = view
			UI:Refresh()
		end)
		b:SetHeight(20)
		b:SetPoint("TOPLEFT", x, -4)
		b:Hide()
		return b
	end
	UI.tableButton = ViewTab("Table", "table", 10)
	UI.betsButton = ViewTab("Bets", "bets", 68)

	-- The gear, left of the X: the settings page.
	UI.gear = CreateFrame("Button", nil, frame)
	UI.gear:SetSize(18, 18)
	UI.gear:SetPoint("TOPRIGHT", -28, -3)
	UI.gear:SetNormalTexture("Interface\\Icons\\INV_Misc_Gear_01")
	UI.gear:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
	UI.gear:SetScript("OnClick", function()
		UI.view = UI.view ~= "settings" and "settings" or nil
		UI:Refresh()
	end)
	Tooltip(UI.gear, "Settings")

	-- The spyglass, left of the gear: ask every Bonfire user who can hear you to answer. Fills the
	-- fire list and a host's list of players nearby, and says in chat who answered and how.
	-- Rests 15 seconds between uses, so nobody can flood the channel with it.
	UI.pingButton = CreateFrame("Button", nil, frame)
	UI.pingButton:SetSize(18, 18)
	UI.pingButton:SetPoint("RIGHT", UI.gear, "LEFT", -4, 0)
	UI.pingButton:SetNormalTexture("Interface\\Icons\\INV_Misc_Spyglass_03")
	UI.pingButton:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
	UI.pingButton:SetScript("OnClick", function(self)
		if GetTime() - (self.at or -100) < 15 then return end
		self.at = GetTime()
		self:SetAlpha(0.4)
		C_Timer.After(15, function() self:SetAlpha(1) end)
		ns.Ping()
		if GetTime() - (ns.Beacon.lastHello or 0) > 5 then ns.Beacon:Hello() end
		UI:Notice("Looking for Bonfire users nearby...")
	end)
	Tooltip(UI.pingButton, "Look for Bonfire users and fires nearby. Anyone who can hear you answers: hosts show up in the fire list, players in a host's invite list, and chat says who answered.")

	-- The settings page: one switch a line, what it does in its tooltip.
	local SETTINGS = {
		{ "quips", "Quips", "Your character says a line and does an emote now and then, only on your own clicks in Bonfire." },
		{ "chatTab", "Bonfire chat tab", "Bonfire's messages in their own chat tab instead of your main chat.", function(on) ns.Chat:SetTab(on) end },
		{ "tableChat", "Table chat", "A chat channel for everyone at your table (Bonfire tells you its number when you sit down)." },
		{ "pins", "Map pins", "Fires on your minimap and world map.", function(on) ns.Beacon:SetPins(on) end },
		{ "askRating", "Ask how a table was", "After you've played at someone's table: paid out fair, and pace, one click each. Your answers build hosts' reputations." },
		{ "autoInvite", "Invite players who click Join", "Hosting: whoever clicks Join is seated and invited to your group straight away. Off: they wait on your table page until you click Let in." },
		{ "bigTables", "Tables of up to 10", "Hosting: up to 10 seats, your group turned into a raid past 5 (most quests don't give credit in a raid). Off: 5 seats, and the group stays a party.",
			function() ns.Table:SetSeatLimit() end },
	}
	UI.settings = CreateFrame("Frame", nil, frame)
	UI.settings:SetPoint("TOPLEFT", 12, -80)
	UI.settings:SetSize(356, #SETTINGS * 28)
	UI.settings:Hide()
	UI.checks = {}
	for i, s in ipairs(SETTINGS) do
		local box = CreateFrame("CheckButton", nil, UI.settings, "UICheckButtonTemplate")
		box:SetSize(26, 26)
		box:SetPoint("TOPLEFT", 0, -(i - 1) * 28)
		local label = UI.settings:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
		label:SetPoint("LEFT", box, "RIGHT", 4, 0)
		label:SetText(s[2])
		box:SetScript("OnClick", function(self)
			local on = self:GetChecked() and true or false
			Bonfire.db.global[s[1]] = on
			if s[4] then s[4](on) end
			UI:Refresh()
		end)
		Tooltip(box, s[3])
		UI.checks[i] = { box = box, key = s[1] }
	end
	Tooltip(UI.tableButton, "The table and its game.")
	Tooltip(UI.betsButton, function()
		local t = ns.Table.current
		if t and t.stake == 0 then return "Side bets use gold, so they're off on a For fun table. Switch to Gambling to use them." end
		return "Side bets for this table."
	end)
end

-- A refresh works out which widgets belong on screen. Hiding a button and showing it again in
-- the same refresh drops a click in progress (it's hidden between mouse down and mouse up), and
-- the window refreshes often (every table update, aura change and countdown tick). So a refresh
-- only marks what it shows with Use, and hides whatever it didn't mark at the end.
local used

local function Use(w)
	used[w] = true
	if not Locked(w) then w:Show() end
end

local function HideUnused()
	local marks = used
	used = nil
	local function check(w)
		if marks[w] or Locked(w) then return end
		w:Hide()
		if w.secure and w:GetParent() ~= park then
			w:ClearAllPoints()
			w:SetParent(park)
		end
	end
	for _, row in ipairs(rows) do check(row.button) end
	for _, b in pairs(buttons) do check(b) end
	for _, b in ipairs(pickButtons) do check(b) end
	check(stake)
	check(UI.settings)
end

local function ClearRows()
	frame.burn:SetText("")
	frame.money:SetText("")
	for _, row in ipairs(rows) do row:SetText("") end
end

-- Shows the given bottom-left buttons in order.
local function LayoutLeft(list)
	local prev
	for _, b in ipairs(list) do
		if not Locked(b) then
			b:ClearAllPoints()
			if prev then b:SetPoint("LEFT", prev, "RIGHT", 4, 0) else b:SetPoint("BOTTOMLEFT", 12, 10) end
		end
		Use(b)
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
		Use(row.button)
	end
end

-- True if name was dealt into the game being played (their stake is in the pot).
local function InGame(t, name)
	local gs = t.gs
	if t.state ~= "playing" or not gs then return false end
	for _, p in ipairs(gs.p or {}) do
		if p[1] == name then return true end
	end
	return tContains(gs.order or {}, name)
end

-- Your record: games, gold, streaks, side bets and anything you still owe from a table you left.
local function ShowHistory()
	frame.header:SetText("Your record")
	local lines = ns.Table:HistoryLines(4, 2)
	if #lines == 0 then
		frame.sub:SetText("No games yet. Play a round and your record shows up here.")
	else
		frame.sub:SetText(lines[1])
		frame.money:SetText(lines[2] or "")
		for i = 3, #lines do SetRow(i - 2, lines[i]) end
	end
	buttons.history:SetText("Back")
	Use(buttons.history)
end

-- How was the host's table? Asked once per visit when you leave or cash out; skippable.
local function ShowSettings()
	frame.header:SetText("Settings")
	frame.sub:SetText("Hover a switch to see what it does. They apply to all your characters.")
	for _, c in ipairs(UI.checks) do c.box:SetChecked(Bonfire.db.global[c.key] and true or false) end
	Use(UI.settings)
	LayoutLeft({ buttons.report })
	Use(buttons.settingsBack)
end

-- The fire row's button says why you can't join rather than just greying out.
local function JoinLabel(fire, near)
	if fire.state == "settling" then return "Closing" end
	if (fire.seats or 0) >= (fire.maxSeats or 0) then return "Full" end
	if not near then return "Too far" end
	return "Join"
end

-- A host invited you: what's on, how far, and Join (or why not yet) / No thanks.
local function ShowInvite()
	local host = UI.invite.host
	local fire = ns.Beacon.fires[host]
	local d = fire and ns.Beacon:Distance(fire)
	local game = fire and ns.Games[fire.game]
	frame.header:SetText(("%s invites you to their fire"):format(ns.Short(host)))
	frame.sub:SetText(fire and ("%s, %s, %d/%d seated.  Host: %s"):format(game and game.name or "?", ns.Coins(fire.stake),
		fire.seats or 0, fire.maxSeats or 0, ns.Broker:Badge(host)) or "")
	frame.money:SetText(d and (d <= ns.Table.FOLD_RANGE and ("It's %d yd away: close enough to join."):format(d)
		or ("It's %d yd away. Walk within %d yd to join."):format(d, ns.Table.FOLD_RANGE)) or "")
	SetRow(2, "Joining adds you to their group, so the table")
	SetRow(3, "can reach you. You leave it when you leave.")
	local label = fire and JoinLabel(fire, d and d <= ns.Table.FOLD_RANGE) or "Join"
	buttons.acceptInvite:SetText(label)
	buttons.acceptInvite:SetEnabled(label == "Join")
	LayoutLeft({ buttons.acceptInvite })
	Use(buttons.declineInvite)
end

local function ShowRating()
	local r = UI.rating
	frame.header:SetText(("How was %s's table?"):format(ns.Short(r.host)))
	frame.sub:SetText("One click each, both optional. Your word travels to players you pass, so good hosts get known.")
	SetRow(2, "Paid out fair?")
	SetRow(4, "Pace")
	for _, b in ipairs({ buttons.fairYes, buttons.fairNo, buttons.paceQuick, buttons.paceOk, buttons.paceSlow }) do
		b:SetText(r.answers[b.field] == b.value and ("|cffffd100" .. b.label .. "|r") or b.label)
		Use(b)
	end
	buttons.rateDone:SetText(r.seated and "Back to table" or ((r.answers.t or r.answers.p) and "Done" or "Skip"))
	Use(buttons.rateDone)
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
			SetRow(i, ("%s %s  %s  %d/%d %s  %s  |cff999999%s|r"):format(
					ns.Short(fire.host), ns.Broker:Badge(fire.host), game and game.name or "?", fire.seats or 0, fire.maxSeats or 0,
					ns.StakeBadge(fire.stake), ns.Coins(fire.stake), fire.distance and ("%d yd"):format(fire.distance) or "far"),
				JoinLabel(fire, near), function() ns.Table:Join(fire.host) end, JoinLabel(fire, near) == "Join")
		end
	end
	RefreshStake()
	Use(stake)
	buttons.history:SetText("History")
	Use(buttons.history)

	-- At a campfire: host there. Otherwise light one with the kit, or explain what's missing.
	local atFire, kit = ns.AtCampfire(), ns.FindCampfireKit()
	if not atFire and kit and not InCombatLockdown() then
		buttons.light:SetParent(frame)  -- out of combat here; parked again when it's not shown
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
	local reach = (gs.re or 0) > 0 and ("  |cffffcc33near misses within %d|r"):format(gs.re) or ""
	local wipe = gs.last and gs.last.w == 1 and "  |cffff6666wipeout, replay|r" or ""
	local head = ("Round %d, d%d:"):format(gs.r, gs.R)
	if gs.ph == "pick" then return head .. " pick your number" .. clock end
	if gs.ph == "roll" then return head .. " everyone roll!" .. clock .. reach .. wipe end
	return head
end

local function Subtitle(t)
	local gs = t.gs
	if t.state == "playing" and gs and t.game == "oddmanout" then
		return OddSubtitle(gs)
	elseif t.state == "playing" and gs then
		local last = ""
		if t.lastRoll == 1 then
			last = "   |cffff6666a 1: fire out, pots lost|r"
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
			and ("  " .. ns.SignedCoins(t.share - t.stake) .. (#t.winners > 1 and " each" or "")) or ""
		local wait = t.rematchAt and t.rematchAt - GetServerTime() or 0
		local nextGame = wait > 0 and ("  |cffffffffnext game in %ds|r"):format(wait) or ""
		return "Winner: |cff66ff66" .. table.concat(names, ", ") .. "|r" .. won .. nextGame
	elseif t.stake > 0 then
		-- Only paid-up players are dealt in; say how many that is, so nobody's surprised.
		local ready, seated = #Ledger.Eligible(t), #t.seats
		if ready < seated then
			return ("Stake %s. %d of %d paid up; the unpaid sit out."):format(ns.Coins(t.stake), ready, seated)
		end
		return ("Stake %s. Everyone's paid up."):format(ns.Coins(t.stake))
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
		local parts = {}
		if t.state == "playing" then
			-- Stakes in the running game have left everyone's credit for the pot. Counting them
			-- as owed would read as if players were dealt in without paying.
			parts[#parts + 1] = ("In the pot: %s."):format(ns.CoinString(t.stake * #(t.committed or {})))
			if holding > 0 then parts[#parts + 1] = ("You also hold %s for players."):format(ns.CoinString(holding)) end
			return table.concat(parts, "  ")
		end
		for _, p in ipairs(Ledger.PayIns(t)) do incoming = incoming + p[2] end
		parts[#parts + 1] = holding > 0 and ("You hold %s for players."):format(ns.CoinString(holding)) or "You hold no player credit."
		if incoming > 0 then parts[#parts + 1] = ("Owed to you: %s."):format(ns.CoinString(incoming)) end
		return table.concat(parts, "  ")
	end
	local credit, owes = Ledger.Balance(t, me), Ledger.Owes(t, me)
	local r = t.tally and t.tally[me]
	local net = r and r.w + r.l > 0 and ("  Net " .. ns.SignedCoins(r.net)) or ""
	if InGame(t, me) then
		local extra = credit > 0 and ("  Host also holds %s."):format(ns.CoinString(credit)) or ""
		return ("Your stake is in the pot.%s%s"):format(extra, net)
	elseif owes > 0 and t.state ~= "settling" then
		return ("Pay the host %s to be dealt in.%s"):format(ns.CoinString(owes), net)
	elseif credit > 0 then
		return ("Host holds %s for you; Cash out to collect.%s"):format(ns.CoinString(credit), net)
	end
	return "Nothing is held for you." .. net
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
				Use(b)
			end
		end
		-- Roll stays in view but greyed until the last pick is in, so it's clear what comes next.
		buttons.oddroll:SetText(picked and "Others picking..." or ("Roll d%d"):format(gs.R))
		buttons.oddroll:SetEnabled(false)
		left[#left + 1] = buttons.oddroll
	elseif gs.ph == "roll" then
		-- Spent the moment it's clicked, so a second click can't send a second /roll.
		local _, canRoll = ns.Table:OmoRollInfo()
		buttons.oddroll:SetText(canRoll and ("Roll d%d"):format(gs.R) or (waitingMe and "Rolling..." or "Rolled"))
		buttons.oddroll:SetEnabled(canRoll or false)
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

	-- Players see the host's reputation; a host with practice players at a gold table is told
	-- nobody else can see it.
	local badge = hosting and ((t.stake > 0 and Table:HasBots()) and " |cffff6666practice, hidden|r" or "")
		or (" " .. ns.Broker:Badge(t.host))
	frame.header:SetText(("%s's fire%s  |cffffffff%s|r %s"):format(ns.Short(t.host), badge, game and game.name or "?", ns.StakeBadge(t.stake)))
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

	-- Host with room at the table: Bonfire users nearby who aren't at a table, with Invite.
	local open = hosting and t.state ~= "settling" and #t.seats < t.maxSeats and not (t.stake > 0 and Table:HasBots())
	local requests = open and Table:Requests() or {}
	local asking = {}
	for _, r in ipairs(requests) do asking[r.name] = true end
	local nearby = open and ns.Beacon:Nearby(60) or {}
	local shown = {}
	for _, p in ipairs(nearby) do
		if not listed[p.name] and not asking[p.name] then shown[#shown + 1] = p end
	end
	if (#requests > 0 or #shown > 0) and n + 2 <= ROWS then
		n = n + 1
		SetRow(n, "|cff999999Bonfire players nearby|r")
		for _, r in ipairs(requests) do
			if n >= ROWS then break end
			n = n + 1
			SetRow(n, ("%s   |cffffd100asks to join|r"):format(ns.Short(r.name)), "Let in", function() Table:LetIn(r.name) end)
		end
		for _, p in ipairs(shown) do
			if n >= ROWS then break end
			n = n + 1
			local invited = Table:WasInvited(p.name)
			SetRow(n, ("%s   |cff999999%s|r"):format(ns.Short(p.name), p.distance and ("%d yd"):format(p.distance) or "nearby"),
				invited and "Invited" or "Invite", function() Table:InvitePlayer(p.name) end, not invited)
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
			Use(stake)
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
		-- Mid-game your stake is in the pot, so what you "owe" is for the next game: no Pay button yet.
		local owes = Ledger.Owes(t, me)
		if owes > 0 and t.state ~= "settling" and not InGame(t, me) then
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
	Use(buttons.leave)
end

function UI:Enable()
	local function refresh() self:Refresh() end
	ns.OnEvent("BAG_UPDATE_DELAYED", refresh)
	ns.OnEvent("PLAYER_REGEN_ENABLED", refresh)
	ns.OnEvent("UNIT_AURA", function(_, unit) if unit == "player" then self:Refresh() end end)
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

local function Draw()
	local t = ns.Table.current
	-- At a table: the Table and Bets tabs. Side bets are gold bets, so Bets is greyed on a For fun
	-- table so it can't be used by accident.
	UI.tableButton:SetShown(t ~= nil)
	UI.betsButton:SetShown(t ~= nil)
	UI.betsButton:SetEnabled(t ~= nil and t.stake > 0)
	if UI.view == "bets" and (not t or t.stake == 0) then UI.view = nil end
	if UI.view == "history" and t then UI.view = nil end  -- sitting down takes you to the table
	local r = UI.rating
	if r and (GetTime() - r.at > 900 or (t and t.host ~= r.host)) then UI.rating, r = nil, nil end
	if UI.view == "rate" and not r then UI.view = nil end
	if UI.invite and (t or GetTime() - UI.invite.at > 120) then UI.invite = nil end
	if UI.view == "invite" and not UI.invite then UI.view = nil end
	local inBets = UI.view == "bets"
	-- The tab you're on shows in gold.
	UI.tableButton:SetText(inBets and "Table" or "|cffffd100Table|r")
	UI.betsButton:SetText(inBets and "|cffffd100Bets|r" or "Bets")
	-- The game picker: on the main menu, and at your own table between games.
	local pickable = not inBets and UI.view ~= "history" and UI.view ~= "rate" and UI.view ~= "invite" and UI.view ~= "settings"
		and (not t or (ns.Table:IsHosting() and t.state == "open"))
	UI.gameButton:SetShown(pickable)
	if pickable then
		UI.gameButton:SetText(("Game: |cffffd100%s|r  v"):format(ns.GameName(t and t.game or ns.ChosenGame())))
	end
	if inBets then
		frame.burn:SetText(BurnText(t))
		ns.BetsUI:Show(frame, t)
		buttons.leave:SetText(ns.Table:IsHosting() and "Close table" or "Leave")
		buttons.leave:SetWidth(100)
		buttons.leave:SetEnabled(true)
		Use(buttons.leave)
		return
	end
	ns.BetsUI:Hide()
	if UI.view == "settings" then return ShowSettings() end
	if UI.view == "rate" then return ShowRating() end
	if UI.view == "invite" then return ShowInvite() end
	if UI.view == "history" then return ShowHistory() end
	if t then ShowTable(t) else ShowFires() end
end

function UI:Refresh()
	if not frame or not frame:IsShown() or used then return end  -- already drawing: that draw covers it
	used = {}
	ClearRows()
	local ok, err = pcall(Draw)
	HideUnused()  -- also clears `used`, so an error can't leave the window stuck
	if not ok then geterrorhandler()(err) end
end

-- The Honest Broker asks how a host's table was. If the window is closed it waits there (for a
-- quarter of an hour) and chat says so, rather than popping up on someone walking away.
-- seated: asked at Cash out, so the page offers a way back to the table.
function UI:AskRating(host, seated)
	UI.rating = { host = host, seated = seated, at = GetTime(), answers = {} }
	UI.view = "rate"
	if frame and frame:IsShown() then return self:Refresh() end
	Bonfire:Printf("How was %s's table? Open /bf to rate it: one click, and you can skip it.", ns.Short(host))
end

function UI:Answer(field, value)
	local r = UI.rating
	if not r then return end
	r.answers[field] = value
	ns.Broker:Rate(r.host, { [field] = value })
	-- Both answered: done, back to where you were.
	if r.answers.t and r.answers.p then
		C_Timer.After(0.8, function()
			if UI.rating == r then UI:EndRating() end
		end)
	end
	self:Refresh()
end

function UI:EndRating()
	UI.rating = nil
	if UI.view == "rate" then UI.view = nil end
	self:Refresh()
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
	-- Opening Bonfire tells hosts nearby you're around, so they can invite you.
	if GetTime() - (ns.Beacon.lastHello or 0) > 10 then ns.Beacon:Hello() end
end

-- A host invited us to their fire: the window opens on the invite (it's for you, from a player).
function UI:ShowInvite(host)
	UI.invite = { host = host, at = GetTime() }
	UI.view = "invite"
	Bonfire:Printf("%s invites you to their fire. /bf to answer.", ns.Short(host))
	self:Show()
end

function UI:Toggle()
	if frame and frame:IsShown() then frame:Hide() else self:Show() end
end

ns.AddCommand("settings", "- Bonfire's settings (also the gear in the window's title bar)", function()
	UI.view = "settings"
	UI:Show()
end)

ns.AddCommand("reset", "- put the Bonfire window back at its default spot", function()
	Bonfire.db.global.pos, Bonfire.db.global.rangePos = nil, nil
	UI:Place()
	ns.Range:Place()
end)
