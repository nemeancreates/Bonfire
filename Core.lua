local ADDON, ns = ...

local Bonfire = LibStub("AceAddon-3.0"):NewAddon(ADDON, "AceConsole-3.0", "AceEvent-3.0", "AceTimer-3.0", "AceComm-3.0", "AceSerializer-3.0")
ns.Bonfire = Bonfire

-- Bonfire's messages go to its own chat tab when there is one, so they don't drown in a busy
-- chat. The tab flashes when something new lands in it.
local consolePrint = Bonfire.Print
function Bonfire:Print(...)
	local frame = ns.replyFrame or (ns.Chat and ns.Chat.frame)
	if not frame then return consolePrint(self, ...) end
	consolePrint(self, frame, ...)
	if FCF_StartAlertFlash and frame ~= SELECTED_CHAT_FRAME then pcall(FCF_StartAlertFlash, frame) end
end

local consolePrintf = Bonfire.Printf
function Bonfire:Printf(...)
	local frame = ns.replyFrame or (ns.Chat and ns.Chat.frame)
	if not frame then return consolePrintf(self, ...) end
	consolePrintf(self, frame, ...)
	if FCF_StartAlertFlash and frame ~= SELECTED_CHAT_FRAME then pcall(FCF_StartAlertFlash, frame) end
end

local defaults = {
	global = {
		-- unit indexes ns.COIN_UNITS; total is the bet being built up, confirmed is what the table plays for
		stake = { forFun = true, amount = 5, unit = 2, total = 0, confirmed = 0 },
		pins = true,
		game = "embers",                            -- the game your next table plays
		chatTab = true,                             -- Bonfire's own chat tab, and table chat
		bet = { amount = 5, unit = 2, total = 0 },  -- the side bet being built
		betCut = 5,                                  -- host cut for new betting cards, percent
		stats = { played = 0, won = 0 },
	},
}

-- AceEvent keeps one handler per event per object, so a second Bonfire:RegisterEvent for the same
-- event silently replaces the first (that's how the table once stopped reading /roll lines).
-- Every file registers through here instead, and each handler for an event gets called.
local eventHandlers = {}
function ns.OnEvent(event, fn)
	local list = eventHandlers[event]
	if not list then
		list = {}
		eventHandlers[event] = list
		Bonfire:RegisterEvent(event, function(...)
			for _, handler in ipairs(list) do
				local ok, err = pcall(handler, ...)
				if not ok then geterrorhandler()(err) end
			end
		end)
	end
	list[#list + 1] = fn
end

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

-- +5g in green or -2s in red, "even" for nothing.
function ns.SignedCoins(copper)
	if not copper or copper == 0 then return "even" end
	return ("%s%s|r"):format(copper > 0 and "|cff66ff66+" or "|cffff6666-", ns.CoinString(math.abs(copper)))
end

-- The game the picker has selected, falling back to Embers if it isn't playable.
function ns.ChosenGame()
	local key = Bonfire.db.global.game
	return ns.GameReady(key) and key or "embers"
end

-- "Welcoming Campfire": the buff you get from resting at a Forever campfire
-- (spell ID from DynamicCam's Forever camping situation; verify with /bf auras).
ns.CAMP_AURA = 1229739

-- The name of the campfire buff on you, or nil: proof a campfire is burning next to you.
-- Matches the Welcoming Campfire buff by ID, and any other buff with "campfire" in its name
-- (a proximity buff such as "Campfire nearby" counts too).
function ns.CampfireBuff()
	local ok, aura = pcall(C_UnitAuras.GetPlayerAuraBySpellID, ns.CAMP_AURA)
	if ok and aura then return aura.name or "Welcoming Campfire" end
	local found
	pcall(function()
		for i = 1, 40 do
			local a = C_UnitAuras.GetAuraDataByIndex("player", i, "HELPFUL")
			if not a then break end
			if type(a.name) == "string" and a.name:lower():find("campfire", 1, true) then
				found = a.name
				break
			end
		end
	end)
	return found
end

function ns.AtCampfire()
	return ns.CampfireBuff() ~= nil or ns.Table:NearOwnFire()
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

-- How many campfire kits are in your bags. Placing a fire uses one up; crafting makes one.
function ns.CountCampfireKits()
	local n = 0
	for bag = 0, (NUM_BAG_SLOTS or 4) + 1 do
		for slot = 1, C_Container.GetContainerNumSlots(bag) do
			local info = C_Container.GetContainerItemInfo(bag, slot)
			local name = info and C_Item.GetItemNameByID(info.itemID)
			if name and name:lower():find("campfire", 1, true) then n = n + (info.stackCount or 1) end
		end
	end
	return n
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

function ns.AddCommand(name, usage, fn, hidden)
	commands[name] = { usage = usage, fn = fn }
	if not hidden then order[#order + 1] = name end  -- hidden commands work but aren't in the help list
end

function ns.AddHiddenCommand(name, usage, fn)
	ns.AddCommand(name, usage, fn, true)
end

function Bonfire:OnSlash(input)
	local cmd, rest = strtrim(input or ""):match("^(%S*)%s*(.-)$")
	cmd = cmd:lower()
	if cmd == "" then return ns.UI:Toggle() end
	-- What you type is answered where you typed it, not in the Bonfire tab.
	ns.replyFrame = SELECTED_CHAT_FRAME or DEFAULT_CHAT_FRAME
	local c = commands[cmd]
	local ok, err
	if not c then
		self:Print(cmd == "help" and "/bf opens the window. Commands:"
			or ("No command called '" .. cmd .. "'. /bf opens the window. Commands:"))
		for _, name in ipairs(order) do self:Print(("  /bf %s %s"):format(name, commands[name].usage)) end
	else
		ok, err = pcall(c.fn, rest)
	end
	ns.replyFrame = nil
	if ok == false then geterrorhandler()(err) end
end

function Bonfire:OnInitialize()
	self.db = LibStub("AceDB-3.0"):New("BonfireDB", defaults, true)
	self:RegisterChatCommand("bonfire", "OnSlash")
	self:RegisterChatCommand("bf", "OnSlash")
	self:RegisterChatCommand("bfhelp", function() self:OnSlash("help") end)
end

function Bonfire:OnEnable()
	ns.Comm:Enable()
	ns.Beacon:Enable()
	ns.Table:Enable()
	ns.Trade:Enable()
	ns.UI:Enable()
	ns.Range:Enable()
	ns.Chat:Enable()
	ns.Quips:Enable()
	ns.Broker:Enable()
	local _, build, _, interface = GetBuildInfo()
	self:Printf("v%s loaded (client %s, interface %d). /bf to open.",
		C_AddOns.GetAddOnMetadata(ADDON, "Version"), build, interface)
end
