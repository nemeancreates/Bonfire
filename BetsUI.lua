local _, ns = ...
local Bonfire = ns.Bonfire
local Bets = ns.Bets

-- The side-bets view, on the Bets tab of the main window: pick a round, see each side's
-- pool and what a bet would win, build a bet and place it. The host also sets the cut,
-- opens new rounds, locks them, declares winners, and collects what bettors owe.
local BetsUI = {}
ns.BetsUI = BetsUI

local MAX_SIDES, OWE_ROWS, PAY_ROWS = 6, 3, 8
local MAX_ROUNDS = Bets.MAX_ROUNDS  -- one button per round across the top; the card holds no more
local SIDE_COLORS = { { 0.4, 0.8, 1 }, { 1, 0.67, 0.2 }, { 0.6, 0.9, 0.4 }, { 0.9, 0.5, 0.9 }, { 1, 0.85, 0.3 }, { 0.9, 0.4, 0.4 } }
local SIDE_HEX = {}
for i, c in ipairs(SIDE_COLORS) do SIDE_HEX[i] = ("|cff%02x%02x%02x"):format(c[1] * 255, c[2] * 255, c[3] * 255) end
local STATE_COLOR = { open = "ffffff", locked = "ffcc33", done = "66ff66", void = "888888" }
local STATE_TEXT = { open = "betting open", locked = "bets locked", done = "finished", void = "called off" }

local root, w
local viewRound
local viewPayments, lastPhase  -- the payment window: shown once every round is locked
local adding = false  -- the host is naming a new round
local mode = 1        -- index into Bets.MODES for the new round

-- The bet you're building: what you've added up, or the amount on the dial if nothing's added.
local function Pending()
	local db = Bonfire.db.global.bet
	return db.total > 0 and db.total or db.amount * ns.COIN_UNITS[db.unit].copper
end

