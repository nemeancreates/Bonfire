local _, ns = ...

-- Bonfire (key "embers"): push-your-luck with one shared die, so any number of players
-- play at once. The host clicks Roll (a server /roll 1-6); everyone still stoking adds the
-- roll to their round pot. A 1 blows the fire out and every unbanked pot is lost.
-- Bank at any time to keep your pot and sit out the rest of the round.
-- Highest total after the last round takes the pot.
--
-- Pure rules only (no WoW API) so tests/run.lua can load it.
local Embers = { name = "Bonfire", rounds = 5, sides = 6 }
ns.Games = ns.Games or {}
ns.Games.embers = Embers

function Embers.New(players, rounds)
	local s = { round = 1, rounds = rounds or Embers.rounds, order = {}, players = {}, over = false }
	for i, name in ipairs(players) do
		s.order[i] = name
		s.players[name] = { total = 0, pot = 0, stoking = true }
	end
	return s
end

function Embers.AnyStoking(s)
	for _, name in ipairs(s.order) do
		if s.players[name].stoking then return true end
	end
	return false
end

local function NextRound(s)
	s.round = s.round + 1
	if s.round > s.rounds then
		s.round = s.rounds
		s.over = true
	end
	for _, name in ipairs(s.order) do
		local p = s.players[name]
		p.pot = 0
		p.stoking = not s.over and not p.left
	end
end

function Embers.Bank(s, name)
	local p = s.players[name]
	if s.over or not p or not p.stoking then return false end
	p.total = p.total + p.pot
	p.pot = 0
	p.stoking = false
	if not Embers.AnyStoking(s) then NextRound(s) end
	return true
end

-- Leaving forfeits: the player stops scoring and can't win.
function Embers.Leave(s, name)
	local p = s.players[name]
	if not p or p.left then return end
	p.left, p.stoking, p.pot = true, false, 0
	if not s.over and not Embers.AnyStoking(s) then NextRound(s) end
end

-- Applies one shared roll; returns true when it blew the fire out.
function Embers.Roll(s, value)
	if s.over or not Embers.AnyStoking(s) then return end
	local bust = value == 1
	for _, name in ipairs(s.order) do
		local p = s.players[name]
		if p.stoking then p.pot = bust and 0 or p.pot + value end
	end
	if bust then NextRound(s) end
	return bust
end

function Embers.Winners(s)
	local best, winners = -1, {}
	for _, name in ipairs(s.order) do
		local p = s.players[name]
		if not p.left then
			if p.total > best then best, winners = p.total, { name }
			elseif p.total == best then winners[#winners + 1] = name end
		end
	end
	return winners, best
end
