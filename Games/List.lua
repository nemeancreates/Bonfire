local _, ns = ...

-- Every game the table can run, in the order the picker shows them. ready = playable now;
-- the rest show greyed as "soon". A game's rules live in Games\<name>.lua (ns.Games[key]).
ns.GAME_LIST = {
	{ key = "embers", ready = true,
		blurb = "Push your luck. Everyone shares each roll and banks their pot before a 1 wipes it out. Highest total after five rounds wins." },
	{ key = "oddmanout", ready = true,
		blurb = "Pick a number. If anyone else rolls it, you're out. The die shrinks as players drop; last one standing wins." },
	{ key = "deathroll", ready = false, name = "Deathroll",
		blurb = "Everyone rolls and the highest and lowest are knocked out, until two remain for a 1v1 deathroll." },
	{ key = "critters", ready = false, name = "Critter Race",
		blurb = "Six critters race for a pool everyone can bet on." },
	{ key = "duel", ready = false, name = "Duel",
		blurb = "Two players fight inside the fire's ring while the rest bet on the winner." },
}

function ns.GameReady(key)
	for _, entry in ipairs(ns.GAME_LIST) do
		if entry.key == key then return entry.ready end
	end
	return false
end

function ns.GameName(key)
	local game = ns.Games and ns.Games[key]
	if game and game.name then return game.name end
	for _, entry in ipairs(ns.GAME_LIST) do
		if entry.key == key then return entry.name or key end
	end
	return tostring(key)
end
