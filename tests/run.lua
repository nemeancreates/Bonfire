-- Offline tests for pure game logic. Run scripts\test.ps1 (LuaJIT = Lua 5.1, like WoW).
local ns = {}
local function load(file) assert(loadfile(file))("Bonfire", ns) end
load("Roll.lua")
load("Money.lua")
load("Ledger.lua")
load("Games/Embers.lua")

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

print(("%d passed, %d failed"):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
