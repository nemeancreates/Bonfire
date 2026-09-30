local _, ns = ...

-- A simple record of your games: how many, wins and losses, the gold you won and lost, your
-- current streak and best runs, and the last few results. Kept per character.
-- Pure (no WoW API) so tests/run.lua can load it.
local History = { KEEP = 10, KEEP_SEEN = 40 }
ns.History = History

function History.New()
	return { played = 0, won = 0, lost = 0, gained = 0, spent = 0, streak = 0, bestWin = 0, bestLoss = 0, recent = {} }
end

-- net is copper: the profit for a win, minus the stake for a loss, 0 at a for-fun table.
function History.Add(h, game, won, net, when)
	h.played = h.played + 1
	if won then
		h.won, h.gained = h.won + 1, h.gained + math.max(net, 0)
		h.streak = h.streak > 0 and h.streak + 1 or 1
		h.bestWin = math.max(h.bestWin, h.streak)
	else
		h.lost, h.spent = h.lost + 1, h.spent + math.max(-net, 0)
		h.streak = h.streak < 0 and h.streak - 1 or -1
		h.bestLoss = math.max(h.bestLoss, -h.streak)
	end
	table.insert(h.recent, 1, { game = game, won = won, net = net, at = when })
	while #h.recent > History.KEEP do table.remove(h.recent) end
end

-- Side bets get their own tally (h.bets, made on first use so older saves still load).
-- key names the settled round; a key already seen is ignored, so a repeated table update
-- can't count a round twice. net is copper: what the bet paid minus what you put in.
-- Returns true if it was counted.
function History.AddBet(h, key, label, won, net, when)
	local b = h.bets
	if not b then
		b = { placed = 0, won = 0, lost = 0, gained = 0, spent = 0, seen = {}, recent = {} }
		h.bets = b
	end
	for _, k in ipairs(b.seen) do
		if k == key then return false end
	end
	table.insert(b.seen, 1, key)
	while #b.seen > History.KEEP_SEEN do table.remove(b.seen) end
	b.placed = b.placed + 1
	if won then
		b.won, b.gained = b.won + 1, b.gained + math.max(net, 0)
	else
		b.lost, b.spent = b.lost + 1, b.spent + math.max(-net, 0)
	end
	table.insert(b.recent, 1, { label = label, won = won, net = net, at = when })
	while #b.recent > History.KEEP do table.remove(b.recent) end
	return true
end
