-- Offline tests for pure game logic. Run scripts\test.ps1 (LuaJIT = Lua 5.1, like WoW).
local ns = {}
ns.AddCommand = function() end  -- commands are registered by the addon, not needed here
local function load(file) assert(loadfile(file))("Bonfire", ns) end
load("Roll.lua")
load("Money.lua")
load("Ledger.lua")
load("History.lua")
load("Bets.lua")
load("Reputation.lua")
load("Games/List.lua")
load("Quips.lua")
load("Games/Embers.lua")
load("Games/Deathroll.lua")
load("Games/OddManOut.lua")

local passed, failed = 0, 0
local function test(name, fn)
	local ok, err = pcall(fn)
	if ok then passed = passed + 1 else failed = failed + 1; print("FAIL " .. name .. ": " .. tostring(err)) end
end
local function eq(actual, expected)
	if actual ~= expected then error(("expected %s, got %s"):format(tostring(expected), tostring(actual)), 2) end
end

-- Roll parsing ---------------------------------------------------------------
local enUS = ns.RollPattern("%s rolls %d (%d-%d)")

test("parses an enUS roll", function()
	local who, roll, low, high = ns.ParseRoll("Oppa rolls 42 (1-100)", enUS)
	eq(who, "Oppa"); eq(roll, 42); eq(low, 1); eq(high, 100)
end)

test("keeps realm suffixes", function()
	eq(ns.ParseRoll("Oppa-ClassicBetaPvE rolls 6 (1-6)", enUS), "Oppa-ClassicBetaPvE")
end)

test("ignores other system text", function()
	eq(ns.ParseRoll("Oppa has come online.", enUS), nil)
	eq(ns.ParseRoll("Oppa rolls 42 (1-100) extra", enUS), nil)
end)

test("handles positional locale formats", function()
	local who, roll = ns.ParseRoll("Oppa wirft 5 (1-6)", ns.RollPattern("%1$s wirft %2$d (%3$d-%4$d)"))
	eq(who, "Oppa"); eq(roll, 5)
end)

-- Embers ---------------------------------------------------------------------
local Embers = ns.Games.embers

test("rolls add to every stoking pot", function()
	local s = Embers.New({ "A", "B" }, 3)
	Embers.Roll(s, 4); Embers.Roll(s, 5)
	eq(s.players.A.pot, 9); eq(s.players.B.pot, 9)
end)

test("banking keeps the pot and sits you out", function()
	local s = Embers.New({ "A", "B" }, 3)
	Embers.Roll(s, 4)
	eq(Embers.Bank(s, "A"), true)
	Embers.Roll(s, 6)
	eq(s.players.A.total, 4); eq(s.players.A.pot, 0); eq(s.players.B.pot, 10)
	eq(Embers.Bank(s, "A"), false)
end)

test("a 1 wipes unbanked pots and starts the next round", function()
	local s = Embers.New({ "A", "B" }, 3)
	Embers.Roll(s, 6); Embers.Bank(s, "A"); Embers.Roll(s, 3)
	eq(Embers.Roll(s, 1), true)
	eq(s.round, 2); eq(s.players.A.total, 6); eq(s.players.B.total, 0)
	eq(s.players.A.stoking, true); eq(s.players.B.stoking, true)
end)

test("round ends when everyone has banked", function()
	local s = Embers.New({ "A", "B" }, 3)
	Embers.Roll(s, 5); Embers.Bank(s, "A"); Embers.Bank(s, "B")
	eq(s.round, 2); eq(s.players.B.total, 5)
end)

