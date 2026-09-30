local _, ns = ...

-- Deathroll, in two flavours that share one finish:
--
--  All out: every player rolls 1..start at the same time. If an even number rolled, the
--  highest AND lowest roller are knocked out; if odd, only the highest. Ties for an
--  extreme re-roll among just the tied players. This repeats until two remain.
--
--  The duel: the last two take turns. The first rolls 1..start, each next roll is
--  1..(the roll before). Whoever rolls a 1 loses the pot. A classic 1v1 starts at 100;
--  the final roll-off of an all-out game (3 or more players) starts at 10.
--
-- Anyone who doesn't roll in time is folded by the host (Deathroll.Fold): out
-- immediately, and in the duel that hands the win to the other player.
--
-- Pure rules, no WoW API, so tests/run.lua can load it. The host feeds in real /roll
-- results and does the timing.
local Deathroll = { name = "Deathroll", sides = 100, finalStart = 10, rollSeconds = 8 }
ns.Games = ns.Games or {}
ns.Games.deathroll = Deathroll

local function Set(list)
	local set = {}
	for _, name in ipairs(list) do set[name] = true end
	return set
end

function Deathroll.Alive(s)
	local list = {}
	for _, name in ipairs(s.order) do
		if s.alive[name] then list[#list + 1] = name end
	end
	return list
end

local function Eliminate(s, name, reason)
	if not s.alive[name] then return end
	s.alive[name] = nil
	s.out[name] = reason
	s.rolls[name] = nil
	s.outOrder[#s.outOrder + 1] = name
end

local function Finish(s, winner)
	s.phase, s.over, s.winner, s.waiting = "over", true, winner, {}
end

-- Starts whatever comes next for the players still alive.
local function Begin(s)
	local alive = Deathroll.Alive(s)
	if #alive <= 1 then return Finish(s, alive[1]) end
	if #alive == 2 then
		-- Whoever rolled higher in the last all-out round rolls first; a tie (or a classic 1v1,
		-- where nobody has rolled) goes by seat order.
		local rolls = (s.pool and s.pool.rolls) or s.rolls or {}
		local first, second = alive[1], alive[2]
		if (rolls[second] or 0) > (rolls[first] or 0) then first, second = second, first end
		s.phase = "duel"
		s.duel = { roller = first, other = second, max = s.duelStart or s.start }
		s.waiting = { [first] = true }
		return
	end
	s.phase, s.rolls, s.waiting, s.pool, s.tie = "round", {}, Set(alive), nil, nil
end

-- Picks the highest or lowest of names by rolls[name]. Returns the name, or nil
-- with a new tie-break round started among the tied players.
local function Pick(s, names, kind)
	local best, tied
	for _, name in ipairs(names) do
		local v = s.rolls[name]
		if v and (not best or (kind == "high" and v > best) or (kind == "low" and v < best)) then best = v end
	end
	tied = {}
	for _, name in ipairs(names) do
		if s.rolls[name] == best then tied[#tied + 1] = name end
	end
	if #tied == 1 then return tied[1] end
	if #tied > 1 then
		s.phase, s.tie, s.waiting = "tie", { kind = kind, names = tied }, Set(tied)
		s.tieRolls = s.rolls
		s.rolls = {}
	end
end

local Step

-- Continues an all-out round: knock out the highest, then (for an even count) the lowest.
Step = function(s)
	local pool = s.pool
	if not pool.high then
		local names = {}
		for _, name in ipairs(pool.names) do
			if s.alive[name] then names[#names + 1] = name end
		end
		local pick = #names > 0 and Pick(s, names, "high")
		if pick == nil and s.phase == "tie" then return end
		if pick then
			pool.high = pick
			Eliminate(s, pick, "highest")
			s.rolls = s.tieRolls or s.rolls
			s.tieRolls = nil
			for _, name in ipairs(names) do s.rolls[name] = pool.rolls[name] end
		else
			pool.high = false
		end
	end
	if pool.even and pool.low == nil then
		local names = {}
		for _, name in ipairs(pool.names) do
			if s.alive[name] then names[#names + 1] = name end
		end
		for _, name in ipairs(names) do s.rolls[name] = pool.rolls[name] end
		local pick = #names > 0 and Pick(s, names, "low")
		if pick == nil and s.phase == "tie" then return end
		pool.low = pick or false
		if pick then Eliminate(s, pick, "lowest") end
	end
	s.round = s.round + 1
	Begin(s)
end

-- A round's rolls are all in (or the stragglers folded).
local function Resolve(s)
	local names = {}
	for _, name in ipairs(s.order) do
		if s.alive[name] and s.rolls[name] then names[#names + 1] = name end
	end
	if #names <= 2 then return Begin(s) end
	local rolls = {}
	for _, name in ipairs(names) do rolls[name] = s.rolls[name] end
	s.pool = { names = names, rolls = rolls, even = #names % 2 == 0 }
	Step(s)
end

-- A tie-break among the tied players is complete.
local function ResolveTie(s)
	local tie = s.tie
	local names = {}
	for _, name in ipairs(tie.names) do
		if s.alive[name] and s.rolls[name] then names[#names + 1] = name end
	end
	local pool = s.pool
	if #names == 0 then
		-- Everyone tied folded; they're already out, so this extreme is settled.
		pool[tie.kind] = false
		s.rolls, s.tieRolls, s.tie = {}, nil, nil
		s.phase = "round"
		return Step(s)
	end
	local pick = Pick(s, names, tie.kind)
	if pick == nil then return end  -- tied again, another tie-break started
	pool[tie.kind] = pick
	Eliminate(s, pick, tie.kind == "high" and "highest" or "lowest")
	s.rolls, s.tieRolls, s.tie = pool.rolls, nil, nil
	s.phase = "round"
	Step(s)
end

function Deathroll.New(players, start)
	local s = {
		start = start or Deathroll.sides, order = {}, alive = {}, out = {}, outOrder = {},
		round = 1, rolls = {}, waiting = {}, over = false, phase = "round",
	}
	for i, name in ipairs(players) do
		s.order[i] = name
		s.alive[name] = true
	end
	if #players >= 3 then s.duelStart = math.min(Deathroll.finalStart, s.start) end
	Begin(s)
	return s
end

-- Who still owes a roll right now.
function Deathroll.Waiting(s)
	local list = {}
	for _, name in ipairs(s.order) do
		if s.waiting[name] then list[#list + 1] = name end
	end
	return list
end

-- The range this player must /roll: (1, max).
function Deathroll.Range(s, name)
	if not s.waiting[name] then return end
	if s.phase == "duel" then return 1, s.duel.max end
	return 1, s.start
end

function Deathroll.Roll(s, name, value, max)
	if s.over or not s.waiting[name] then return false end
	local _, limit = Deathroll.Range(s, name)
	if type(value) ~= "number" or value < 1 or value > limit or (max and max ~= limit) then return false end
	s.last = { name = name, value = value }

	if s.phase == "duel" then
		local duel = s.duel
		if value == 1 then
			Eliminate(s, name, "rolled 1")
			return Finish(s, duel.other == name and duel.roller or duel.other) or true
		end
		duel.max = value
		duel.roller, duel.other = duel.other, duel.roller
		s.waiting = { [duel.roller] = true }
		return true
	end

	s.rolls[name] = value
	s.waiting[name] = nil
	if next(s.waiting) == nil then
		if s.phase == "tie" then ResolveTie(s) else Resolve(s) end
	end
	return true
end

-- Several players ran out of time at once (or left the fire): all out together, so if
-- everyone still in folds there's no winner, rather than the last one being handed it.
function Deathroll.FoldMany(s, list)
	if s.over then return false end
	local any = false
	for _, name in ipairs(list) do
		if s.alive[name] then
			Eliminate(s, name, "folded")
			s.waiting[name] = nil
			any = true
		end
	end
	if not any then return false end
	local alive = Deathroll.Alive(s)
	if s.phase == "duel" then
		Finish(s, alive[1])
	elseif #alive <= 1 and s.phase == "round" then
		Finish(s, alive[1])
	elseif next(s.waiting) == nil then
		if s.phase == "tie" then ResolveTie(s) else Resolve(s) end
	end
	return true
end

function Deathroll.Fold(s, name)
	return Deathroll.FoldMany(s, { name })
end
