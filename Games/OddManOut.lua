local _, ns = ...

-- The Odd Man Out (d20)
--
-- Two to ten players. Everyone secretly picks a number. Each round everyone rolls once,
-- and you're knocked out if any OTHER player rolled your number (your own roll never
-- counts against you). Players can pick the same number. Last one standing wins.
--
-- The die is 1-20 while six or more players are left and 1-10 with five or fewer, so it
-- shrinks as the table thins out. When it shrinks everyone picks again in the new range,
-- otherwise a number over 10 would be unhittable.
--
-- Near misses: a round where nobody goes out widens the net. A roll within 1 of your number
-- counts too, then within 2, and no further (Odd.MaxReach). The numbers wrap around (1 is
-- next to 10) so no pick is safer than another. Reach goes back to 0 as soon as someone is
-- knocked out or the die shrinks. Without this two players on d10 could go many rounds.
--
-- If a round would knock out everyone left, nobody goes, the reach backs off one step, and
-- the round is replayed.
-- Anyone who doesn't pick or roll in time is folded by the host (Odd.Fold): out now.
--
-- Pure rules, no WoW API, so tests/run.lua and tests/sim.lua can load it. The host feeds
-- in the real /roll results and does the timing.
local Odd = { name = "The Odd Man Out", minPlayers = 2, maxPlayers = 10, pickSeconds = 15, rollSeconds = 10 }
ns.Games = ns.Games or {}
ns.Games.oddmanout = Odd

-- Six or more players roll d20; five or fewer roll d10.
function Odd.RangeFor(count)
	return count >= 6 and 20 or 10
end

-- The widest near miss allowed: within 2 on a d10, within 4 on a d20 (about half the die).
function Odd.MaxReach(range)
	return math.floor(range / 5)
end

local function Set(list)
	local set = {}
	for _, name in ipairs(list) do set[name] = true end
	return set
end

function Odd.Alive(s)
	local list = {}
	for _, name in ipairs(s.order) do
		if s.alive[name] then list[#list + 1] = name end
	end
	return list
end

local function Eliminate(s, name, reason)
	if not s.alive[name] then return end
	s.alive[name] = nil
	s.out[name] = { reason = reason, pick = s.picks[name], round = s.round }
	s.outOrder[#s.outOrder + 1] = name
	s.rolls[name], s.waiting[name] = nil, nil
end

local function Finish(s, winner)
	s.phase, s.over, s.winner, s.waiting = "over", true, winner, {}
end

local function BeginPick(s)
	s.phase, s.picks, s.rolls, s.reach = "pick", {}, {}, 0
	s.waiting = Set(Odd.Alive(s))
end

local function BeginRoll(s)
	s.phase, s.rolls = "roll", {}
	s.waiting = Set(Odd.Alive(s))
end

-- After a round: a winner, a fresh pick (the die changed size), or another roll.
local function Advance(s)
	local alive = Odd.Alive(s)
	if #alive <= 1 then return Finish(s, alive[1]) end
	local range = Odd.RangeFor(#alive)
	if range ~= s.range then
		s.range = range
		return BeginPick(s)
	end
	BeginRoll(s)
end

-- A roll hits a pick when it's the same number, or within s.reach of it, wrapping around.
local function Hits(s, roll, pick)
	local d = math.abs(roll - pick)
	return math.min(d, s.range - d) <= s.reach
end

-- Everyone left has rolled: knock out whoever had their number rolled by someone else.
local function Resolve(s)
	local alive = Odd.Alive(s)
	local rolled = {}
	for name, v in pairs(s.rolls) do rolled[name] = v end
	local knocked = {}
	for _, p in ipairs(alive) do
		for _, q in ipairs(alive) do
			if q ~= p and Hits(s, s.rolls[q], s.picks[p]) then
				knocked[#knocked + 1] = p
				break
			end
		end
	end
	local wipeout = #alive > 0 and #knocked == #alive
	s.last = { round = s.round, range = s.range, reach = s.reach, rolls = rolled, knocked = wipeout and {} or knocked, wipeout = wipeout }
	if wipeout then
		s.wipeouts = s.wipeouts + 1
		s.reach = math.max(0, s.reach - 1)  -- the net was too wide: back it off a step and replay
	else
		for _, name in ipairs(knocked) do Eliminate(s, name, "knocked out") end
		if #knocked == 0 then
			s.reach = math.min(s.reach + 1, Odd.MaxReach(s.range))
		else
			s.reach = 0
		end
	end
	s.round = s.round + 1
	Advance(s)
end

function Odd.New(players)
	local s = {
		order = {}, alive = {}, out = {}, outOrder = {}, picks = {}, rolls = {}, waiting = {},
		round = 1, wipeouts = 0, over = false, phase = "pick", reach = 0,
	}
	for i, name in ipairs(players) do
		s.order[i] = name
		s.alive[name] = true
	end
	s.range = Odd.RangeFor(#players)
	if #players <= 1 then
		Finish(s, players[1])
	else
		BeginPick(s)
	end
	return s
end

-- Who still owes a pick or a roll right now.
function Odd.Waiting(s)
	local list = {}
	for _, name in ipairs(s.order) do
		if s.waiting[name] then list[#list + 1] = name end
	end
	return list
end

local function WholeNumberIn(value, max)
	return type(value) == "number" and value % 1 == 0 and value >= 1 and value <= max
end

-- A pick can be changed until the last player has picked.
function Odd.Pick(s, name, value)
	if s.phase ~= "pick" or not s.alive[name] or not WholeNumberIn(value, s.range) then return false end
	s.picks[name] = value
	s.waiting[name] = nil
	if next(s.waiting) == nil then BeginRoll(s) end
	return true
end

-- Picks for someone who ran out of time (rand(lo, hi), so tests can control it).
function Odd.AutoPick(s, name, rand)
	return Odd.Pick(s, name, rand(1, s.range))
end

function Odd.Roll(s, name, value, max)
	if s.phase ~= "roll" or not s.waiting[name] or not WholeNumberIn(value, s.range) then return false end
	if max and max ~= s.range then return false end
	s.rolls[name] = value
	s.waiting[name] = nil
	if next(s.waiting) == nil then Resolve(s) end
	return true
end

-- Ran out of time (or left the fire): out now. Several at once means everyone still owing
-- folds together, so if that's everyone left there's no winner.
function Odd.FoldMany(s, list)
	if s.over then return false end
	local any = false
	for _, name in ipairs(list) do
		if s.alive[name] then
			Eliminate(s, name, "folded")
			any = true
		end
	end
	if not any then return false end
	local alive = Odd.Alive(s)
	if #alive <= 1 then
		Finish(s, alive[1])
		return true
	end
	if s.phase == "pick" then
		local range = Odd.RangeFor(#alive)
		if range ~= s.range then
			s.range = range
			BeginPick(s)
		elseif next(s.waiting) == nil then
			BeginRoll(s)
		end
	elseif s.phase == "roll" and next(s.waiting) == nil then
		Resolve(s)
	end
	return true
end

function Odd.Fold(s, name)
	return Odd.FoldMany(s, { name })
end

-- For the ledger: the winner as a list (empty when nobody won).
function Odd.Winners(s)
	return s.winner and { s.winner } or {}
end
