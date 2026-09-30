local _, ns = ...
local Ledger = ns.Ledger

-- Side bets. A table can run a card of rounds (fights, races), each with two or more
-- sides. Spectators bet on a side; a bet counts once it's paid, either from credit the
-- host already holds for that player or by trading the host the gold. Payouts come from
-- the pool (parimutuel): winners split everything bet, in proportion to their bets, minus
-- an optional host cut. A round nobody bet against, or where nobody backed the winner,
-- refunds every stake.
--
-- Works on the table's `market`: { rounds, bets, cut (percent), current }.
--   round = { title, sides = { names }, state = "open"|"locked"|"done"|"void", winner, lockAt }
--   bet   = { id, who, round, side, amount (copper), paid }
--
-- Pure (no WoW API) so tests/run.lua can load it. Money moves through Ledger balances;
-- the host's own gold is never ledgered, so bets by the host are free and never credited.
local Bets = {
	MAX_ROUNDS = 6,                                                   -- rounds on one card (as many as the window shows)
	MAX_BETS = 1,                                                     -- bets per player per round
	CUTS = { 2, 5, 10, 20 },                                        -- host cut choices, percent
	MODES = { "Duel", "Deathroll", "Critter Race", "Dice", "Custom" }, -- what a round can be
}
ns.Bets = Bets

-- Bets on a round still count as owed while it's open, or locked but the games haven't begun.
local function Collecting(r)
	return r.state == "open" or (r.state == "locked" and not r.started)
end

function Bets.NewMarket(cut)
	return { rounds = {}, bets = {}, cut = cut or 0, nextBet = 1, current = 1 }
end

-- True when every round on the card is settled or called off.
function Bets.AllFinished(m)
	for _, r in ipairs(m.rounds) do
		if r.state ~= "done" and r.state ~= "void" then return false end
	end
	return true
end

-- Whether another round fits: yes below MAX_ROUNDS, or on a full card that's all finished
-- (the next round starts a fresh card).
function Bets.CanAddRound(m)
	return not m or #m.rounds < Bets.MAX_ROUNDS or Bets.AllFinished(m)
end

