local ADDON, ns = ...

local Bonfire = LibStub("AceAddon-3.0"):NewAddon(ADDON, "AceConsole-3.0", "AceEvent-3.0", "AceTimer-3.0", "AceComm-3.0", "AceSerializer-3.0")
ns.Bonfire = Bonfire

local defaults = {
	global = {
		-- unit indexes ns.COIN_UNITS; total is the bet being built up, confirmed is what the table plays for
		stake = { forFun = true, amount = 5, unit = 2, total = 0, confirmed = 0 },
		pins = true,
		stats = { played = 0, won = 0 },
	},
}

-- Everything on the wire uses "Name-Realm" so names from chat, comms and rolls compare equal.
function ns.FullName(name)
	if not name then return end
	if name:find("-", 1, true) then return name end
	return name .. "-" .. GetNormalizedRealmName()
end

-- The name everyone else sees us as. Comms carry the full name ("Firstname Surname-Realm")
-- while UnitName gives just "Firstname", so use the name our own channel echo arrived
-- under once we've seen it (Comm learns it a few seconds after login).
function ns.Me()
	return ns.FullName(ns.Comm and ns.Comm.selfSender or UnitName("player"))
end

-- Different APIs give different forms of the same name, so compare on the first word.
function ns.NameKey(name)
	if not name then return end
	return (name:match("^[^%s%-]+") or name):lower()
end

function ns.Short(name)
	return name and Ambiguate(name, "short")
end

function ns.Coins(copper)
	if not copper or copper == 0 then return "for fun" end
	return ns.CoinString(copper)
end

-- "Welcoming Campfire": the buff you get from resting at a Forever campfire
-- (spell ID from DynamicCam's Forever camping situation; verify with /bf auras).
ns.CAMP_AURA = 1229739

function ns.AtCampfire()
	local ok, aura = pcall(C_UnitAuras.GetPlayerAuraBySpellID, ns.CAMP_AURA)
	return ok and aura ~= nil
end

-- The Basic Campfire Kit's exact name isn't confirmed, so match on "campfire".
-- Returns "bag slot", which a secure item button accepts, and the item's name.
function ns.FindCampfireKit()
	for bag = 0, (NUM_BAG_SLOTS or 4) + 1 do
		for slot = 1, C_Container.GetContainerNumSlots(bag) do
			local info = C_Container.GetContainerItemInfo(bag, slot)
			local name = info and C_Item.GetItemNameByID(info.itemID)
			if name and name:lower():find("campfire", 1, true) then return bag .. " " .. slot, name end
		end
	end
end

-- Marks gambling fires wherever seats are shown; for-fun fires get nothing.
ns.COIN_ICON = "Interface\\MoneyFrame\\UI-GoldIcon"
function ns.StakeBadge(copper)
	return (copper or 0) > 0 and ("|T" .. ns.COIN_ICON .. ":12:12|t") or ""
end

-- 0 means a for-fun table.
function ns.StakeCopper()
	local stake = Bonfire.db.global.stake
	if stake.forFun then return 0 end
	return stake.confirmed
end

-- A gold table needs a confirmed bet before it can open.
function ns.BetReady()
	local stake = Bonfire.db.global.stake
	return stake.forFun or stake.confirmed > 0
end

-- Slash commands ---------------------------------------------------------------
local commands, order = {}, {}

function ns.AddCommand(name, usage, fn)
	commands[name] = { usage = usage, fn = fn }
	order[#order + 1] = name
end

function Bonfire:OnSlash(input)
	local cmd, rest = strtrim(input or ""):match("^(%S*)%s*(.-)$")
	cmd = cmd:lower()
	if cmd == "" then return ns.UI:Toggle() end
	local c = commands[cmd]
	if not c then
		self:Print("/bf opens the window. Commands:")
		for _, name in ipairs(order) do print(("  /bf %s %s"):format(name, commands[name].usage)) end
		return
	end
	c.fn(rest)
end

function Bonfire:OnInitialize()
	self.db = LibStub("AceDB-3.0"):New("BonfireDB", defaults, true)
	self:RegisterChatCommand("bonfire", "OnSlash")
	self:RegisterChatCommand("bf", "OnSlash")
end

function Bonfire:OnEnable()
	ns.Comm:Enable()
	ns.Beacon:Enable()
	ns.Table:Enable()
	ns.Trade:Enable()
	ns.UI:Enable()
	ns.Range:Enable()
	local _, build, _, interface = GetBuildInfo()
	self:Printf("v%s loaded (client %s, interface %d). /bf to open.",
		C_AddOns.GetAddOnMetadata(ADDON, "Version"), build, interface)
end
