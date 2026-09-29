local _, ns = ...

-- All money is integer copper. Stakes are built up from amounts of one coin type at a time.
local COIN_ICON = {
	g = "Interface\\MoneyFrame\\UI-GoldIcon",
	s = "Interface\\MoneyFrame\\UI-SilverIcon",
	c = "Interface\\MoneyFrame\\UI-CopperIcon",
}

ns.COIN_UNITS = {
	{ key = "g", name = "gold", copper = 10000, color = "ffd700", icon = COIN_ICON.g },
	{ key = "s", name = "silver", copper = 100, color = "c7c7cf", icon = COIN_ICON.s },
	{ key = "c", name = "copper", copper = 1, color = "eda55f", icon = COIN_ICON.c },
}
ns.STAKE_STEP, ns.STAKE_STEP_BIG, ns.STAKE_MAX = 5, 10, 1000  -- per-click steps, and the most of one coin type to add at once
ns.BET_CAP = 1000 * 10000                                      -- the most a bet can total: 1000 gold

local UNIT = { g = 10000, s = 100, c = 1 }

-- Copper -> "5[gold] 20[silver] 3[copper]" with the standard coin textures.
function ns.CoinString(copper)
	copper = math.floor(copper or 0)
	local parts = {}
	for _, key in ipairs({ "g", "s", "c" }) do
		local amount = math.floor(copper / UNIT[key])
		copper = copper - amount * UNIT[key]
		if amount > 0 then parts[#parts + 1] = ("%d|T%s:0:0:2:0|t"):format(amount, COIN_ICON[key]) end
	end
	if #parts == 0 then return ("0|T%s:0:0:2:0|t"):format(COIN_ICON.c) end
	return table.concat(parts, " ")
end

-- "5g20s", "35s", "1g 5c" or a bare copper number -> copper, nil if malformed.
function ns.ParseMoney(text)
	if type(text) ~= "string" then return end
	text = text:lower():gsub("%s", "")
	if text == "" then return end
	if text:match("^%d+$") then return tonumber(text) end
	if (text:gsub("%d+[gsc]", "")) ~= "" then return end
	local total = 0
	for num, unit in text:gmatch("(%d+)([gsc])") do
		total = total + tonumber(num) * UNIT[unit]
	end
	return total
end
