-- Plays full games through the real Table.lua against a fake clock and stand-ins for the
-- game's functions, with practice players in the seats and the host playing too. It catches
-- Lua errors and stuck games in the table wiring that the pure-rules tests can't see.
-- Run with scripts\tablesim.ps1.
local ns = {}
math.randomseed(20260929)

-- ---- fake game --------------------------------------------------------------------------
local now, timers = 1000, {}
local log = {}
function GetTime() return now end
function GetServerTime() return math.floor(now) end
C_Timer = {
	After = function(delay, fn) timers[#timers + 1] = { at = now + delay, fn = fn } end,
	NewTimer = function(delay, fn)
		local timer = { at = now + delay, fn = fn }
		timers[#timers + 1] = timer
		return timer
	end,
}
local function advance(seconds)
	local target = now + seconds
	while true do
		local nextTimer, index
		for i, timer in ipairs(timers) do
			if timer.at <= target and (not nextTimer or timer.at < nextTimer.at) then nextTimer, index = timer, i end
		end
		if not nextTimer then break end
		table.remove(timers, index)
		now = math.max(now, nextTimer.at)
		nextTimer.fn()
	end
	now = target
end

floor = math.floor
function tContains(list, value)
	for _, v in ipairs(list) do if v == value then return true end end
	return false
end
function strtrim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
function InCombatLockdown() return false end
function UnitName() return "Host" end
C_Spell = {}
RANDOM_ROLL_RESULT = "%s rolls %d (%d-%d)"

local stake, chosen = 0, "oddmanout"
local hostSeat = "Host-Realm"
local hbd = {
	GetPlayerZonePosition = function() return 0.5, 0.5, 1429 end,
	GetZoneDistance = function() return 5 end,
}
function LibStub() return hbd end

local Bonfire = {
	db = { global = { stats = { played = 0, won = 0 }, stake = { total = 0, confirmed = 0 }, betCut = 5, bet = { amount = 5, unit = 2, total = 0 } }, char = {} },
}
function Bonfire:Print(...) log[#log + 1] = table.concat({ ... }, " ") end
function Bonfire:Printf(fmt, ...) log[#log + 1] = fmt:format(...) end
ns.Bonfire = Bonfire
ns.AddCommand = function() end
ns.AddHiddenCommand = function() end
ns.Me = function() return hostSeat end
ns.FullName = function(n)
	if not n then return end
	return n:find("-", 1, true) and n or n .. "-Realm"
end
ns.Short = function(n) return n and (n:gsub("%-.*", "")) end
ns.NameKey = function(name) return name and (name:match("^[^%s%-]+") or name):lower() end
ns.SignedCoins = function(c) return tostring(c) end
ns.Coins = function(c) if not c or c == 0 then return "for fun" end return ns.CoinString(c) end
ns.StakeCopper = function() return stake end
ns.BetReady = function() return true end
ns.ChosenGame = function() return chosen end
ns.AtCampfire = function() return true end
ns.CampfireBuff = function() return true end
ns.UI = { Refresh = function() end, Notice = function() end, Show = function() end }
ns.Beacon = { Announce = function() end, Remove = function() end, fires = {}, Distance = function() return 5 end }
ns.Comm = {
	selfSender = hostSeat, On = function() end, ChannelId = function() return 1 end,
	Broadcast = function() return true end, Whisper = function() end,
}
ns.Trade = {}

function SendChatMessage() end
function DoEmote() end
Bonfire.db.global.chatTab = true
for _, file in ipairs({ "Money.lua", "Games/List.lua", "Quips.lua", "Roll.lua", "Ledger.lua", "Bets.lua", "Games/Embers.lua",
	"Games/Deathroll.lua", "Games/OddManOut.lua", "History.lua", "Table.lua" }) do
	assert(loadfile(file))("Bonfire", ns)
end
local Table, Odd, Ledger = ns.Table, ns.Games.oddmanout, ns.Ledger

-- The host's own /roll shows up in chat straight away.
function RandomRoll(lo, hi)
	Table:OnSystemMessage(("Host rolls %d (%d-%d)"):format(math.random(lo, hi), lo, hi))
end

-- ---- driving a table ----------------------------------------------------------------------
local function newTable(game, bots, gold)
	stake, chosen = gold and 500 or 0, game
	Table.current, Table.game, timers, log = nil, nil, {}, {}
	Table:Host(true)
	assert(Table.current, "table didn't open: " .. table.concat(log, " | "))
	if bots > 0 then Table:AddBots(bots) end
	advance(12)  -- bots pay in, first state goes out
end

-- Plays one game to its end. hostMode: "plays" (acts like a player) or "afk" (never acts).
local function settleBots()
	local t = Table.current
	for _ = 1, 2 do  -- payouts first, then the pay-ins those players now owe
		for _, name in ipairs(t.seats) do
			if Table:IsBot(name) then Table:BotTrade(name) end
		end
		advance(2)
	end
end

local function playGame(hostMode)
	local t = Table.current
	if t.stake > 0 then settleBots() end
	Table:Start()
	assert(t.state == "playing", "game didn't start: " .. table.concat(log, " | "))
	for _ = 1, 900 do
		advance(1)
		Table:GameTick()
		local g = Table.game
		if t.state == "open" then return true end
		if g and hostMode == "plays" then
			if t.game == "oddmanout" then
				if g.phase == "pick" and g.waiting[hostSeat] and math.random() < 0.6 then Table:MakePick(math.random(1, g.range)) end
				if g.phase == "roll" and g.waiting[hostSeat] and math.random() < 0.9 then Table:OmoRoll() end
				if g.phase == "roll" then
					for _, name in ipairs(Odd.Alive(g)) do
						local p = g.picks[name]
						assert(p and p <= g.range, "a pick above the die: " .. tostring(p))
					end
				end
			else
				if Table:CanRoll() then Table:Roll() end
				local me = g.players[hostSeat]
				if me and me.stoking and me.pot >= 9 then Table:Bank() end
			end
		end
	end
	return false
end

local failures, games, decided = 0, 0, 0
local function run(label, count, mk)
	local bad = 0
	for i = 1, count do
		local ok, err = pcall(mk, i)
		games = games + 1
		if not ok then
			bad = bad + 1
			if bad <= 2 then print(("  FAIL %s #%d: %s"):format(label, i, tostring(err))) end
		end
	end
	failures = failures + bad
	print(("%-46s %3d games, %d failed"):format(label, count, bad))
end

local function oneGame(game, gold, hostMode)
	return function()
		local bots = math.random(1, 9)
		newTable(game, bots, gold)
		for round = 1, 2 do  -- two games in a row, to check nothing leaks between them
			assert(playGame(hostMode), ("game %d never finished (%s, %d bots)"):format(round, game, bots))
			local t = Table.current
			assert(t.winners, "no winners table")
			if game == "oddmanout" and #t.winners > 0 then decided = decided + 1 end
			assert(Table.game == nil and Table.deadline == nil, "game state left behind")
			assert(t.gs and (t.gs.order or t.gs.p), "no final state to show")
			if t.stake > 0 and #t.winners == 1 and t.winners[1] ~= hostSeat then
				assert(Ledger.Balance(t, t.winners[1]) >= t.share, "the winner wasn't credited")
			end
			advance(12)  -- bots re-pay or cash out
		end
	end
end

run("Odd Man Out, host plays, for fun", 150, oneGame("oddmanout", false, "plays"))
run("Odd Man Out, host plays, gold", 100, oneGame("oddmanout", true, "plays"))
run("Odd Man Out, host never acts (auto pick/fold)", 100, oneGame("oddmanout", false, "afk"))
run("Embers, host plays, for fun", 60, oneGame("embers", false, "plays"))
run("Embers, host plays, gold", 60, oneGame("embers", true, "plays"))

-- A spectator's side-bet results, worked out from the market the host sends.
local function betResults()
	local Bets = ns.Bets
	local function market(host)
		local t = { host = host, stake = 500, seats = { "Viewer-Realm", "Other-Realm" }, market = Bets.NewMarket(5) }
		Ledger.Init(t)
		local m = t.market
		Bets.AddRound(m, "Duel", { "A", "B" }, 1000, "Duel")          -- A wins: the viewer backed A
		Bets.AddRound(m, "Race", { "A", "B" }, 1001, "Critter Race")  -- B wins: the viewer backed A
		Bets.AddRound(m, "Dice", { "A", "B" }, 1002, "Dice")          -- nobody against the winner: refunded
		for ri = 1, 3 do
			assert(Bets.Place(t, "Viewer-Realm", ri, 1, 100, true))
			if ri < 3 then assert(Bets.Place(t, "Other-Realm", ri, 2, 300, true)) end
		end
		assert(Bets.Resolve(t, 1, 1))
		assert(Bets.Resolve(t, 2, 2))
		assert(Bets.Resolve(t, 3, 1))
		return t
	end
	local ok, err = pcall(function()
		Bonfire.db.char.history = nil
		local t = market("Host-Realm")
		hostSeat = "Viewer-Realm"
		Table:CountBets(t)
		Table:CountBets(t)  -- the same update again must not count twice
		local b = Bonfire.db.char.history.bets
		assert(b.placed == 2 and b.won == 1 and b.lost == 1, "wrong bet counts")
		assert(b.gained == 280 and b.spent == 100, ("wrong gold: +%d -%d"):format(b.gained, b.spent))
		assert(Bonfire.db.char.history.played == 0, "a bet counted as a game")
		Bonfire.db.char.history = nil
		hostSeat = "Host-Realm"
		Table:CountBets(t)  -- the host's own bets are free and never count
		assert(Bonfire.db.char.history == nil, "the host's bets were counted")
	end)
	hostSeat = "Host-Realm"
	assert(ok, err)
end
run("Side bet results in /bf history", 1, betResults)

print(("\n%d games, %d failed, %d Odd Man Out games with a winner"):format(games, failures, decided))
os.exit(failures == 0 and 0 or 1)
