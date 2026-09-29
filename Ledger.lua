local _, ns = ...

-- The host holds the pot. Players trade their stake to the host before a round;
-- balances[name] is the copper the host is holding for that player. Winnings stay
-- as credit for the next round until the player cashes out or walks away.
-- The host's own money never enters the ledger: it's already in their bags.
--
-- Works on the host's table: { host, stake, seats, balances, cashout, left, committed }.
-- Pure (no WoW API) so tests/run.lua can load it.
local Ledger = {}
ns.Ledger = Ledger

function Ledger.Init(t)
	t.balances, t.cashout, t.left = t.balances or {}, t.cashout or {}, t.left or {}
end

-- True when the host holds nobody's gold: no credit and no stakes in a running pot.
-- Only then can a table pass to a new host, since gold stays with whoever holds it.
function Ledger.Empty(t)
	if t.stake > 0 and t.committed then return false end
	for _, balance in pairs(t.balances) do
		if balance ~= 0 then return false end
	end
	return true
end

function Ledger.Balance(t, name)
	return t.balances[name] or 0
end

-- Copper a seated player still has to hand over to be dealt into the next round.
function Ledger.Owes(t, name)
	if name == t.host then return 0 end
	return math.max(0, t.stake - Ledger.Balance(t, name))
end

-- Seated players who can be dealt in: paid up and not cashing out.
function Ledger.Eligible(t)
	local list = {}
	for _, name in ipairs(t.seats) do
		if Ledger.Owes(t, name) == 0 and not t.cashout[name] then list[#list + 1] = name end
	end
	return list
end

function Ledger.Commit(t, players)
	t.committed = {}
	for i, name in ipairs(players) do
		t.committed[i] = name
		if name ~= t.host then t.balances[name] = Ledger.Balance(t, name) - t.stake end
	end
end

-- The game was abandoned: everyone gets their stake back.
function Ledger.Void(t)
	for _, name in ipairs(t.committed or {}) do
		if name ~= t.host then t.balances[name] = Ledger.Balance(t, name) + t.stake end
	end
	t.committed = nil
end

-- Splits the pot (every committed stake, leavers included) between the winners.
-- Odd coppers go to the first winner. Returns the even share.
function Ledger.Settle(t, winners)
	local pot = t.stake * #(t.committed or {})
	t.committed = nil
	if #winners == 0 then return 0 end
	local share = math.floor(pot / #winners)
	local extra = pot - share * #winners
	for i, name in ipairs(winners) do
		if name ~= t.host then
			t.balances[name] = Ledger.Balance(t, name) + share + (i == 1 and extra or 0)
		end
	end
	return share
end

-- Records a finished game in the table's tally: wins, losses, net copper and the current
-- streak (positive = wins in a row, negative = losses) for every player dealt in.
-- players is who was committed to the game; winners and share come from Settle.
function Ledger.Record(t, players, winners, share)
	t.tally = t.tally or {}
	local won = {}
	for _, name in ipairs(winners) do won[name] = true end
	for _, name in ipairs(players or {}) do
		local r = t.tally[name] or { w = 0, l = 0, net = 0, streak = 0 }
		t.tally[name] = r
		if won[name] then
			r.w, r.net = r.w + 1, r.net + share - t.stake
			r.streak = r.streak > 0 and r.streak + 1 or 1
		else
			r.l, r.net = r.l + 1, r.net - t.stake
			r.streak = r.streak < 0 and r.streak - 1 or -1
		end
	end
end

-- A trade between the host and a player finished. copper > 0: the host received it.
function Ledger.Credit(t, name, copper)
	local balance = Ledger.Balance(t, name) + copper
	t.balances[name] = balance ~= 0 and balance or nil
	if balance <= 0 then
		t.cashout[name] = nil
		t.left[name] = nil
	end
end

function Ledger.Leave(t, name)
	t.cashout[name] = nil
	if Ledger.Balance(t, name) > 0 then t.left[name] = true end
end

-- Seated players who still owe their stake, in seat order.
function Ledger.PayIns(t)
	local list = {}
	for _, name in ipairs(t.seats) do
		local owes = Ledger.Owes(t, name)
		if owes > 0 and not t.cashout[name] then list[#list + 1] = { name, owes } end
	end
	return list
end

-- Who the host has to pay back: cash-outs, players who left, and everyone once
-- the host is putting the fire out.
function Ledger.Payouts(t)
	local list, queued = {}, {}
	local function add(name)
		local balance = Ledger.Balance(t, name)
		if name ~= t.host and balance > 0 and not queued[name] then
			queued[name] = true
			list[#list + 1] = { name, balance }
		end
	end
	for _, name in ipairs(t.seats) do
		if t.cashout[name] or t.state == "settling" then add(name) end
	end
	local gone = {}
	for name in pairs(t.left) do gone[#gone + 1] = name end
	table.sort(gone)
	for _, name in ipairs(gone) do add(name) end
	return list
end