-- "Oppa vs Gopher" (or "vs.") -> { "Oppa", "Gopher" } (two to six sides)
local function ParseSides(text)
	local sides = {}
	for part in (text:gsub("%s+[vV][sS]%.?%s+", "|")):gmatch("[^|]+") do
		part = strtrim(part)
		if part ~= "" then sides[#sides + 1] = part end
	end
	if #sides >= 2 and #sides <= MAX_SIDES then return sides end
end

-- The round's sides come from two boxes with "vs" fixed between them, so nobody has to type it
-- and the addon always knows who's against whom. More than two sides: keep going in the second
-- box ("Gopher vs Toad").
local function SubmitRound()
	local a, b = strtrim(w.sideA:GetText() or ""), strtrim(w.sideB:GetText() or "")
	if a == "" or b == "" then return ns.Table:Refuse("Name both sides, one in each box: Oppa vs Gopher.") end
	local sides = ParseSides(a .. " vs " .. b)
	if not sides then
		return ns.Table:Refuse(("Two to %d sides: one in the first box, the rest in the second (Gopher vs Toad)."):format(MAX_SIDES))
	end
	local ri = ns.Table:AddRound(sides, 120, Bets.MODES[mode])
	if ri then viewRound = ri end
	adding = false
	w.sideA:ClearFocus()
	w.sideB:ClearFocus()
	ns.UI:Refresh()
end

local function CancelRound()
	w.sideA:ClearFocus()
	w.sideB:ClearFocus()
	adding = false
	ns.UI:Refresh()
end

local function Build(frame)
	local UI = ns.UI
	local db = Bonfire.db.global.bet
	root = CreateFrame("Frame", nil, frame)
	root:SetAllPoints()
	root:SetScript("OnHide", function()
		if w and w.menu then w.menu:Hide() end
	end)
	w = { rounds = {}, sides = {}, owe = {}, pays = {} }

	for i = 1, MAX_ROUNDS do
		local b = UI.Button(root, tostring(i), 34, function()
			viewRound = i
			ns.UI:Refresh()
		end)
		b:SetPoint("TOPLEFT", 14 + (i - 1) * 38, -50)
		w.rounds[i] = b
	end
	w.pool = root:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	w.pool:SetPoint("TOPRIGHT", -14, -56)

	w.clock = root:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	w.clock:SetPoint("TOPRIGHT", -14, -78)
	w.title = root:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	w.title:SetPoint("TOPLEFT", 14, -78)
	w.title:SetPoint("RIGHT", w.clock, "LEFT", -8, 0)
	w.title:SetJustifyH("LEFT")

	for i = 1, MAX_SIDES do
		local row = {}
		row.text = root:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		row.text:SetPoint("TOPLEFT", 16, -100 - (i - 1) * 24)
		row.text:SetPoint("RIGHT", root, "RIGHT", -88, 0)
		row.text:SetJustifyH("LEFT")
		row.text:SetWordWrap(false)
		row.bar = root:CreateTexture(nil, "ARTWORK")
		row.bar:SetHeight(3)
		row.bar:SetPoint("TOPLEFT", row.text, "BOTTOMLEFT", 0, -2)
		row.button = UI.Button(root, "Bet", 64, function() BetsUI:Click(i) end)
		row.button:SetPoint("RIGHT", root, "RIGHT", -14, 0)
		row.button:SetPoint("TOP", row.text, "TOP", 0, 6)
		UI.Tooltip(row.button, function()
			if row.button:GetText() == "Winner" then return "Declare this side the winner." end
			if BetsUI.hasBet then return "You already have a bet on this round. Cancel it first if you want to change it." end
			return "Bet on this side."
		end)
		w.sides[i] = row
	end

	-- What you've bet, or (for the host) who still owes.
	w.mine = root:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	w.mine:SetPoint("TOPLEFT", 16, -250)
	w.mine:SetPoint("RIGHT", root, "RIGHT", -14, 0)
	w.mine:SetJustifyH("LEFT")
	w.mine:SetJustifyV("TOP")
	w.mine:SetHeight(96)
	for i = 1, OWE_ROWS do
		local row = {}
		row.text = root:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		row.text:SetPoint("TOPLEFT", 16, -252 - (i - 1) * 22)
		row.text:SetPoint("RIGHT", root, "RIGHT", -90, 0)
		row.text:SetJustifyH("LEFT")
		row.button = UI.Button(root, "Collect", 70, function(self) ns.Trade:Open(self.name) end)
		row.button:SetPoint("RIGHT", root, "RIGHT", -14, 0)
		row.button:SetPoint("TOP", row.text, "TOP", 0, 6)
		UI.Tooltip(row.button, "Opens a trade with them. Their side fills in what they owe; once you both accept, they're marked paid automatically.")
		w.owe[i] = row
	end

	-- The payment window: everyone's total bet and what they still owe.
	for i = 1, PAY_ROWS do
		local row = {}
		row.text = root:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		row.text:SetPoint("TOPLEFT", 16, -102 - (i - 1) * 22)
		row.text:SetPoint("RIGHT", root, "RIGHT", -90, 0)
		row.text:SetJustifyH("LEFT")
		row.text:SetWordWrap(false)
		row.button = UI.Button(root, "Collect", 70, function(self) ns.Trade:Open(self.name) end)
		row.button:SetPoint("RIGHT", root, "RIGHT", -14, 0)
		row.button:SetPoint("TOP", row.text, "TOP", 0, 6)
		UI.Tooltip(row.button, "Opens a trade with them. Their side fills in what they owe; once you both accept, they're marked paid automatically.")
		w.pays[i] = row
	end
	-- Switches between the rounds and the payment window once every round is locked. It sits
	-- on the right of the title bar, clear of the Table and Bets tabs on the left.
	w.toggle = UI.Button(root, "Payments", 80, function()
		viewPayments = not viewPayments
		ns.UI:Refresh()
	end)
	w.toggle:SetHeight(20)
	w.toggle:SetPoint("TOPRIGHT", -74, -4)  -- clear of the spyglass, the gear and the X
	w.toggle:Hide()

	-- Bet builder: [-] 5(coin) [+] [coin] [Add]   /   Bet: total   [Clear]
	local function Step(sign)
		return function()
			local step = IsShiftKeyDown() and ns.STAKE_STEP_BIG or ns.STAKE_STEP
			db.amount = math.max(ns.STAKE_STEP, math.min(ns.COIN_UNITS[db.unit].max, db.amount + sign * step))
			ns.UI:Refresh()
		end
	end
	w.less = UI.Button(root, "-", 24, Step(-1))
	w.less:SetPoint("BOTTOMLEFT", 12, 66)
	w.amount = root:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	w.amount:SetPoint("LEFT", w.less, "RIGHT", 4, 0)
	w.amount:SetWidth(56)
	w.more = UI.Button(root, "+", 24, Step(1))
	w.more:SetPoint("LEFT", w.amount, "RIGHT", 4, 0)
	w.unit = UI.Button(root, "", 36, function()
		db.unit = db.unit % #ns.COIN_UNITS + 1
		db.amount = math.min(db.amount, ns.COIN_UNITS[db.unit].max)
		ns.UI:Refresh()
	end)
	w.unit:SetPoint("LEFT", w.more, "RIGHT", 4, 0)
	w.add = UI.Button(root, "Add", 48, function()
		db.total = math.min(ns.BET_CAP, db.total + db.amount * ns.COIN_UNITS[db.unit].copper)
		ns.UI:Refresh()
	end)
	w.add:SetPoint("LEFT", w.unit, "RIGHT", 4, 0)
	w.clear = UI.Button(root, "Clear", 50, function()
		db.total = 0
		ns.UI:Refresh()
	end)
	w.clear:SetPoint("BOTTOMRIGHT", -12, 42)
	w.total = root:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	w.total:SetPoint("BOTTOMLEFT", 14, 48)
	w.total:SetPoint("RIGHT", w.clear, "LEFT", -6, 0)
	w.total:SetJustifyH("LEFT")
	w.builder = { w.less, w.amount, w.more, w.unit, w.add, w.clear, w.total }
	UI.Tooltip(w.add, "Adds this amount to your bet. Switch coin type and add again to mix gold, silver and copper.")
	UI.Tooltip(w.clear, "Start the bet over.")

	-- Host: the cut, a four-stop slider (2, 5, 10, 20 percent).
	w.cutRow = CreateFrame("Frame", nil, root)
	w.cutRow:SetSize(356, 30)
	w.cutRow:SetPoint("BOTTOMLEFT", 12, 92)
	local label = w.cutRow:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	label:SetPoint("LEFT", 2, 5)
	label:SetText("Host cut")
	w.cut = CreateFrame("Slider", nil, w.cutRow)
	w.cut:SetSize(200, 16)
	w.cut:SetPoint("LEFT", 70, 5)
	w.cut:SetOrientation("HORIZONTAL")
	w.cut:SetMinMaxValues(1, #Bets.CUTS)
	w.cut:SetValueStep(1)
	w.cut:SetObeyStepOnDrag(true)
	local track = w.cut:CreateTexture(nil, "BACKGROUND")
	track:SetPoint("LEFT")
	track:SetPoint("RIGHT")
	track:SetHeight(4)
	track:SetColorTexture(0.45, 0.38, 0.22, 1)
	w.cut:SetThumbTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal")
	for i, pct in ipairs(Bets.CUTS) do
		local stop = w.cutRow:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		stop:SetPoint("TOP", w.cut, "BOTTOMLEFT", (i - 1) / (#Bets.CUTS - 1) * 200, -1)
		stop:SetText(pct .. "%")
	end
	w.cutNote = w.cutRow:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	w.cutNote:SetPoint("LEFT", w.cut, "RIGHT", 8, 0)
	w.cut:SetScript("OnValueChanged", function(_, value, byUser)
		if byUser then ns.Table:SetCut(Bets.CUTS[math.floor(value + 0.5)]) end
	end)
	UI.Tooltip(w.cutRow, "The share of every pot the host keeps. Locked once bets are in, so the odds can't change under anyone.")

	-- Host: naming a new round. [mode] [Oppa___] vs [Gopher___] [Open] [X]
	w.newRow = CreateFrame("Frame", nil, root)
	w.newRow:SetSize(356, 24)
	w.newRow:SetPoint("BOTTOMLEFT", 12, 94)
	w.mode = UI.Button(w.newRow, "", 96, function() w.menu:SetShown(not w.menu:IsShown()) end)
	w.mode:SetPoint("LEFT")
	UI.Tooltip(w.mode, "What kind of round this is. Everyone sees it in the betting window.")

	-- The game list drops up from the mode button.
	w.menu = CreateFrame("Frame", nil, w.newRow)
	w.menu:SetFrameStrata("DIALOG")
	w.menu:SetSize(120, #Bets.MODES * 22 + 8)
	w.menu:SetPoint("BOTTOMLEFT", w.mode, "TOPLEFT", 0, 2)
	local menuBg = w.menu:CreateTexture(nil, "BACKGROUND")
	menuBg:SetAllPoints()
	menuBg:SetColorTexture(0.1, 0.07, 0.03, 0.97)
	for i, name in ipairs(Bets.MODES) do
		local item = UI.Button(w.menu, name, 112, function()
			mode = i
			w.menu:Hide()
			ns.UI:Refresh()
		end)
		item:SetPoint("TOPLEFT", 4, -4 - (i - 1) * 22)
	end
	w.menu:Hide()

	local function SideBox(tip)
		local box = CreateFrame("EditBox", nil, w.newRow)
		box:SetSize(70, 20)
		box:SetAutoFocus(false)
		box:SetFontObject("GameFontHighlight")
		box:SetTextInsets(5, 5, 0, 0)
		box:SetMaxLetters(40)
		local bg = box:CreateTexture(nil, "BACKGROUND")
		bg:SetAllPoints()
		bg:SetColorTexture(0, 0, 0, 0.55)
		-- Lit up while it has your keyboard: if it isn't, typing goes to your keybinds.
		box:SetScript("OnEditFocusGained", function(self)
			bg:SetColorTexture(0.32, 0.25, 0.06, 0.95)
			self:HighlightText()
		end)
		box:SetScript("OnEditFocusLost", function(self)
			bg:SetColorTexture(0, 0, 0, 0.55)
			self:HighlightText(0, 0)
		end)
		box:SetScript("OnEnterPressed", SubmitRound)
		box:SetScript("OnEscapePressed", CancelRound)
		UI.Tooltip(box, tip)
		return box
	end
	w.sideA = SideBox("The first side. Click to type: the box lights up while it has your keyboard. Tab goes to the other side, Enter opens the round.")
	w.sideA:SetPoint("LEFT", w.mode, "RIGHT", 6, 0)
	w.vs = w.newRow:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	w.vs:SetPoint("LEFT", w.sideA, "RIGHT", 4, 0)
	w.vs:SetText("vs")
	w.sideB = SideBox("The other side. More than two? Keep going here: Gopher vs Toad.")
	w.sideB:SetPoint("LEFT", w.vs, "RIGHT", 4, 0)
	w.sideA:SetScript("OnTabPressed", function() w.sideB:SetFocus() end)
	w.sideB:SetScript("OnTabPressed", function() w.sideA:SetFocus() end)
	w.open = UI.Button(w.newRow, "Open", 46, SubmitRound)
	w.open:SetPoint("LEFT", w.sideB, "RIGHT", 4, 0)
	w.dismiss = UI.Button(w.newRow, "X", 24, CancelRound)
	w.dismiss:SetPoint("LEFT", w.open, "RIGHT", 4, 0)

	-- Bottom-left actions.
	w.lock = UI.Button(root, "Lock bets", 78, function()
		if IsShiftKeyDown() then ns.Table:LockAll() else ns.Table:LockRound(viewRound) end
	end)
	w.void = UI.Button(root, "Call off", 90, function()
		local t = ns.Table.current
		if t and t.market and Bets.CanRemove(t, viewRound) then
			ns.Table:RemoveRound(viewRound)
		else
			ns.Table:VoidRound(viewRound)
		end
	end)
	w.new = UI.Button(root, "New round", 80, function()
		local last = ns.Table.current and ns.Table.current.market and ns.Table.current.market.rounds
		last = last and last[#last]
		adding = true
		-- Start from the last round's sides (a rematch is one Enter away), or empty boxes.
		w.sideA:SetText(last and last.sides[1] or "")
		w.sideB:SetText(last and table.concat(last.sides, " vs ", 2) or "")
		if last then
			for i, m in ipairs(Bets.MODES) do
				if m == last.game then mode = i end
			end
		end
		ns.UI:Refresh()
		-- Give the click a moment to finish, or it takes the keyboard back.
		C_Timer.After(0.05, function() w.sideA:SetFocus() end)
	end)
	w.pay = UI.Button(root, "Pay host", 150, function() ns.Table:PayHost() end)
	w.start = UI.Button(root, "Start games", 140, function() ns.Table:BeginGames() end)
	UI.Tooltip(w.start, "Begin the games. Anyone who hasn't paid yet has their bets dropped.")
	w.cancel = UI.Button(root, "Cancel unpaid", 100, function() ns.Table:CancelBets(viewRound) end)
	UI.Tooltip(w.lock, "Close betting on this round. Shift-click locks every round. Once all are locked, everyone pays before the games begin.")
	UI.Tooltip(w.void, function()
		local t = ns.Table.current
		if t and t.market and Bets.CanRemove(t, viewRound) then
			return "Take this round off the card. Later rounds are renumbered."
		end
		return "Cancel this round and give every stake back. It stays on the card as called off, since bets were paid."
	end)
	UI.Tooltip(w.new, function()
		local t = ns.Table.current
		if t and not Bets.CanAddRound(t.market) then
			return ("The card holds %d rounds. Finish or remove one to open another; once every round is settled, a new round starts a fresh card."):format(Bets.MAX_ROUNDS)
		end
		return "Open betting on another round."
	end)
	UI.Tooltip(w.cancel, "Take back the bets you haven't paid for yet.")
end

-- Puts buttons along the bottom-left, in order, hiding the rest. A button that stays isn't
-- hidden first: hiding it between mouse down and up would swallow the click.
local function Layout(list, all)
	local keep = {}
	for _, b in ipairs(list) do keep[b] = true end
	for _, b in ipairs(all) do
		if not keep[b] then b:Hide() end
	end
	local prev
	for _, b in ipairs(list) do
		b:ClearAllPoints()
		if prev then b:SetPoint("LEFT", prev, "RIGHT", 4, 0) else b:SetPoint("BOTTOMLEFT", 12, 10) end
		b:Show()
		prev = b
	end
end

local ACTIONS  -- every bottom-left button, set once the window is built

local function HideRoundView()
	for _, b in ipairs(w.rounds) do b:Hide() end
	for _, row in ipairs(w.sides) do
		row.text:Hide()
		row.bar:Hide()
		row.button:Hide()
	end
	for _, row in ipairs(w.owe) do
		row.text:Hide()
		row.button:Hide()
	end
	w.mine:SetText("")
	for _, widget in ipairs(w.builder) do widget:Hide() end
	w.cutRow:Hide()
	-- Not the round-naming row: every view sets it itself, and hiding it even for a moment
	-- takes the keyboard off its boxes (the page redraws every few seconds).
end

local function HidePayments()
	for _, row in ipairs(w.pays) do
		row.text:Hide()
		row.button:Hide()
	end
end

-- Every round is locked: one list of what everyone owes the host, with Start games below.
local function ShowPayments(frame, t)
	local hosting, me = ns.Table:IsHosting(), ns.Me()
	local rows, owedTotal, paidTotal = Bets.Payments(t)
	HideRoundView()
	frame.header:SetText(("%s's fire  |cffffd100Payments|r"):format(ns.Short(t.host)))
	w.title:SetText("Pay the host before the games begin")
	w.clock:SetText("")
	w.pool:SetText(("Paid %s   |cffff6666owed %s|r"):format(ns.CoinString(paidTotal), ns.CoinString(owedTotal)))
	for i = 1, PAY_ROWS do
		local row, p = w.pays[i], rows[i]
		if i == PAY_ROWS and #rows > PAY_ROWS then
			row.text:SetText(("|cff999999...and %d more|r"):format(#rows - PAY_ROWS + 1))
			row.text:Show()
			row.button:Hide()
		elseif p then
			local name = p.who == me and ("|cffffd100" .. ns.Short(p.who) .. "|r") or ns.Short(p.who)
			row.text:SetText(("%s   %s bet   %s"):format(name, ns.CoinString(p.total),
				p.owes > 0 and ("|cffff6666owes " .. ns.CoinString(p.owes) .. "|r") or "|cff66ff66paid|r"))
			row.button.name = p.who
			row.text:Show()
			row.button:SetShown(hosting and p.owes > 0)
		else
			row.text:Hide()
			row.button:Hide()
		end
	end
	w.mine:SetText(#rows == 0 and "|cff999999Nobody has bet on this card.|r" or "")
	w.newRow:SetShown(hosting and adding)

	local actions = {}
	if hosting then
		w.start:SetText(owedTotal > 0 and "Start (drop unpaid)" or "Start games")
		actions[#actions + 1] = w.start
		actions[#actions + 1] = w.new
	else
		local owed = ns.Table:OwedTotal(t, me)
		if owed > 0 then
			w.pay:SetText("Pay host " .. ns.Coins(owed))
			actions[#actions + 1] = w.pay
		end
	end
	Layout(actions, ACTIONS)
end

function BetsUI:Click(side)
	local t = ns.Table.current
	local r = t and t.market and t.market.rounds[viewRound]
	if not r then return end
	if r.state == "open" then
		ns.Table:PlaceBet(viewRound, side, Pending())
		Bonfire.db.global.bet.total = 0
	elseif r.state == "locked" and r.started and ns.Table:IsHosting() then
		ns.Table:ResolveRound(viewRound, side)
	end
	ns.UI:Refresh()
end

function BetsUI:Hide()
	if root then root:Hide() end
end

-- No rounds yet: the host can open one, everyone else waits for it.
local function ShowEmpty(frame, t, hosting)
	HideRoundView()
	HidePayments()
	w.toggle:Hide()
	frame.header:SetText(("%s's fire  |cffffd100Side bets|r"):format(ns.Short(t.host)))
	frame.sub:SetText("")
	w.title:SetText("No rounds yet")
	w.clock:SetText("")
	w.pool:SetText("")
	w.mine:SetText(hosting
		and "Open a round with New round: pick what it is, then name one side in each box."
		or "The host hasn't opened any side bets yet. Rounds show up here as soon as they do.")
	w.newRow:SetShown(hosting and adding)
	if hosting then w.mode:SetText(("|cffffd100%s|r |cffaaaaaav|r"):format(Bets.MODES[mode])) end
	w.new:SetEnabled(true)
	Layout(hosting and { w.new } or {}, ACTIONS)
end

function BetsUI:Show(frame, t)
	if not root then
		Build(frame)
		ACTIONS = { w.lock, w.void, w.new, w.pay, w.cancel, w.start }
	end
	root:Show()
	local m, hosting, me = t.market, ns.Table:IsHosting(), ns.Me()
	if not m or #m.rounds == 0 then return ShowEmpty(frame, t, hosting) end
	w.new:SetEnabled(Bets.CanAddRound(m))
	if not viewRound or not m.rounds[viewRound] then viewRound = math.min(m.current or 1, #m.rounds) end
	local ri = viewRound
	local r = m.rounds[ri]
	local db = Bonfire.db.global.bet
	local practice = hosting and ns.Table:HasBots()
	local canBet = not hosting or practice

	-- Which game the round is, front and centre.
	frame.header:SetText(("%s's fire  |cffffd100%s|r"):format(ns.Short(t.host), r.game or "Custom"))
	frame.sub:SetText("")

	-- Once every round is locked, everyone pays before anything starts.
	local phase = Bets.Phase(m)
	if phase ~= lastPhase then
		lastPhase = phase
		viewPayments = phase == "payment"
	end
	w.toggle:SetShown(phase == "payment")
	if phase == "payment" and viewPayments then
		w.toggle:SetText("Rounds")
		return ShowPayments(frame, t)
	end
	w.toggle:SetText("Payments")
	HidePayments()

	for i = 1, MAX_ROUNDS do
		local rd, b = m.rounds[i], w.rounds[i]
		if rd then
			b:SetText(("|cff%s%d|r"):format(STATE_COLOR[rd.state] or "ffffff", i))
			b:SetEnabled(i ~= ri)
			b:Show()
		else
			b:Hide()
		end
	end

	local pools, total = Bets.Pools(m, ri)
	local odds = Bets.Odds(m, ri)
	local pending = Pending()
	-- One bet per player per round.
	local hasBet = false
	if canBet then
		for _, b in ipairs(m.bets) do
			if b.who == me and b.round == ri then hasBet = true end
		end
	end
	BetsUI.hasBet = hasBet
	local stateText = STATE_TEXT[r.state] or r.state
	if r.state == "locked" then stateText = r.started and "games on" or "collecting payments" end
	w.title:SetText(("%s  |cff%s%s|r"):format(r.title, STATE_COLOR[r.state] or "ffffff", stateText))
	local poolNote = ("host cut %d%%"):format(m.cut or 0)
	if r.state == "done" then
		local _, refunded, cut = Bets.Payouts(m, ri, r.winner)
		if not refunded and cut > 0 then poolNote = "host kept " .. ns.CoinString(cut) end
	end
	w.pool:SetText(("Pool %s  |cff999999%s|r"):format(ns.CoinString(total), poolNote))

	for i = 1, MAX_SIDES do
		local row, name = w.sides[i], r.sides[i]
		if name then
			local share = total > 0 and pools[i] / total or 0
			local won = r.state == "done" and r.winner == i
			local pays = (r.state == "open" and pending > 0) and Bets.Preview(m, ri, i, pending) or 0
			row.text:SetText(("%s%s|r%s   %s   %s%s"):format(
				SIDE_HEX[i], name, won and "  |cff66ff66(won)|r" or "", ns.CoinString(pools[i]),
				odds[i] and ("%.1fx"):format(odds[i]) or "-",
				pays > 0 and ("   |cff66ff66wins " .. ns.CoinString(pays) .. "|r") or ""))
			local c = SIDE_COLORS[i]
			row.bar:SetColorTexture(c[1], c[2], c[3])
			row.bar:SetWidth(math.max(1, 262 * share))
			row.text:Show()
			row.bar:Show()
			if r.state == "open" then
				row.button:SetText("Bet")
				row.button:SetEnabled(canBet and not hasBet)
				row.button:Show()
			elseif r.state == "locked" and hosting and r.started then
				row.button:SetText("Winner")
				row.button:SetEnabled(true)
				row.button:Show()
			else
				row.button:Hide()
			end
		else
			row.text:Hide()
			row.bar:Hide()
			row.button:Hide()
		end
	end

	-- Every bet you've made on the card in one list, so you don't have to click through the
	-- rounds (or, as host, who you still have to collect from, below).
	local lines, hasUnpaid, staked, count = {}, false, 0, 0
	if canBet then
		for i, rd in ipairs(m.rounds) do
			for _, b in ipairs(m.bets) do
				if b.who == me and b.round == i then
					count, staked = count + 1, staked + b.amount
					local status
					if rd.state == "done" then
						local pay, refunded = Bets.Payouts(m, i, rd.winner)
						local got = pay[b.id] or 0
						status = refunded and "refunded"
							or (got > 0 and ("|cff66ff66won %s|r |cff999999(%.1fx)|r"):format(ns.CoinString(got), got / b.amount) or "|cffff6666lost|r")
					elseif b.paid then
						status = "|cff66ff66paid|r"
					else
						status = "|cffff6666owes|r"
						if i == ri then hasUnpaid = true end
					end
					lines[#lines + 1] = ("%s%d|r  %s on %s%s|r   %s"):format(
						i == ri and "|cffffd100" or "|cff999999", i, ns.CoinString(b.amount),
						SIDE_HEX[b.side] or "", rd.sides[b.side] or "?", status)
				end
			end
		end
	end
	local owing = hosting and Bets.Owing(t) or {}
	for i = 1, OWE_ROWS do
		local row, o = w.owe[i], owing[i]
		if o then
			row.text:SetText(("%s owes %s"):format(ns.Short(o[1]), ns.CoinString(o[2])))
			row.button.name = o[1]
			row.text:Show()
			row.button:Show()
		else
			row.text:Hide()
			row.button:Hide()
		end
	end
	if #owing > 0 then
		w.mine:SetText("")
	elseif #lines > 0 then
		w.mine:SetText(("|cffffffffYour bets|r  %d, %s staked\n%s"):format(count, ns.CoinString(staked), table.concat(lines, "\n")))
	else
		w.mine:SetText(canBet and "|cff999999You haven't bet yet.|r" or "")
	end

	-- Builder
	local unit = ns.COIN_UNITS[db.unit]
	w.amount:SetText(("%d|T%s:16:16:2:0|t"):format(db.amount, unit.icon))
	w.unit:SetText(("|T%s:16:16|t"):format(unit.icon))
	w.total:SetText(db.total > 0 and ("Bet: " .. ns.CoinString(db.total)) or "|cff999999Add an amount, or just pick a side.|r")
	w.clear:SetEnabled(db.total > 0)
	for _, widget in ipairs(w.builder) do widget:SetShown(r.state == "open" and canBet and not hasBet) end

	-- Host: naming a new round, or the cut slider
	w.newRow:SetShown(hosting and adding)
	w.cutRow:SetShown(hosting and not adding)
	if hosting then
		w.mode:SetText(("|cffffd100%s|r |cffaaaaaav|r"):format(Bets.MODES[mode]))
		local locked = Bets.HoldsGold(t)
		local stop = 1
		for i, pct in ipairs(Bets.CUTS) do
			if math.abs(pct - (m.cut or 0)) < math.abs(Bets.CUTS[stop] - (m.cut or 0)) then stop = i end
		end
		w.cut:SetValue(stop)
		w.cut:EnableMouse(not locked)
		w.cut:SetAlpha(locked and 0.45 or 1)
		w.cutNote:SetText(locked and "|cffff6666locked|r" or "")
	end

	-- Bottom-left actions
	local actions = {}
	if hosting then
		local removable = Bets.CanRemove(t, ri)
		if r.state == "open" then actions[#actions + 1] = w.lock end
		if removable or r.state == "open" or r.state == "locked" then
			w.void:SetText(removable and "Remove round" or "Call off")
			actions[#actions + 1] = w.void
		end
		actions[#actions + 1] = w.new
	else
		local owed = ns.Table:OwedTotal(t, me)
		if owed > 0 then
			w.pay:SetText("Pay host " .. ns.Coins(owed))
			actions[#actions + 1] = w.pay
		end
		if hasUnpaid then actions[#actions + 1] = w.cancel end
	end
	Layout(actions, ACTIONS)
	self:Tick()
end

-- Once a second: the lock countdown.
function BetsUI:Tick()
	if not root or not root:IsShown() then return end
	local t = ns.Table.current
	local r = t and t.market and t.market.rounds[viewRound or 1]
	if not r then return end
	local text = ""
	if r.state == "open" and r.lockAt then
		local left = r.lockAt - GetServerTime()
		text = left > 0 and ("Closes in |cffffffff%d:%02d|r"):format(math.floor(left / 60), left % 60) or "closing..."
	end
	w.clock:SetText(text)
end