test("game ends after the last round with the high total winning", function()
	local s = Embers.New({ "A", "B", "C" }, 1)
	Embers.Roll(s, 6); Embers.Bank(s, "B"); Embers.Roll(s, 2); Embers.Bank(s, "C"); Embers.Roll(s, 1)
	eq(s.over, true)
	local winners, best = Embers.Winners(s)
	eq(#winners, 1); eq(winners[1], "C"); eq(best, 8)
	eq(Embers.Roll(s, 5), nil)
end)

test("ties split the win", function()
	local s = Embers.New({ "A", "B" }, 1)
	Embers.Roll(s, 3); Embers.Bank(s, "A"); Embers.Bank(s, "B")
	eq(#Embers.Winners(s), 2)
end)

test("leavers forfeit and can't win", function()
	local s = Embers.New({ "A", "B" }, 2)
	Embers.Roll(s, 6); Embers.Bank(s, "A"); Embers.Leave(s, "A")
	eq(s.players.B.stoking, true)
	Embers.Leave(s, "B")
	eq(s.round, 2)
	eq(#Embers.Winners(s), 0)
end)

-- Money ----------------------------------------------------------------------
test("parses coin strings", function()
	eq(ns.ParseMoney("5g20s3c"), 52003)
	eq(ns.ParseMoney("35s"), 3500)
	eq(ns.ParseMoney(" 1g 5c "), 10005)
	eq(ns.ParseMoney("250"), 250)
	eq(ns.ParseMoney("5x"), nil)
	eq(ns.ParseMoney("g5"), nil)
	eq(ns.ParseMoney(""), nil)
end)

test("dialled amounts stop where the next coin takes over", function()
	eq(ns.COIN_UNITS[1].max, 100); eq(ns.COIN_UNITS[2].max, 99); eq(ns.COIN_UNITS[3].max, 99)
end)

test("formats coins with textures", function()
	local function plain(copper) return (ns.CoinString(copper):gsub("|T.-|t", "")) end
	eq(plain(52003), "5 20 3"); eq(plain(100), "1"); eq(plain(0), "0"); eq(plain(10001), "1 1")
	eq(ns.CoinString(50):find("UI-CopperIcon", 1, true) ~= nil, true)
end)

-- Ledger ---------------------------------------------------------------------
local Ledger = ns.Ledger
local function Tbl(stake, seats)
	local t = { host = "H", stake = stake, seats = seats, state = "open" }
	Ledger.Init(t)
	return t
end

test("unpaid players sit out; the host never owes", function()
	local t = Tbl(500, { "H", "A", "B" })
	Ledger.Credit(t, "A", 500)
	Ledger.Credit(t, "B", 300)
	eq(Ledger.Owes(t, "H"), 0); eq(Ledger.Owes(t, "B"), 200)
	local players = Ledger.Eligible(t)
	eq(#players, 2); eq(players[1], "H"); eq(players[2], "A")
	local payins = Ledger.PayIns(t)
	eq(#payins, 1); eq(payins[1][1], "B"); eq(payins[1][2], 200)
end)

test("free tables need no trades", function()
	local t = Tbl(0, { "H", "A" })
	eq(#Ledger.Eligible(t), 2); eq(#Ledger.PayIns(t), 0)
end)

test("the pot goes to the winner as credit, host money stays out", function()
	local t = Tbl(500, { "H", "A", "B" })
	Ledger.Credit(t, "A", 500); Ledger.Credit(t, "B", 500)
	Ledger.Commit(t, Ledger.Eligible(t))
	eq(Ledger.Balance(t, "A"), 0)
	eq(Ledger.Settle(t, { "A" }), 1500)
	eq(Ledger.Balance(t, "A"), 1500); eq(Ledger.Balance(t, "B"), 0); eq(Ledger.Balance(t, "H"), 0)
	eq(t.committed, nil)
end)

test("split pots give odd coppers to the first winner", function()
	local t = Tbl(5, { "H", "A", "B" })
	Ledger.Credit(t, "A", 5); Ledger.Credit(t, "B", 5)
	Ledger.Commit(t, Ledger.Eligible(t))
	eq(Ledger.Settle(t, { "A", "B" }), 7)
	eq(Ledger.Balance(t, "A"), 8); eq(Ledger.Balance(t, "B"), 7)
end)

test("an abandoned game refunds stakes", function()
	local t = Tbl(500, { "H", "A" })
	Ledger.Credit(t, "A", 800)
	Ledger.Commit(t, Ledger.Eligible(t))
	Ledger.Void(t)
	eq(Ledger.Balance(t, "A"), 800); eq(t.committed, nil)
end)

test("cash-outs and leavers queue for payout until paid", function()
	local t = Tbl(500, { "H", "A", "B" })
	Ledger.Credit(t, "A", 1200); Ledger.Credit(t, "B", 700)
	t.cashout.A = true
	t.seats = { "H", "A" }; Ledger.Leave(t, "B")
	local out = Ledger.Payouts(t)
	eq(#out, 2); eq(out[1][1], "A"); eq(out[1][2], 1200); eq(out[2][1], "B")
	eq(#Ledger.Eligible(t), 1)
	Ledger.Credit(t, "A", -1200); Ledger.Credit(t, "B", -700)
	eq(#Ledger.Payouts(t), 0); eq(t.cashout.A, nil); eq(t.left.B, nil)
end)

test("settling pays back everyone holding credit", function()
	local t = Tbl(500, { "H", "A", "B" })
	Ledger.Credit(t, "A", 500)
	t.state = "settling"
	local out = Ledger.Payouts(t)
	eq(#out, 1); eq(out[1][1], "A")
end)

test("a table can pass only while the host holds no gold", function()
	local t = Tbl(500, { "H", "A" })
	eq(Ledger.Empty(t), true)
	Ledger.Credit(t, "A", 500)
	eq(Ledger.Empty(t), false)
	Ledger.Credit(t, "A", -500)
	eq(Ledger.Empty(t), true)
	Ledger.Credit(t, "A", 500); Ledger.Commit(t, Ledger.Eligible(t))
	eq(Ledger.Empty(t), false)
end)

test("for-fun tables can always pass, even mid-game", function()
	local t = Tbl(0, { "H", "A" })
	Ledger.Commit(t, Ledger.Eligible(t))
	eq(Ledger.Empty(t), true)
end)

-- Deathroll ------------------------------------------------------------------
local Deathroll = ns.Games.deathroll

local function rolls(s, values)
	for _, pair in ipairs(values) do
		eq(Deathroll.Roll(s, pair[1], pair[2]), true)
	end
end

local function names(list) return table.concat(list, ",") end

test("all out, even count: highest and lowest are knocked out", function()
	local s = Deathroll.New({ "A", "B", "C", "D" })
	eq(s.phase, "round")
	rolls(s, { { "A", 10 }, { "B", 90 }, { "C", 50 }, { "D", 30 } })
	eq(s.out.B, "highest"); eq(s.out.A, "lowest")
	eq(s.phase, "duel"); eq(names(Deathroll.Alive(s)), "C,D")
	eq(s.duel.roller, "C")
end)

test("all out, odd count: only the highest goes", function()
	local s = Deathroll.New({ "A", "B", "C" })
	rolls(s, { { "A", 10 }, { "B", 90 }, { "C", 50 } })
	eq(s.out.B, "highest"); eq(s.out.A, nil)
	eq(s.phase, "duel"); eq(names(Deathroll.Alive(s)), "A,C")
end)

test("five players: one out, then two, then the duel", function()
	local s = Deathroll.New({ "A", "B", "C", "D", "E" })
	rolls(s, { { "A", 5 }, { "B", 60 }, { "C", 20 }, { "D", 80 }, { "E", 40 } })
	eq(names(Deathroll.Alive(s)), "A,B,C,E"); eq(s.phase, "round"); eq(s.round, 2)
	rolls(s, { { "A", 70 }, { "B", 10 }, { "C", 30 }, { "E", 90 } })
	eq(s.out.E, "highest"); eq(s.out.B, "lowest")
	eq(s.phase, "duel"); eq(names(Deathroll.Alive(s)), "A,C")
end)

test("the final roll-off of an all-out game starts at 10, a classic 1v1 at 100", function()
	local s = Deathroll.New({ "A", "B", "C" })
	rolls(s, { { "A", 10 }, { "B", 90 }, { "C", 50 } })
	eq(s.phase, "duel")
	local _, hi = Deathroll.Range(s, s.duel.roller)
	eq(hi, 10)
	eq(Deathroll.Roll(s, s.duel.roller, 11), false)
	local first = s.duel.roller
	eq(Deathroll.Roll(s, first, 7), true)
	eq(select(2, Deathroll.Range(s, s.duel.roller)), 7)
	eq(select(2, Deathroll.Range(Deathroll.New({ "A", "B" }), "A")), 100)
end)

test("a tie for highest re-rolls among only the tied players", function()
	local s = Deathroll.New({ "A", "B", "C", "D" })
	rolls(s, { { "A", 90 }, { "B", 90 }, { "C", 50 }, { "D", 10 } })
	eq(s.phase, "tie"); eq(names(Deathroll.Waiting(s)), "A,B")
	eq(Deathroll.Roll(s, "C", 5), false)
	rolls(s, { { "A", 20 }, { "B", 70 } })
	eq(s.out.B, "highest"); eq(s.out.D, "lowest")
	eq(s.phase, "duel"); eq(names(Deathroll.Alive(s)), "A,C")
end)

test("a tie for lowest re-rolls among only the tied players", function()
	local s = Deathroll.New({ "A", "B", "C", "D" })
	rolls(s, { { "A", 10 }, { "B", 10 }, { "C", 50 }, { "D", 90 } })
	eq(s.out.D, "highest"); eq(s.phase, "tie"); eq(names(Deathroll.Waiting(s)), "A,B")
	rolls(s, { { "A", 5 }, { "B", 3 } })
	eq(s.out.B, "lowest"); eq(names(Deathroll.Alive(s)), "A,C"); eq(s.phase, "duel")
end)

test("everyone tied: highest re-roll, then a lowest re-roll", function()
	local s = Deathroll.New({ "A", "B", "C", "D" })
	rolls(s, { { "A", 50 }, { "B", 50 }, { "C", 50 }, { "D", 50 } })
	eq(names(Deathroll.Waiting(s)), "A,B,C,D")
	rolls(s, { { "A", 1 }, { "B", 2 }, { "C", 3 }, { "D", 4 } })
	eq(s.out.D, "highest"); eq(s.phase, "tie"); eq(names(Deathroll.Waiting(s)), "A,B,C")
	rolls(s, { { "A", 9 }, { "B", 8 }, { "C", 7 } })
	eq(s.out.C, "lowest"); eq(names(Deathroll.Alive(s)), "A,B"); eq(s.phase, "duel")
end)

test("the duel chains ranges and a 1 loses", function()
	local s = Deathroll.New({ "A", "B" })
	eq(s.phase, "duel")
	local lo, hi = Deathroll.Range(s, "A")
	eq(lo, 1); eq(hi, 100)
	eq(Deathroll.Range(s, "B"), nil)
	eq(Deathroll.Roll(s, "B", 40), false)
	eq(Deathroll.Roll(s, "A", 101), false)
	eq(Deathroll.Roll(s, "A", 40, 99), false)
	eq(Deathroll.Roll(s, "A", 40, 100), true)
	local _, max = Deathroll.Range(s, "B")
	eq(max, 40)
	eq(Deathroll.Roll(s, "B", 41), false)
	eq(Deathroll.Roll(s, "B", 12), true)
	eq(select(2, Deathroll.Range(s, "A")), 12)
	eq(Deathroll.Roll(s, "A", 1), true)
	eq(s.over, true); eq(s.winner, "B"); eq(s.out.A, "rolled 1")
end)

test("nobody rolls twice in a round or out of turn", function()
	local s = Deathroll.New({ "A", "B", "C" })
	eq(Deathroll.Roll(s, "A", 10), true)
	eq(Deathroll.Roll(s, "A", 20), false)
	eq(Deathroll.Roll(s, "Z", 20), false)
	eq(Deathroll.Roll(s, "B", 0), false)
end)

test("folding in the duel hands the win to the other player", function()
	local s = Deathroll.New({ "A", "B" })
	eq(Deathroll.Fold(s, "A"), true)
	eq(s.over, true); eq(s.winner, "B"); eq(s.out.A, "folded")
	eq(Deathroll.Fold(s, "B"), false)
end)

test("folding before rolling drops you and the round carries on", function()
	local s = Deathroll.New({ "A", "B", "C" })
	rolls(s, { { "A", 30 } })
	Deathroll.Fold(s, "B")
	eq(s.phase, "round")
	rolls(s, { { "C", 60 } })
	eq(s.out.B, "folded"); eq(s.phase, "duel"); eq(names(Deathroll.Alive(s)), "A,C")
end)

test("a fold that leaves one player standing ends the game", function()
	local s = Deathroll.New({ "A", "B", "C" })
	Deathroll.Fold(s, "A")
	eq(s.over, false)
	Deathroll.Fold(s, "B")
	eq(s.over, true); eq(s.winner, "C")
end)

local function players(n)
	local list = {}
	for i = 1, n do list[i] = "P" .. i end
	return list
end

test("Deathroll: at every size from 3 to 10, one player wins outright when the rest fold", function()
	for n = 3, 10 do
		local s = Deathroll.New(players(n))
		local others = {}
		for i = 2, n do others[#others + 1] = "P" .. i end
		eq(Deathroll.FoldMany(s, others), true)
		eq(s.over, true); eq(s.winner, "P1")

		local t = Deathroll.New(players(n))
		eq(Deathroll.Roll(t, "P1", 50), true)
		for i = 2, n - 1 do Deathroll.Fold(t, "P" .. i) end
		eq(t.over, false)
		Deathroll.Fold(t, "P" .. n)
		eq(t.over, true); eq(t.winner, "P1")
	end
end)

test("the higher roller of the last all-out round rolls first in the roll-off", function()
	local s = Deathroll.New({ "A", "B", "C" })
	rolls(s, { { "A", 10 }, { "B", 90 }, { "C", 50 } })
	eq(s.duel.roller, "C"); eq(s.duel.other, "A")
	local t = Deathroll.New({ "A", "B", "C", "D" })
	rolls(t, { { "A", 50 }, { "B", 90 }, { "C", 50 }, { "D", 10 } })
	eq(t.duel.roller, "A")
	eq(Deathroll.New({ "A", "B" }).duel.roller, "A")
end)

test("Odd Man Out: at every size from 3 to 10, one player can win in the first round", function()
	local Odd = ns.Games.oddmanout
	for n = 3, 10 do
		local s = Odd.New(players(n))
		for i = 1, n - 1 do Odd.Pick(s, "P" .. i, 5) end
		Odd.Pick(s, "P" .. n, 7)
		for i = 1, n - 1 do Odd.Roll(s, "P" .. i, 1) end
		Odd.Roll(s, "P" .. n, 5)
		eq(s.over, true); eq(s.winner, "P" .. n); eq(#s.outOrder, n - 1)
		eq(names(Odd.Winners(s)), "P" .. n)
	end
end)

test("everyone folding together leaves no winner", function()
	local s = Deathroll.New({ "A", "B", "C" })
	eq(Deathroll.FoldMany(s, { "A", "B", "C" }), true)
	eq(s.over, true); eq(s.winner, nil)
end)

test("both duelists timing out together leaves no winner", function()
	local s = Deathroll.New({ "A", "B" })
	Deathroll.FoldMany(s, { "A", "B" })
	eq(s.over, true); eq(s.winner, nil)
end)

test("a fold during a tie-break settles it", function()
	local s = Deathroll.New({ "A", "B", "C", "D" })
	rolls(s, { { "A", 90 }, { "B", 90 }, { "C", 50 }, { "D", 10 } })
	Deathroll.Fold(s, "A")
	eq(s.phase, "tie")
	rolls(s, { { "B", 33 } })
	eq(s.out.A, "folded"); eq(s.out.B, "highest")
end)

test("the tally tracks wins, losses, net gold and streaks", function()
	local t = Tbl(500, { "H", "A", "B" })
	Ledger.Credit(t, "A", 500); Ledger.Credit(t, "B", 500)
	local dealt = Ledger.Eligible(t)
	Ledger.Commit(t, dealt)
	local share = Ledger.Settle(t, { "A" })
	Ledger.Record(t, dealt, { "A" }, share)
	eq(t.tally.A.w, 1); eq(t.tally.A.net, 1000); eq(t.tally.A.streak, 1)
	eq(t.tally.B.l, 1); eq(t.tally.B.net, -500); eq(t.tally.B.streak, -1)
	eq(t.tally.H.l, 1); eq(t.tally.H.net, -500)
	Ledger.Record(t, dealt, { "B" }, 1500)
	eq(t.tally.A.streak, -1); eq(t.tally.B.streak, 1); eq(t.tally.A.net, 500)
	Ledger.Record(t, dealt, { "B" }, 1500)
	eq(t.tally.B.streak, 2); eq(t.tally.A.streak, -2)
end)

test("for-fun tables tally wins but no gold", function()
	local t = Tbl(0, { "H", "A" })
	Ledger.Record(t, { "H", "A" }, { "A" }, 0)
	eq(t.tally.A.w, 1); eq(t.tally.A.net, 0); eq(t.tally.H.l, 1)
end)

-- Side bets ------------------------------------------------------------------
local Bets = ns.Bets

-- A table with two rounds, holding credit for the given players.
local function Market(cut, credit)
	local t = { host = "H", stake = 0, seats = { "H", "A", "B", "C" }, state = "open" }
	Ledger.Init(t)
	for who, copper in pairs(credit or {}) do Ledger.Credit(t, who, copper) end
	t.market = Bets.NewMarket(cut)
	Bets.AddRound(t.market, "Oppa vs Gopher", { "Oppa", "Gopher" })
	Bets.AddRound(t.market, "Second fight", { "Ratty", "Toad" })
	return t
end

test("rounds carry their game mode and the cut choices are fixed", function()
	local t = Market(0, {})
	Bets.AddRound(t.market, "Rats", { "A", "B", "C" }, 0, "Critter Race")
	eq(t.market.rounds[1].game, "Custom"); eq(t.market.rounds[3].game, "Critter Race")
	eq(table.concat(Bets.CUTS, ","), "2,5,10,20")
end)

test("each round keeps the cut it opened with, whatever the card's default becomes", function()
	local t = Market(5, { A = 1000, B = 1000 })
	eq(t.market.rounds[1].cut, 5)  -- no cut named: the card's default
	local ri = Bets.AddRound(t.market, "Rats", { "X", "Y" }, 0, "Dice", 20)
	eq(t.market.rounds[ri].cut, 20)
	t.market.cut = 2  -- a later round's cut becomes the default; the open ones don't move
	eq(t.market.rounds[1].cut, 5); eq(t.market.rounds[ri].cut, 20)
	Bets.Place(t, "A", ri, 1, 100); Bets.Place(t, "B", ri, 2, 100)
	local pay, _, cut = Bets.Payouts(t.market, ri, 1)
	eq(cut, 40); eq(pay[1], 160)  -- 200 pool, 20% to the host
	eq(Bets.Odds(t.market, ri)[1], 1.6)
	eq(Bets.Preview(t.market, ri, 1, 100), 120)  -- another 100 on side 1: pool 300, 240 after the cut, half of it
	Bets.Place(t, "A", 1, 1, 100); Bets.Place(t, "B", 1, 2, 100)
	local _, _, cut1 = Bets.Payouts(t.market, 1, 1)
	eq(cut1, 10)  -- round 1 still takes its own 5%
end)

test("a card holds six rounds; a full card that's all settled starts over", function()
	local t = Market(0, { A = 1000 })
	for i = 3, Bets.MAX_ROUNDS do eq(Bets.AddRound(t.market, "R" .. i, { "X", "Y" }), i) end
	eq(Bets.CanAddRound(t.market), false)
	eq(Bets.AddRound(t.market, "Seventh", { "X", "Y" }), nil)
	eq(#t.market.rounds, Bets.MAX_ROUNDS)
	Bets.Place(t, "A", 1, 1, 300)
	for i = 1, Bets.MAX_ROUNDS - 1 do Bets.Void(t, i) end
	eq(Bets.AddRound(t.market, "Seventh", { "X", "Y" }), nil)  -- one round still open
	Bets.Resolve(t, Bets.MAX_ROUNDS, 1)
	local ri, fresh = Bets.AddRound(t.market, "Seventh", { "X", "Y" })
	eq(ri, 1); eq(fresh, true); eq(#t.market.rounds, 1); eq(#t.market.bets, 0)
	eq(Ledger.Balance(t, "A"), 1000)  -- the called-off bet came back before the card was cleared
	eq(select(2, Bets.AddRound(t.market, "Eighth", { "X", "Y" })), false)
end)

test("a bet counts once it's paid from held credit", function()
	local t = Market(0, { A = 500 })
	local ok, bet = Bets.Place(t, "A", 1, 1, 300)
	eq(ok, true); eq(bet.paid, true); eq(Ledger.Balance(t, "A"), 200)
	ok, bet = Bets.Place(t, "B", 1, 2, 300)
	eq(ok, true); eq(bet.paid, false)
	local pools, total = Bets.Pools(t.market, 1)
	eq(pools[1], 300); eq(pools[2], 0); eq(total, 300)
	Ledger.Credit(t, "B", 300)
	Bets.Fund(t)
	eq(bet.paid, true); eq(Ledger.Balance(t, "B"), 0)
	eq(select(2, Bets.Pools(t.market, 1)), 600)
end)

test("owing bettors are listed until they pay", function()
	local t = Market(0, { A = 100 })
	Bets.Place(t, "A", 1, 1, 300)
	Bets.Place(t, "B", 1, 2, 500)
	local owing = Bets.Owing(t)
	eq(#owing, 2); eq(owing[1][1], "A"); eq(owing[1][2], 200); eq(owing[2][2], 500)
	eq(Bets.Unpaid(t.market, "A"), 300)
end)

test("locking keeps unpaid bets on the books until the games begin", function()
	local t = Market(0, { A = 500 })
	Bets.Place(t, "A", 1, 1, 500)
	Bets.Place(t, "B", 1, 2, 500)
	eq(Bets.Lock(t, 1), 1)
	eq(t.market.rounds[1].state, "locked"); eq(#t.market.bets, 2)
	eq(Bets.Place(t, "C", 1, 1, 100), false)
	eq(Bets.Lock(t, 1), false)
	eq(Bets.Unpaid(t.market, "B"), 500)
	Ledger.Credit(t, "B", 500)
	Bets.Fund(t)
	eq(t.market.bets[2].paid, true)
end)

test("the card moves from betting to payment to live to done", function()
	local t = Market(0, { A = 500 })
	eq(Bets.Phase(t.market), "betting")
	Bets.Place(t, "A", 1, 1, 500); Bets.Place(t, "B", 2, 2, 300)
	Bets.Lock(t, 1)
	eq(Bets.Phase(t.market), "betting")
	Bets.Lock(t, 2)
	eq(Bets.Phase(t.market), "payment")
	eq(Bets.Begin(t), 1)
	eq(#t.market.bets, 1)
	eq(Bets.Phase(t.market), "live")
	eq(t.market.rounds[1].started, true)
	Bets.Resolve(t, 1, 1); Bets.Void(t, 2)
	eq(Bets.Phase(t.market), "done")
end)

test("the payment list totals what each bettor owes across rounds", function()
	local t = Market(0, { A = 200, C = 900 })
	Bets.Place(t, "A", 1, 1, 200)
	Bets.Place(t, "A", 2, 1, 300)
	Bets.Place(t, "B", 1, 2, 500)
	Bets.Place(t, "C", 2, 2, 100)
	Bets.Place(t, "H", 1, 1, 50, true)
	local rows, owed, paid = Bets.Payments(t)
	eq(#rows, 3)
	eq(rows[1].who, "B"); eq(rows[1].owes, 500)
	eq(rows[2].who, "A"); eq(rows[2].total, 500); eq(rows[2].paid, 200); eq(rows[2].owes, 300)
	eq(rows[3].who, "C"); eq(rows[3].owes, 0)
	eq(owed, 800); eq(paid, 300)
end)

test("a payment covers every unpaid bet a player has across locked rounds", function()
	local t = Market(0, {})
	Bets.Place(t, "A", 1, 1, 200); Bets.Place(t, "A", 2, 2, 300)
	Bets.Lock(t, 1); Bets.Lock(t, 2)
	eq(Bets.Owing(t)[1][2], 500)
	Ledger.Credit(t, "A", 500)
	Bets.Fund(t)
	eq(#Bets.Owing(t), 0); eq(Bets.Begin(t), 0); eq(#t.market.bets, 2)
end)

test("winners split the pool in proportion to their bets", function()
	local t = Market(0, { A = 500, B = 500, C = 1000 })
	Bets.Place(t, "A", 1, 1, 500); Bets.Place(t, "B", 1, 1, 500); Bets.Place(t, "C", 1, 2, 1000)
	local ok, summary = Bets.Resolve(t, 1, 1)
	eq(ok, true); eq(summary.refunded, false); eq(summary.paidOut, 2000)
	eq(Ledger.Balance(t, "A"), 1000); eq(Ledger.Balance(t, "B"), 1000); eq(Ledger.Balance(t, "C"), 0)
	eq(t.tally.A.w, 1); eq(t.tally.A.net, 500); eq(t.tally.C.l, 1); eq(t.tally.C.net, -1000)
	eq(t.market.rounds[1].state, "done")
end)

test("uneven bets pay by share and the host cut comes off the top", function()
	local t = Market(5, { A = 300, B = 100, C = 600 })
	Bets.Place(t, "A", 1, 1, 300); Bets.Place(t, "B", 1, 1, 100); Bets.Place(t, "C", 1, 2, 600)
	local _, summary = Bets.Resolve(t, 1, 1)
	eq(summary.cut, 50)
	eq(Ledger.Balance(t, "A"), 712); eq(Ledger.Balance(t, "B"), 237)
	local odds = Bets.Odds(t.market, 1)
	eq(math.abs(odds[1] - 950 / 400) < 1e-9, true)
end)

test("a round nobody bet against refunds everyone", function()
	local t = Market(5, { A = 500, B = 500 })
	Bets.Place(t, "A", 1, 1, 500); Bets.Place(t, "B", 1, 1, 500)
	local _, summary = Bets.Resolve(t, 1, 1)
	eq(summary.refunded, true); eq(Ledger.Balance(t, "A"), 500); eq(Ledger.Balance(t, "B"), 500)
	eq(t.tally, nil)
end)

test("a round where nobody backed the winner refunds everyone", function()
	local t = Market(0, { A = 500 })
	Bets.Place(t, "A", 1, 1, 500)
	local _, summary = Bets.Resolve(t, 1, 2)
	eq(summary.refunded, true); eq(Ledger.Balance(t, "A"), 500)
end)

test("voiding a round returns every stake", function()
	local t = Market(0, { A = 500, B = 400 })
	Bets.Place(t, "A", 1, 1, 500); Bets.Place(t, "B", 1, 2, 400)
	eq(Bets.Void(t, 1), true)
	eq(Ledger.Balance(t, "A"), 500); eq(Ledger.Balance(t, "B"), 400)
	eq(#t.market.bets, 0); eq(t.market.rounds[1].state, "void")
	eq(Bets.Void(t, 1), false)
end)

test("rounds are independent, one bet per player per round", function()
	local t = Market(0, { A = 1000, B = 500 })
	eq(Bets.Place(t, "A", 1, 1, 500), true)
	local again, why = Bets.Place(t, "A", 1, 2, 100)
	eq(again, false); eq(why, "you already have a bet on that round")
	eq(Bets.Place(t, "A", 2, 2, 100), true)
	Bets.Place(t, "B", 1, 2, 500)
	eq(select(2, Bets.Pools(t.market, 1)), 1000); eq(select(2, Bets.Pools(t.market, 2)), 100)
	Bets.Resolve(t, 1, 2)
	eq(Ledger.Balance(t, "B"), 1000); eq(t.market.rounds[2].state, "open")
	eq(Ledger.Balance(t, "A"), 400)
end)

test("an unpaid bet can be cancelled and placed again", function()
	local t = Market(0, {})
	Bets.Place(t, "A", 1, 1, 300)
	eq(Bets.Place(t, "A", 1, 2, 300), false)
	eq(Bets.CancelUnpaid(t, "A", 1), 1)
	eq(Bets.Place(t, "A", 1, 2, 300), true)
end)

test("the host bets for free and is never credited", function()
	local t = Market(0, { A = 500 })
	local _, hostBet = Bets.Place(t, "H", 1, 1, 500, true)
	eq(hostBet.paid, true)
	Bets.Place(t, "A", 1, 2, 500)
	Bets.Resolve(t, 1, 1)
	eq(Ledger.Balance(t, "H"), 0); eq(Ledger.Balance(t, "A"), 0)
end)

test("unpaid bets can be cancelled, and the host may only hold gold for paid ones", function()
	local t = Market(0, { A = 500 })
	Bets.Place(t, "B", 1, 1, 200)
	eq(Bets.HoldsGold(t), false)
	eq(Bets.CancelUnpaid(t, "B", 1), 1); eq(#t.market.bets, 0)
	Bets.Place(t, "A", 1, 1, 500)
	eq(Bets.HoldsGold(t), true)
	Bets.Resolve(t, 1, 1)
	eq(Bets.HoldsGold(t), false)
end)

test("pretend-gold bets never make the host hold gold, real paid ones do", function()
	local t = Market(0, { A = 300 })
	Bets.Place(t, "B", 1, 1, 100, true)
	eq(Bets.HoldsGold(t), false)
	Bets.Place(t, "A", 1, 2, 300)
	eq(Bets.HoldsGold(t), true)
end)

test("a round can be removed until real money is paid in on it, and the rest renumber", function()
	local t = Market(0, { A = 500 })
	Bets.AddRound(t.market, "Third", { "X", "Y" })
	Bets.Place(t, "A", 2, 1, 500)
	eq(Bets.CanRemove(t, 2), false)
	eq(Bets.RemoveRound(t, 2), false)
	Bets.Place(t, "B", 1, 1, 100)
	Bets.Place(t, "C", 1, 2, 100, true)
	Bets.Place(t, "C", 3, 1, 100, true)
	eq(Bets.CanRemove(t, 1), true)
	eq(Bets.RemoveRound(t, 1), true)
	eq(#t.market.rounds, 2); eq(t.market.rounds[1].title, "Second fight"); eq(t.market.rounds[2].title, "Third")
	eq(#t.market.bets, 2)
	eq(t.market.bets[1].round, 1); eq(t.market.bets[2].round, 2)
	eq(Ledger.Balance(t, "A"), 0)
end)

test("a called-off round has nothing paid in and can then be removed", function()
	local t = Market(0, { A = 500 })
	Bets.Place(t, "A", 1, 1, 500)
	eq(Bets.CanRemove(t, 1), false)
	Bets.Void(t, 1)
	eq(Bets.CanRemove(t, 1), true)
	eq(Bets.RemoveRound(t, 1), true)
	eq(#t.market.rounds, 1); eq(Ledger.Balance(t, "A"), 500)
end)

test("a preview says what a new bet would win", function()
	local t = Market(0, { A = 500, B = 500 })
	Bets.Place(t, "A", 1, 1, 500)
	eq(Bets.Preview(t.market, 1, 2, 500), 500 + 500)
	eq(Bets.Preview(t.market, 1, 1, 500), 500)
	Bets.Place(t, "B", 1, 2, 500)
	eq(Bets.Preview(t.market, 1, 2, 500), math.floor(1500 * 500 / 1000))
end)

test("bad bets are refused", function()
	local t = Market(0, { A = 500 })
	eq(Bets.Place(t, "A", 9, 1, 100), false)
	eq(Bets.Place(t, "A", 1, 3, 100), false)
	eq(Bets.Place(t, "A", 1, 1, 0), false)
	eq(Bets.Place(t, "A", 1, 1, -5), false)
	eq(Bets.Place(t, "A", 1, 1, ns.BET_CAP + 1), false)
end)

-- History --------------------------------------------------------------------
test("history counts wins, losses, gold, streaks and keeps the last ten", function()
	local h = ns.History.New()
	ns.History.Add(h, "embers", true, 5000, 1)
	ns.History.Add(h, "embers", true, 3000, 2)
	ns.History.Add(h, "oddmanout", true, 0, 3)
	eq(h.played, 3); eq(h.won, 3); eq(h.gained, 8000); eq(h.streak, 3); eq(h.bestWin, 3)
	ns.History.Add(h, "embers", false, -2000, 4)
	eq(h.lost, 1); eq(h.spent, 2000); eq(h.streak, -1); eq(h.bestWin, 3); eq(h.bestLoss, 1)
	ns.History.Add(h, "embers", false, -2000, 5)
	eq(h.streak, -2); eq(h.bestLoss, 2)
	ns.History.Add(h, "embers", true, 100, 6)
	eq(h.streak, 1); eq(h.bestLoss, 2)
	eq(h.recent[1].at, 6); eq(h.recent[1].won, true)
	for i = 7, 20 do ns.History.Add(h, "embers", true, 0, i) end
	eq(#h.recent, 10); eq(h.recent[1].at, 20); eq(h.recent[10].at, 11)
end)

test("side bets tally on their own, once per settled round, and older saves still load", function()
	local h = ns.History.New()
	eq(h.bets, nil)
	eq(ns.History.AddBet(h, "Host|Duel|100", "Duel", true, 4000, 1), true)
	eq(ns.History.AddBet(h, "Host|Duel|100", "Duel", true, 4000, 2), false)  -- same round again
	eq(ns.History.AddBet(h, "Host|Race|200", "Race", false, -1500, 3), true)
	eq(h.bets.placed, 2); eq(h.bets.won, 1); eq(h.bets.lost, 1)
	eq(h.bets.gained, 4000); eq(h.bets.spent, 1500)
	eq(h.bets.recent[1].label, "Race"); eq(h.bets.recent[2].net, 4000)
	eq(h.played, 0)  -- the games record is untouched
	for i = 1, 60 do ns.History.AddBet(h, "k" .. i, "x", true, 0, i) end
	eq(#h.bets.recent, 10); eq(#h.bets.seen, ns.History.KEEP_SEEN)
	eq(ns.History.AddBet(h, "k60", "x", true, 0, 99), false)  -- recent keys are still remembered
end)

-- Quips ----------------------------------------------------------------------
local Quips = ns.Quips

test("every kind of quip has lines and only real-looking emotes", function()
	for _, kind in ipairs({ "start", "win", "lose", "streak_win", "streak_lose", "roll_high", "roll_low", "bust", "cashout", "ambient", "begun" }) do
		eq(#Quips.lines[kind] >= 3, true)
	end
	for kind, list in pairs(Quips.emotes) do
		eq(Quips.lines[kind] ~= nil, true)
		for _, token in ipairs(list) do eq(token, token:upper()) end
	end
end)

test("picking a line skips recent ones when it can", function()
	local recent = {}
	for i = 1, #Quips.lines.win - 1 do recent[Quips.lines.win[i]] = true end
	for _ = 1, 20 do
		eq(Quips.Pick("win", function(lo, hi) return math.random(lo, hi) end, recent), Quips.lines.win[#Quips.lines.win])
	end
	for _, line in ipairs(Quips.lines.win) do recent[line] = true end
	eq(type(Quips.Pick("win", function(lo) return lo end, recent)), "string")
	eq(Quips.Pick("nonsense", math.random), nil)
end)

test("streaks start at three in a row", function()
	eq(Quips.StreakKind(2), nil); eq(Quips.StreakKind(3), "streak_win"); eq(Quips.StreakKind(7), "streak_win")
	eq(Quips.StreakKind(-2), nil); eq(Quips.StreakKind(-3), "streak_lose"); eq(Quips.StreakKind(nil), nil)
end)

test("a roll is high in the top fifth of the die and low in the bottom fifth", function()
	eq(Quips.RollKind(20, 20), "roll_high"); eq(Quips.RollKind(17, 20), "roll_high"); eq(Quips.RollKind(16, 20), nil)
	eq(Quips.RollKind(1, 20), "roll_low"); eq(Quips.RollKind(4, 20), "roll_low"); eq(Quips.RollKind(5, 20), nil)
	eq(Quips.RollKind(6, 6), "roll_high"); eq(Quips.RollKind(3, 6), nil); eq(Quips.RollKind(1, 1), nil)
end)

-- Game list ------------------------------------------------------------------
test("the picker lists each game once, and the playable ones have rules", function()
	local seen, ready = {}, 0
	for _, entry in ipairs(ns.GAME_LIST) do
		eq(seen[entry.key], nil)
		seen[entry.key] = true
		if entry.ready then
			ready = ready + 1
			eq(type(ns.Games[entry.key]), "table"); eq(type(ns.Games[entry.key].New), "function")
		end
	end
	eq(ready >= 2, true)
	eq(ns.GameReady("embers"), true); eq(ns.GameReady("oddmanout"), true)
	eq(ns.GameReady("critters"), false); eq(ns.GameReady("nonsense"), false)
	eq(ns.GameName("oddmanout"), "The Odd Man Out"); eq(ns.GameName("critters"), "Critter Race")
end)

-- The Odd Man Out ------------------------------------------------------------
local Odd = ns.Games.oddmanout

local function picked(s, list)
	for _, p in ipairs(list) do eq(Odd.Pick(s, p[1], p[2]), true) end
end
local function oddRolls(s, list)
	for _, p in ipairs(list) do eq(Odd.Roll(s, p[1], p[2]), true) end
end

test("the die is d10 for five or fewer players and d20 for six or more", function()
	eq(Odd.RangeFor(2), 10); eq(Odd.RangeFor(5), 10); eq(Odd.RangeFor(6), 20); eq(Odd.RangeFor(10), 20)
	eq(Odd.New({ "A", "B", "C", "D", "E" }).range, 10)
	eq(Odd.New({ "A", "B", "C", "D", "E", "F" }).range, 20)
end)

test("picks are checked against the die and can change until the last one is in", function()
	local s = Odd.New({ "A", "B", "C" })
	eq(Odd.Pick(s, "A", 11), false); eq(Odd.Pick(s, "A", 0), false); eq(Odd.Pick(s, "A", 2.5), false)
	eq(Odd.Pick(s, "Z", 3), false)
	eq(Odd.Pick(s, "A", 5), true); eq(Odd.Pick(s, "A", 6), true)
	eq(s.picks.A, 6); eq(s.phase, "pick")
	picked(s, { { "B", 7 }, { "C", 9 } })
	eq(s.phase, "roll")
	eq(Odd.Pick(s, "A", 1), false)
end)

test("you're knocked out when someone else rolls your number", function()
	local s = Odd.New({ "A", "B", "C" })
	picked(s, { { "A", 5 }, { "B", 7 }, { "C", 9 } })
	oddRolls(s, { { "A", 7 }, { "B", 1 }, { "C", 2 } })
	eq(s.out.B.reason, "knocked out"); eq(s.out.B.pick, 7)
	eq(names(Odd.Alive(s)), "A,C"); eq(s.phase, "roll"); eq(s.round, 2)
	eq(s.picks.A, 5)
	eq(names(s.last.knocked), "B")
end)

test("your own roll never knocks you out", function()
	local s = Odd.New({ "A", "B", "C" })
	picked(s, { { "A", 5 }, { "B", 7 }, { "C", 9 } })
	oddRolls(s, { { "A", 5 }, { "B", 1 }, { "C", 2 } })
	eq(names(Odd.Alive(s)), "A,B,C"); eq(#s.last.knocked, 0); eq(s.round, 2)
end)

test("players can share a number: only the others are hit by a roll of it", function()
	local s = Odd.New({ "A", "B", "C" })
	picked(s, { { "A", 5 }, { "B", 5 }, { "C", 3 } })
	oddRolls(s, { { "A", 5 }, { "B", 1 }, { "C", 2 } })
	eq(names(Odd.Alive(s)), "A,C")
	local t = Odd.New({ "A", "B", "C" })
	picked(t, { { "A", 5 }, { "B", 5 }, { "C", 3 } })
	oddRolls(t, { { "A", 5 }, { "B", 5 }, { "C", 2 } })
	eq(t.over, true); eq(t.winner, "C")
end)

test("a quiet round widens the net: a near miss counts", function()
	local s = Odd.New({ "A", "B" })
	picked(s, { { "A", 3 }, { "B", 8 } })
	oddRolls(s, { { "A", 1 }, { "B", 10 } })
	eq(#s.last.knocked, 0); eq(s.reach, 1)
	oddRolls(s, { { "A", 7 }, { "B", 10 } })
	eq(s.last.reach, 1); eq(s.out.B.reason, "knocked out"); eq(s.winner, "A")
end)

test("near misses wrap around: 10 is next to 1", function()
	local s = Odd.New({ "A", "B" })
	picked(s, { { "A", 1 }, { "B", 5 } })
	oddRolls(s, { { "A", 2 }, { "B", 7 } })
	eq(s.reach, 1)
	oddRolls(s, { { "A", 8 }, { "B", 10 } })
	eq(s.out.A.reason, "knocked out"); eq(s.winner, "B")
end)

test("reach grows each quiet round up to a cap", function()
	eq(Odd.MaxReach(10), 2); eq(Odd.MaxReach(20), 4)
	local s = Odd.New({ "A", "B" })
	picked(s, { { "A", 1 }, { "B", 6 } })
	local seen = {}
	for _ = 1, 4 do
		seen[#seen + 1] = s.reach
		oddRolls(s, { { "A", 2 }, { "B", 5 } })
	end
	eq(table.concat(seen, ","), "0,1,2,2")
	eq(s.reach, 2)
end)

test("reach resets when someone is knocked out", function()
	local s = Odd.New({ "A", "B", "C" })
	picked(s, { { "A", 1 }, { "B", 5 }, { "C", 9 } })
	oddRolls(s, { { "A", 3 }, { "B", 7 }, { "C", 7 } })
	oddRolls(s, { { "A", 3 }, { "B", 7 }, { "C", 7 } })
	eq(s.reach, 2)
	oddRolls(s, { { "A", 3 }, { "B", 5 }, { "C", 5 } })
	eq(names(Odd.Alive(s)), "A,C"); eq(s.out.B.reason, "knocked out"); eq(s.reach, 0)
end)

test("a wipeout backs the reach off a step and replays", function()
	local s = Odd.New({ "A", "B" })
	picked(s, { { "A", 3 }, { "B", 8 } })
	oddRolls(s, { { "A", 1 }, { "B", 10 } })
	oddRolls(s, { { "A", 1 }, { "B", 10 } })
	eq(s.reach, 2)
	oddRolls(s, { { "A", 6 }, { "B", 4 } })
	eq(s.last.wipeout, true); eq(s.reach, 1); eq(names(Odd.Alive(s)), "A,B")
end)

test("a shrinking die resets the reach along with the picks", function()
	local list = {}
	for i = 1, 7 do list[i] = "P" .. i end
	local s = Odd.New(list)
	for i = 1, 7 do Odd.Pick(s, "P" .. i, i * 2) end
	local function round(picks)
		for i = 1, 7 do
			local name = "P" .. i
			if s.waiting[name] then Odd.Roll(s, name, picks[name] or 19) end
		end
	end
	round({})
	eq(s.reach, 1); eq(s.range, 20)
	round({ P1 = 5, P5 = 9 })
	eq(names(Odd.Alive(s)), "P1,P5,P6,P7")
	eq(s.range, 10); eq(s.phase, "pick"); eq(s.reach, 0); eq(next(s.picks), nil)
end)

test("a round that would knock everyone out is replayed", function()
	local s = Odd.New({ "A", "B" })
	picked(s, { { "A", 1 }, { "B", 2 } })
	oddRolls(s, { { "A", 2 }, { "B", 1 } })
	eq(s.last.wipeout, true); eq(#s.last.knocked, 0)
	eq(names(Odd.Alive(s)), "A,B"); eq(s.wipeouts, 1); eq(s.phase, "roll"); eq(s.round, 2)
end)

test("the last player standing wins", function()
	local s = Odd.New({ "A", "B", "C" })
	picked(s, { { "A", 5 }, { "B", 7 }, { "C", 9 } })
	oddRolls(s, { { "A", 7 }, { "B", 1 }, { "C", 2 } })
	oddRolls(s, { { "A", 9 }, { "C", 1 } })
	eq(s.over, true); eq(s.winner, "A"); eq(s.phase, "over")
	eq(names(Odd.Winners(s)), "A")
end)

test("the die shrinks as players drop and everyone picks again", function()
	local list = {}
	for i = 1, 7 do list[i] = "P" .. i end
	local s = Odd.New(list)
	eq(s.range, 20)
	for i = 1, 7 do eq(Odd.Pick(s, "P" .. i, i), true) end
	for i = 1, 7 do
		local v = (i == 1 and 2) or (i == 3 and 4) or 20
		eq(Odd.Roll(s, "P" .. i, v), true)
	end
	eq(names(Odd.Alive(s)), "P1,P3,P5,P6,P7")
	eq(s.range, 10); eq(s.phase, "pick"); eq(next(s.picks), nil)
	eq(Odd.Pick(s, "P1", 15), false)
	for _, name in ipairs(Odd.Alive(s)) do eq(Odd.Pick(s, name, 3), true) end
	eq(s.phase, "roll")
end)

test("rolls must be on the die and only once a round", function()
	local s = Odd.New({ "A", "B", "C" })
	picked(s, { { "A", 5 }, { "B", 7 }, { "C", 9 } })
	eq(Odd.Roll(s, "A", 11), false); eq(Odd.Roll(s, "A", 0), false)
	eq(Odd.Roll(s, "A", 3, 20), false)
	eq(Odd.Roll(s, "A", 3, 10), true)
	eq(Odd.Roll(s, "A", 4), false)
	eq(Odd.Roll(s, "Z", 4), false)
end)

test("folding in the pick phase, in the roll phase, and with one left", function()
	local s = Odd.New({ "A", "B", "C" })
	picked(s, { { "A", 5 } })
	eq(Odd.Fold(s, "B"), true)
	eq(s.phase, "pick"); eq(names(Odd.Waiting(s)), "C")
	picked(s, { { "C", 9 } })
	eq(s.phase, "roll")

	local t = Odd.New({ "A", "B", "C", "D" })
	picked(t, { { "A", 1 }, { "B", 2 }, { "C", 3 }, { "D", 4 } })
	oddRolls(t, { { "A", 9 }, { "B", 9 } })
	Odd.Fold(t, "C")
	eq(names(Odd.Waiting(t)), "D")
	oddRolls(t, { { "D", 1 } })
	eq(t.out.C.reason, "folded"); eq(t.out.A.reason, "knocked out")
	eq(names(Odd.Alive(t)), "B,D")

	local u = Odd.New({ "A", "B" })
	Odd.Fold(u, "A")
	eq(u.over, true); eq(u.winner, "B")
end)

test("everyone timing out together leaves no winner", function()
	local s = Odd.New({ "A", "B", "C" })
	eq(Odd.FoldMany(s, { "A", "B", "C" }), true)
	eq(s.over, true); eq(s.winner, nil); eq(#Odd.Winners(s), 0)
end)

test("a fold in the pick phase can shrink the die and restart the picks", function()
	local list = {}
	for i = 1, 6 do list[i] = "P" .. i end
	local s = Odd.New(list)
	picked(s, { { "P1", 15 }, { "P2", 12 } })
	Odd.Fold(s, "P3")
	eq(s.range, 10); eq(next(s.picks), nil); eq(#Odd.Waiting(s), 5)
end)

-- Honest Broker ----------------------------------------------------------------
local Rep = ns.Rep

-- A store where each listed rater says something about host H: { rater, trust, pace, unpaid }.
local function Rated(list, now)
	local store = Rep.New()
	for _, e in ipairs(list) do
		Rep.Merge(store, { h = "H-R", r = e[1], t = e[2], p = e[3], up = e[4], at = now or 100 }, e[1], "Me-R", now or 100)
	end
	return store
end

test("a host is New until three different players have rated them", function()
	local store = Rated({ { "A-R", 1, 1 }, { "B-R", 1, 1 } })
	eq(Rep.Badge(Rep.Summary(store, "H-R")), "new")
	eq(Rep.Label(Rep.Summary(store, "H-R")), "New")
	Rep.Merge(store, { h = "H-R", r = "C-R", t = 1, p = 1, at = 100 }, "C-R", "Me-R", 100)
	local s = Rep.Summary(store, "H-R")
	eq(Rep.Badge(s), "trusted"); eq(Rep.Pace(s), "quick"); eq(Rep.Label(s), "Trusted, quick")
end)

test("unpaid and unfair reports make a host Mixed, then Avoid", function()
	local store = Rated({ { "A-R", 1, 2 }, { "B-R", 1, 2 }, { "C-R", 1, 3 }, { "D-R", nil, nil, 500 } })
	eq(Rep.Badge(Rep.Summary(store, "H-R")), "trusted")  -- one bad in four isn't enough
	Rep.Merge(store, { h = "H-R", r = "E-R", t = -1, at = 100 }, "E-R", "Me-R", 100)
	eq(Rep.Badge(Rep.Summary(store, "H-R")), "mixed")
	for _, r in ipairs({ "F-R", "G-R" }) do Rep.Merge(store, { h = "H-R", r = r, up = 900, at = 100 }, r, "Me-R", 100) end
	local s = Rep.Summary(store, "H-R")
	eq(Rep.Badge(s), "avoid"); eq(s.unpaid, 3); eq(Rep.Label(s), "Avoid: 3 unpaid")
	local few = Rated({ { "A-R", nil, nil, 100 } })
	eq(Rep.Label(Rep.Summary(few, "H-R")), "New, 1 unpaid")
end)

test("one player's word counts once, their own beats hearsay, and nobody speaks for us", function()
	local store = Rep.New()
	eq(Rep.Merge(store, { h = "H-R", r = "A-R", t = -1, at = 100 }, "X-R", "Me-R", 200), true)  -- passed along
	eq(Rep.Merge(store, { h = "H-R", r = "A-R", t = -1, at = 90 }, "Y-R", "Me-R", 200), false)  -- older hearsay
	eq(Rep.Merge(store, { h = "H-R", r = "A-R", t = 1, at = 50 }, "A-R", "Me-R", 200), true)    -- A says it themself
	eq(Rep.Merge(store, { h = "H-R", r = "A-R", t = -1, at = 150 }, "X-R", "Me-R", 200), false) -- hearsay can't undo it
	eq(Rep.Summary(store, "H-R").raters, 1); eq(Rep.Summary(store, "H-R").fair, 1)
	eq(Rep.Merge(store, { h = "H-R", r = "Me-R", t = -1, at = 150 }, "X-R", "Me-R", 200), false)
	eq(Rep.Merge(store, { h = "H-R", r = "H-R", t = 1, at = 150 }, "H-R", "Me-R", 200), false)  -- rating yourself
	eq(Rep.Merge(store, { h = "H-R", r = "B-R", t = 1, at = 9999 }, "B-R", "Me-R", 200), false) -- from the future
	eq(Rep.Merge(store, { h = "H-R", r = "B-R", t = 7, at = 150 }, "B-R", "Me-R", 200), false)  -- nonsense
	eq(Rep.Merge(store, { h = "Rat (bot)", r = "B-R", t = 1, at = 150 }, "B-R", "Me-R", 200), false)
end)

test("the payout clock: paid in time is on record, late is unpaid until it's paid", function()
	local store = Rep.New()
	Rep.Owe(store, "Host Name-R", 1000, 0)
	eq(select(2, Rep.Received(store, "Me-R", "Host", 400, 10)), 400)  -- the trade window says "Host"
	eq(store.owed["Host Name-R"].c, 600)
	eq(Rep.CheckOwed(store, "Me-R", Rep.GRACE - 1), false)
	eq(Rep.CheckOwed(store, "Me-R", Rep.GRACE), true)
	local s = Rep.Summary(store, "Host Name-R")
	eq(s.unpaid, 1); eq(s.overdue, 600); eq(s.paid, 400)
	Rep.Received(store, "Me-R", "Host", 600, Rep.GRACE + 50)
	s = Rep.Summary(store, "Host Name-R")
	eq(s.unpaid, 0); eq(s.paid, 1000); eq(store.owed["Host Name-R"], nil)
	eq(Rep.Received(store, "Me-R", "Stranger", 500, 700), nil)  -- trades with anyone else don't count
	Rep.Owe(store, "Other-R", 300, 0)
	Rep.CheckOwed(store, "Me-R", Rep.GRACE)
	Rep.Clear(store, "Me-R", "Other-R", Rep.GRACE + 1)  -- /bf rep paid Other
	eq(Rep.Summary(store, "Other-R").unpaid, 0); eq(store.owed["Other-R"], nil)
end)

test("a digest carries our own records first, each name once, and unpacks the same", function()
	local store = Rated({ { "A-R", 1, 1 }, { "B-R", -1, 3, 200 } }, 100)
	Rep.Set(store, "Me-R", "H-R", { t = 1, p = 2 }, 50)
	Rep.Set(store, "Me-R", "Rat (bot)", { t = 1 }, 60)  -- practice hosts never travel
	local d = Rep.Digest(store, "Me-R", 200, 2)
	eq(#d.r, 2); eq(d.n[d.r[1][2]], "Me-R")
	eq(#d.n, 3)  -- H-R, Me-R and one other rater
	local back = Rep.Unpack(d)
	eq(back[1].h, "H-R"); eq(back[1].t, 1); eq(back[1].p, 2); eq(back[1].up, nil)
	eq(Rep.Unpack({ n = "x", r = {} }), nil)
	eq(#Rep.Unpack({ n = { "A" }, r = { { 1, 9, 1, 1, 0, 0, 5 }, "junk" } }), 0)
	local other = Rep.New()
	for _, rec in ipairs(Rep.Unpack(Rep.Digest(store, "Me-R", 200, 12))) do Rep.Merge(other, rec, "Me-R", "You-R", 200) end
	eq(Rep.Summary(other, "H-R").raters, 3)
end)

test("old records are forgotten and the store stays bounded", function()
	local store = Rep.New()
	Rep.Merge(store, { h = "H-R", r = "A-R", t = 1, at = 0 }, "X-R", "Me-R", 0)
	Rep.Merge(store, { h = "H-R", r = "B-R", t = 1, at = Rep.EXPIRE }, "X-R", "Me-R", Rep.EXPIRE)
	Rep.Prune(store, Rep.EXPIRE + 10)
	eq(store.hosts["H-R"]["A-R"], nil); eq(store.hosts["H-R"]["B-R"] ~= nil, true)
	local keep = Rep.KEEP
	Rep.KEEP = 3
	for i = 1, 6 do Rep.Merge(store, { h = "H" .. i, r = "A-R", t = 1, at = Rep.EXPIRE + i }, "X-R", "Me-R", Rep.EXPIRE + 10) end
	Rep.Prune(store, Rep.EXPIRE + 10)
	local count = 0
	for _, raters in pairs(store.hosts) do for _ in pairs(raters) do count = count + 1 end end
	Rep.KEEP = keep
	eq(count, 3); eq(store.hosts["H6"] ~= nil, true); eq(store.hosts["H1"], nil)
	eq(Rep.Find(store, "h6"), "H6")
end)

-- Comms ------------------------------------------------------------------------
-- Uses the real AceSerializer from Libs\ (made by scripts\setup.ps1); skipped without it.
if io.open("Libs/AceSerializer-3.0/AceSerializer-3.0.lua") then
	dofile("Libs/LibStub/LibStub.lua")
	dofile("Libs/AceSerializer-3.0/AceSerializer-3.0.lua")
	local clock, timers, sends, errors = 0, {}, {}, {}
	rawset(_G, "GetTime", function() return clock end)
	rawset(_G, "C_Timer", { After = function(delay, fn) timers[#timers + 1] = { at = clock + delay, fn = fn } end })
	rawset(_G, "geterrorhandler", function() return function(err) errors[#errors + 1] = err end end)
	ns.FullName = function(name) return name end
	local stub = {}
	LibStub("AceSerializer-3.0"):Embed(stub)
	function stub:SendCommMessage(_, text, distribution, _, _, callback)
		sends[#sends + 1] = { text = text, distribution = distribution, callback = callback }
	end
	ns.Bonfire = stub
	load("Comm.lua")
	ns.Bonfire = nil
	local Comm = ns.Comm
	Comm.id = "me"
	function Comm:ChannelId() return 5 end
	function Comm:Group() end  -- not in a party

	test("a sealed message only opens if every piece arrived in order", function()
		local pad = {}
		for i = 1, 300 do pad[i] = tostring(i) end  -- varied, so any two pieces differ
		local text = stub:Serialize({ k = "S", i = "host", s = { "Drskull Peakabu-Realm", "Ratty (bot)" }, pad = table.concat(pad, ",") })
		eq(Comm.Unseal(Comm.Seal(text)), text)
		eq(Comm.Unseal(text), nil)  -- unsealed can't be checked
		local sealed = Comm.Seal(text)
		local first, a, b, rest = sealed:sub(1, 254), sealed:sub(255, 508), sealed:sub(509, 762), sealed:sub(763)
		eq(Comm.Unseal(first .. b .. rest), nil)       -- a piece went missing
		eq(Comm.Unseal(first .. b .. a .. rest), nil)  -- pieces out of order
	end)

	test("damaged messages are thrown away without an error", function()
		local heard = 0
		Comm.On("Z", function() heard = heard + 1 end)
		Comm.On("Z", function() error("boom") end)
		Comm.On("Z", function() heard = heard + 1 end)
		local bad = Comm.bad
		Comm:Receive(Comm.Seal(stub:Serialize({ k = "Z", n = 3 })), "CHANNEL", "Someone")  -- no sender id: the Lua error you saw
		Comm:Receive("#1|" .. stub:Serialize({ k = "Z", i = "x" }), "CHANNEL", "Someone")    -- wrong checksum
		Comm:Receive("junk", "CHANNEL", "Someone")
		eq(Comm.bad, bad + 3); eq(heard, 0)
		Comm:Receive(Comm.Seal(stub:Serialize({ k = "Z", i = "other", n = 1 })), "CHANNEL", "Someone")
		eq(heard, 2); eq(#errors, 1)  -- one handler failing doesn't stop the rest
	end)

	test("only the newest table state is sent, one at a time, and a lost piece sends it again", function()
		sends = {}
		local version, dropped = 0, 0
		local function make() version = version + 1; return { v = version } end
		local function onDrop() dropped = dropped + 1 end
		Comm:SendLatest("S", make, "ALERT", onDrop)
		eq(#sends, 1)
		Comm:SendLatest("S", make, "ALERT", onDrop)  -- still going out: these just wait
		Comm:SendLatest("S", make, "ALERT", onDrop)
		eq(#sends, 1)
		sends[1].callback(nil, 100, 300, true)
		eq(#sends, 1)
		sends[1].callback(nil, 300, 300, true)  -- last piece out: the newest follows, once
		eq(#sends, 2); eq(version, 2)
		sends[2].callback(nil, 150, 300, false)  -- the game dropped a piece
		sends[2].callback(nil, 300, 300, true)
		eq(dropped, 1); eq(#sends, 2); eq(Comm.dropped, 1)
		clock = clock + 1
		for _, timer in ipairs(timers) do if timer.at <= clock then timer.fn() end end
		eq(#sends, 3); eq(version, 3)
		sends[3].callback(nil, 300, 300, true)
		Comm:SendLatest("S", function() return nil end, "ALERT")  -- nothing new: nothing sent
		eq(#sends, 3)
	end)
else
	print("(comms tests skipped: run scripts\\setup.ps1 to fetch Libs)")
end

-- Source checks ----------------------------------------------------------------
-- AceEvent keeps one handler per event, so two files registering the same event directly means
-- one silently loses it (the host's /roll lines once went unread that way). Only Core.lua's
-- ns.OnEvent may call RegisterEvent.
test("events are registered through ns.OnEvent only", function()
	local toc = assert(io.open("Bonfire.toc")):read("*a")
	for file in toc:gmatch("([%w_/\\]+%.lua)") do
		if file ~= "Core.lua" then
			local src = assert(io.open((file:gsub("\\", "/")))):read("*a")
			if src:find(":RegisterEvent(", 1, true) then error(file .. " calls RegisterEvent directly; use ns.OnEvent") end
		end
	end
end)

print(("%d passed, %d failed"):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