-- Returns the new round's number and whether it started a fresh card, or nil when the card
-- is full and still has rounds going. A fresh card drops only finished rounds: their bets
-- are already paid out or refunded.
function Bets.AddRound(m, title, sides, lockAt, game)
	if not Bets.CanAddRound(m) then return nil end
	local fresh = #m.rounds >= Bets.MAX_ROUNDS
	if fresh then m.rounds, m.bets, m.current = {}, {}, 1 end
	m.rounds[#m.rounds + 1] = { title = title, sides = sides, state = "open", lockAt = lockAt, game = game or "Custom" }
	return #m.rounds, fresh
end

-- Paid money on each side of a round, and the total.
function Bets.Pools(m, ri)
	local r = m.rounds[ri]
	local pools, total = {}, 0
	for i = 1, #r.sides do pools[i] = 0 end
	for _, b in ipairs(m.bets) do
		if b.round == ri and b.paid then
			pools[b.side] = pools[b.side] + b.amount
			total = total + b.amount
		end
	end
	return pools, total
end

local function Net(m, total)
	return total - math.floor(total * (m.cut or 0) / 100)
end

-- Payout multiplier per side (nil where nothing is bet on that side).
function Bets.Odds(m, ri)
	local pools, total = Bets.Pools(m, ri)
	local net, odds = Net(m, total), {}
	for i, pool in ipairs(pools) do
		if pool > 0 then odds[i] = net / pool end
	end
	return odds
end

-- What a new bet of amount on side would return if that side won, given today's pools.
function Bets.Preview(m, ri, side, amount)
	if amount <= 0 then return 0 end
	local pools, total = Bets.Pools(m, ri)
	if total - pools[side] == 0 then return amount end  -- nothing against it yet: stake back
	return math.floor(Net(m, total + amount) * amount / (pools[side] + amount))
end

-- What each paid bet gets back if winner wins: bet id -> copper. Also whether it's a
-- refund, and the host's cut. Used by the host to settle and by everyone to display.
function Bets.Payouts(m, ri, winner)
	local pools, total = Bets.Pools(m, ri)
	local pay = {}
	if total == 0 then return pay, false, 0 end
	local backed = pools[winner] or 0
	if backed == 0 or backed == total then
		for _, b in ipairs(m.bets) do
			if b.round == ri and b.paid then pay[b.id] = b.amount end
		end
		return pay, true, 0
	end
	local net = Net(m, total)
	for _, b in ipairs(m.bets) do
		if b.round == ri and b.paid and b.side == winner then
			pay[b.id] = math.floor(net * b.amount / backed)
		end
	end
	return pay, false, total - net
end

-- Pays unpaid bets from credit the host already holds for the bettor.
function Bets.Fund(t)
	local m = t.market
	if not m then return end
	for _, b in ipairs(m.bets) do
		local r = m.rounds[b.round]
		if not b.paid and r and Collecting(r) and b.who ~= t.host and Ledger.Balance(t, b.who) >= b.amount then
			Ledger.Credit(t, b.who, -b.amount)
			b.paid = true
		end
	end
end

-- free: the bet is paid on the spot (the host's own gold, or a practice player's).
function Bets.Place(t, who, ri, side, amount, free)
	local m = t.market
	local r = m and m.rounds[ri]
	if not r then return false, "no such round" end
	if r.state ~= "open" then return false, "betting is closed on that round" end
	if type(side) ~= "number" or not r.sides[side] then return false, "no such side" end
	amount = math.floor(tonumber(amount) or 0)
	if amount <= 0 or amount > ns.BET_CAP then return false, "that amount isn't allowed" end
	local mine = 0
	for _, b in ipairs(m.bets) do
		if b.who == who and b.round == ri then mine = mine + 1 end
	end
	if mine >= Bets.MAX_BETS then return false, "you already have a bet on that round" end
	local bet = { id = m.nextBet, who = who, round = ri, side = side, amount = amount, paid = free or false, free = free or false }
	m.nextBet = m.nextBet + 1
	m.bets[#m.bets + 1] = bet
	Bets.Fund(t)
	return true, bet
end

-- Drops a player's unpaid bets on a round. Returns how many.
function Bets.CancelUnpaid(t, who, ri)
	local m, n = t.market, 0
	for i = #m.bets, 1, -1 do
		local b = m.bets[i]
		if b.who == who and b.round == ri and not b.paid then
			table.remove(m.bets, i)
			n = n + 1
		end
	end
	return n
end

-- Copper a player has bet but not yet paid, on rounds still open.
function Bets.Unpaid(m, who)
	local sum = 0
	for _, b in ipairs(m.bets) do
		if b.who == who and not b.paid and Collecting(m.rounds[b.round]) then sum = sum + b.amount end
	end
	return sum
end

-- Bettors the host still has to collect from: { name, copper owed }.
function Bets.Owing(t)
	local m, list, seen = t.market, {}, {}
	if not m then return list end
	for _, b in ipairs(m.bets) do
		if not b.paid and not seen[b.who] and b.who ~= t.host then
			seen[b.who] = true
			local owed = math.max(0, Bets.Unpaid(m, b.who) - Ledger.Balance(t, b.who))
			if owed > 0 then list[#list + 1] = { b.who, owed } end
		end
	end
	return list
end

-- True while the host holds other people's real money for bets that haven't been settled.
-- Free bets (the host's own, or a practice player's pretend gold) don't count.
function Bets.HoldsGold(t)
	local m = t.market
	if not m then return false end
	for _, b in ipairs(m.bets) do
		local r = m.rounds[b.round]
		if b.paid and not b.free and b.who ~= t.host and (r.state == "open" or r.state == "locked") then return true end
	end
	return false
end

-- A round can be removed from the card while no real money is paid in on it. Pretend-gold
-- bets and unpaid ones don't count; if real gold is in, it has to be called off (refunded)
-- instead, so a paid round never just vanishes.
function Bets.CanRemove(t, ri)
	for _, b in ipairs(t.market.bets) do
		if b.round == ri and b.paid and not b.free and b.who ~= t.host then return false end
	end
	return true
end

-- Takes the round off the card and renumbers the ones after it. Returns true if removed.
function Bets.RemoveRound(t, ri)
	local m = t.market
	if not m.rounds[ri] or not Bets.CanRemove(t, ri) then return false end
	for i = #m.bets, 1, -1 do
		local b = m.bets[i]
		if b.round == ri then
			table.remove(m.bets, i)
		elseif b.round > ri then
			b.round = b.round - 1
		end
	end
	table.remove(m.rounds, ri)
	m.current = math.max(1, math.min(m.current or 1, #m.rounds))
	return true
end

-- Closes betting on a round. Its unpaid bets stay on the books until the games begin, so
-- everyone can pay what they owe across every round in one go. Returns how many bets are
-- still unpaid, or false if the round wasn't open.
function Bets.Lock(t, ri)
	local m = t.market
	local r = m and m.rounds[ri]
	if not r or r.state ~= "open" then return false end
	Bets.Fund(t)
	r.state = "locked"
	local unpaid = 0
	for _, b in ipairs(m.bets) do
		if b.round == ri and not b.paid then unpaid = unpaid + 1 end
	end
	return unpaid
end

-- Where the card is: "betting" while any round is open, "payment" once every round is
-- locked but the games haven't begun, "live" until each round is settled, then "done".
function Bets.Phase(m)
	local locked, waiting = false, false
	for _, r in ipairs(m.rounds) do
		if r.state == "open" then return "betting" end
		if r.state == "locked" then
			locked = true
			if not r.started then waiting = true end
		end
	end
	if waiting then return "payment" end
	return locked and "live" or "done"
end

-- Everyone with money on the card: { who, total bet, paid, still owes }, biggest debt first,
-- then the totals owed and paid. The host's own bets aren't listed.
function Bets.Payments(t)
	local m = t.market
	local rows, by = {}, {}
	for _, b in ipairs(m.bets) do
		local r = m.rounds[b.round]
		if (r.state == "open" or r.state == "locked") and b.who ~= t.host then
			local row = by[b.who]
			if not row then
				row = { who = b.who, total = 0, paid = 0 }
				by[b.who] = row
				rows[#rows + 1] = row
			end
			row.total = row.total + b.amount
			if b.paid then row.paid = row.paid + b.amount end
		end
	end
	local owedTotal, paidTotal = 0, 0
	for _, row in ipairs(rows) do
		row.owes = math.max(0, row.total - row.paid - Ledger.Balance(t, row.who))
		owedTotal, paidTotal = owedTotal + row.owes, paidTotal + row.paid
	end
	table.sort(rows, function(x, y)
		if x.owes ~= y.owes then return x.owes > y.owes end
		return x.who < y.who
	end)
	return rows, owedTotal, paidTotal
end

-- The round's unpaid bets are dropped and it goes live. Returns how many were dropped.
function Bets.StartRound(t, ri)
	local m = t.market
	local r = m.rounds[ri]
	if not r or r.state ~= "locked" or r.started then return 0 end
	Bets.Fund(t)
	local dropped = 0
	for i = #m.bets, 1, -1 do
		local b = m.bets[i]
		if b.round == ri and not b.paid then
			table.remove(m.bets, i)
			dropped = dropped + 1
		end
	end
	r.started = true
	return dropped
end

-- Begins the games: whatever's still unpaid is dropped and every locked round goes live.
function Bets.Begin(t)
	local dropped = 0
	for i in ipairs(t.market.rounds) do dropped = dropped + Bets.StartRound(t, i) end
	return dropped
end

local function Tally(t, who, won, net)
	t.tally = t.tally or {}
	local r = t.tally[who] or { w = 0, l = 0, net = 0, streak = 0 }
	t.tally[who] = r
	if won then
		r.w, r.streak = r.w + 1, r.streak > 0 and r.streak + 1 or 1
	else
		r.l, r.streak = r.l + 1, r.streak < 0 and r.streak - 1 or -1
	end
	r.net = r.net + net
end

-- The round has a winner: pay the winners into their held credit. Returns ok and a summary.
function Bets.Resolve(t, ri, winner)
	local m = t.market
	local r = m and m.rounds[ri]
	if not r or r.state == "done" or r.state == "void" or not r.sides[winner] then return false end
	if r.state == "open" then Bets.Lock(t, ri) end
	Bets.StartRound(t, ri)
	local pay, refunded, cut = Bets.Payouts(m, ri, winner)
	r.state, r.winner = "done", winner
	local paidOut = 0
	for _, b in ipairs(m.bets) do
		if b.round == ri and b.paid then
			local got = pay[b.id] or 0
			if got > 0 and b.who ~= t.host then Ledger.Credit(t, b.who, got) end
			paidOut = paidOut + got
			if not refunded then Tally(t, b.who, got > 0, got - b.amount) end
		end
	end
	return true, { refunded = refunded, cut = cut, paidOut = paidOut }
end

-- Cancels a round: every stake goes back to its bettor's held credit.
function Bets.Void(t, ri)
	local m = t.market
	local r = m and m.rounds[ri]
	if not r or r.state == "done" or r.state == "void" then return false end
	for i = #m.bets, 1, -1 do
		local b = m.bets[i]
		if b.round == ri then
			if b.paid and b.who ~= t.host then Ledger.Credit(t, b.who, b.amount) end
			table.remove(m.bets, i)
		end
	end
	r.state = "void"
	return true
end

function Bets.VoidAll(t)
	for i in ipairs(t.market and t.market.rounds or {}) do Bets.Void(t, i) end
end
