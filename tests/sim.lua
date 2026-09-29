-- Plays thousands of Odd Man Out games with random picks and rolls and reports how they
-- go, to spot anything wonky. Run with scripts\sim.ps1.
local ns = {}
assert(loadfile("Games/OddManOut.lua"))("Bonfire", ns)
local Odd = ns.Games.oddmanout
math.randomseed(20260929)

local GAMES = 20000

-- pickFn(s, name) -> the number a player picks
local function play(n, pickFn)
	local names = {}
	for i = 1, n do names[i] = "P" .. i end
	local s = Odd.New(names)
	local info = { repicks = 0 }
	local guard = 0
	while not s.over do
		guard = guard + 1
		if guard > 50000 then return nil end
		if s.phase == "pick" then
			if guard > 1 then info.repicks = info.repicks + 1 end
			for _, name in ipairs(Odd.Waiting(s)) do Odd.Pick(s, name, pickFn(s, name)) end
		else
			for _, name in ipairs(Odd.Waiting(s)) do Odd.Roll(s, name, math.random(1, s.range)) end
			if not info.first and s.last then info.first = #s.last.knocked end
		end
	end
	return s, info
end

local function percentile(list, p)
	table.sort(list)
	return list[math.max(1, math.floor(#list * p))]
end

local function report(label, n, pickFn)
	local rounds, wipe, repick, first, stuck = {}, 0, 0, 0, 0
	local wins, noWinner = {}, 0
	for i = 1, n do wins[i] = 0 end
	for _ = 1, GAMES do
		local s, info = play(n, pickFn)
		if not s then
			stuck = stuck + 1
		else
			rounds[#rounds + 1] = s.round - 1
			wipe = wipe + s.wipeouts
			if info.repicks > 0 then repick = repick + 1 end
			first = first + (info.first or 0)
			if s.winner then wins[tonumber(s.winner:sub(2))] = wins[tonumber(s.winner:sub(2))] + 1 else noWinner = noWinner + 1 end
		end
	end
	local total, lo, hi = 0, math.huge, 0
	for _, r in ipairs(rounds) do total = total + r end
	for i = 1, n do lo, hi = math.min(lo, wins[i]), math.max(hi, wins[i]) end
	print(("%-22s n=%-2d rounds avg %5.1f  median %3d  p90 %3d  max %4d | wipeouts/game %.2f | repick in %3.0f%% | 1st round knocks %.1f | best/worst seat wins %.1f%%/%.1f%% | stuck %d | no winner %d")
		:format(label, n, total / #rounds, percentile(rounds, 0.5), percentile(rounds, 0.9), rounds[#rounds],
			wipe / GAMES, 100 * repick / GAMES, first / GAMES, 100 * hi / GAMES, 100 * lo / GAMES, stuck, noWinner))
end

local function uniform(s) return math.random(1, s.range) end

print(("%d games each, everyone picks at random:"):format(GAMES))
for n = 2, 10 do report("random picks", n, uniform) end

print("\nEveryone picks the same number (worst case):")
for _, n in ipairs({ 2, 4, 6, 10 }) do report("all pick 1", n, function() return 1 end) end

print("\nEveryone picks 7, then whatever they like when the die shrinks:")
for _, n in ipairs({ 6, 10 }) do report("pick 7", n, function(s) return math.min(7, s.range) end) end
