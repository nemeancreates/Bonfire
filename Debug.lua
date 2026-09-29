local _, ns = ...
local Bonfire = ns.Bonfire

-- Beta check kit: each command answers one open question from docs/BETA-NOTES.md.

-- What a buff does, from its own description text ("Increases Strength by 5").
local function Describe(aura)
	local ok, text = pcall(C_Spell.GetSpellDescription, aura.spellId)
	text = ok and type(text) == "string" and text:gsub("%s+", " ") or ""
	if #text > 110 then text = text:sub(1, 107) .. "..." end
	return text ~= "" and (" - " .. text) or ""
end

-- Which buff marks "near a campfire"? Stand at one (out of combat) and list buffs,
-- or turn on watch and walk up to a fire.
ns.AddCommand("auras", "- list your buffs and what they do (stand at a campfire)", function()
	local i = 1
	while true do
		local aura = C_UnitAuras.GetAuraDataByIndex("player", i, "HELPFUL")
		if not aura then break end
		Bonfire:Printf("%s%s", tostring(aura.name), Describe(aura))
		i = i + 1
	end
	if i == 1 then Bonfire:Print("no buffs") end
end)

local watcher
local seen = {}  -- auraInstanceID -> name, so removals print a name
ns.AddCommand("watch", "- toggle logging buffs you gain and lose (walk up to a fire)", function()
	if not watcher then
		watcher = CreateFrame("Frame")
		watcher:SetScript("OnEvent", function(_, _, _, info)
			if not info or info.isFullUpdate then return end
			for _, aura in ipairs(info.addedAuras or {}) do
				if aura.isHelpful then
					seen[aura.auraInstanceID] = aura.name
					Bonfire:Printf("|cff66ff66+|r %s%s", tostring(aura.name), Describe(aura))
				end
			end
			for _, id in ipairs(info.removedAuraInstanceIDs or {}) do
				if seen[id] then Bonfire:Printf("|cffff6666-|r %s", tostring(seen[id])) end
				seen[id] = nil
			end
		end)
	end
	if watcher:IsEventRegistered("UNIT_AURA") then
		watcher:UnregisterEvent("UNIT_AURA")
		Bonfire:Print("aura watch off")
	else
		watcher:RegisterUnitEvent("UNIT_AURA", "player")
		Bonfire:Print("aura watch on")
	end
end)

-- Are PlaySoundFile / PlayMusic allowed? (Jukebox and band phases depend on it.)
ns.AddCommand("sound", "[fileID] - play a sound file, or a ready-check sound with no ID", function(arg)
	local id = tonumber(arg)
	if not id then
		Bonfire:Printf("PlaySound(READY_CHECK): %s", tostring(select(2, pcall(PlaySound, SOUNDKIT.READY_CHECK))))
		return
	end
	local ok, willPlay, handle = pcall(PlaySoundFile, id, "Master")
	Bonfire:Printf("PlaySoundFile(%d): ok=%s willPlay=%s handle=%s", id, tostring(ok), tostring(willPlay), tostring(handle))
end)

ns.AddCommand("music", "<fileID>|stop - play or stop a music file", function(arg)
	if arg == "stop" then
		StopMusic()
		return Bonfire:Print("music stopped")
	end
	local id = tonumber(arg)
	if not id then return Bonfire:Print("usage: /bf music <fileID> | stop") end
	local ok, err = pcall(PlayMusic, id)
	Bonfire:Printf("PlayMusic(%d): ok=%s %s", id, tostring(ok), ok and "" or tostring(err))
end)

-- Does the discovery channel work, and do our rolls parse? Prints both.
ns.AddCommand("status", "- channel, position and roll-parser check", function()
	local x, y, mapID = LibStub("HereBeDragons-2.0"):GetPlayerZonePosition()
	Bonfire:Printf("channel %s: %s", ns.Comm.CHANNEL, ns.Comm:ChannelId() and ("joined as /" .. ns.Comm:ChannelId()) or "not joined")
	Bonfire:Printf("position: map %s  %.1f, %.1f", tostring(mapID), (x or 0) * 100, (y or 0) * 100)
	Bonfire:Printf("me: %s (%s)   last sender seen: %s", ns.Me(),
		ns.Comm.selfSender and "learned from the channel" or "NOT learned yet", tostring(ns.Comm.lastSender))
	local comm, now, peers = ns.Comm, GetTime(), 0
	Bonfire:Printf("comms: sent %d, own echoes %d, from others %d", comm.sent, comm.echoes, comm.received)
	for peer, info in pairs(comm.peers) do
		peers = peers + 1
		Bonfire:Printf("  Bonfire user heard: %s (%ds ago, via %s)", peer, now - info.at, tostring(info.via))
	end
	if peers == 0 then Bonfire:Print("  no other Bonfire users heard yet (try /bf ping)") end
	local count = 0
	for host, fire in pairs(ns.Beacon.fires) do
		count = count + 1
		Bonfire:Printf("  fire: %s (%s)", host, fire.stake > 0 and "gold" or "for fun")
	end
	Bonfire:Printf("fires heard: %d", count)
	local kit, kitName = ns.FindCampfireKit()
	Bonfire:Printf("at a campfire: %s   campfire kit: %s", ns.AtCampfire() and "yes" or "no", kit and (kitName .. " in bags") or "none found")
	local d = ns.Table:DistanceToFire()
	if d then Bonfire:Printf("distance to your table's fire: %d yd (fold past %d)", d, ns.Table.FOLD_RANGE) end
	local who, roll = ns.ParseRoll(RANDOM_ROLL_RESULT:format(UnitName("player"), 4, 1, 6))
	Bonfire:Printf("roll parser: %s", who and ("ok (" .. who .. " " .. roll .. ")") or "FAILED")
end)

-- Lists any game API Bonfire calls that this client doesn't have, so a missing one
-- shows up here instead of as a Lua error in the middle of a game.
local function Resolve(path)
	local value = _G
	for key in path:gmatch("[^.]+") do
		value = type(value) == "table" and value[key] or nil
	end
	return value
end

ns.AddCommand("api", "- check the game APIs Bonfire uses exist in this client", function()
	local needed = {
		"Ambiguate", "ChatFrame_RemoveChannel", "CreateFrame", "GetChannelName", "GetMoney",
		"GetNormalizedRealmName", "GetNumGroupMembers", "GetPlayerTradeMoney", "GetServerTime",
		"GetTargetTradeMoney", "GetTime", "InCombatLockdown", "InitiateTrade", "IsInRaid",
		"IsShiftKeyDown", "JoinTemporaryChannel", "PlayMusic", "PlaySound", "PlaySoundFile",
		"RandomRoll", "StopMusic", "UnitName", "tContains", "tinsert",
		"C_AddOns.GetAddOnMetadata", "C_Container.GetContainerItemInfo", "C_Container.GetContainerNumSlots",
		"C_Item.GetItemNameByID", "C_Map.GetPlayerMapPosition", "C_Spell.GetSpellDescription", "C_Spell.GetSpellName", "C_Timer.After",
		"C_Timer.NewTimer", "C_UnitAuras.GetAuraDataByIndex", "C_UnitAuras.GetPlayerAuraBySpellID",
		"ERR_TRADE_COMPLETE", "NUM_CHAT_WINDOWS", "RANDOM_ROLL_RESULT", "SOUNDKIT", "UISpecialFrames",
		"MoneyInputFrame_SetCopper", "TradePlayerInputMoneyFrame",
		"StartDuel", "AcceptDuel", "CancelDuel", "DUEL_WINNER_KNOCKOUT", "DUEL_WINNER_RETREAT",
		"FCF_OpenNewWindow", "GetChatWindowInfo", "ChatFrame_AddChannel", "LeaveChannelByName",
	}
	local missing = {}
	for _, path in ipairs(needed) do
		if Resolve(path) == nil then missing[#missing + 1] = path end
	end
	if #missing == 0 then
		Bonfire:Printf("all %d APIs present", #needed)
	else
		Bonfire:Printf("|cffff6666missing:|r %s", table.concat(missing, ", "))
	end
end)

-- Search this client's function names, to find a missing or renamed API.
ns.AddCommand("find", "<text> - search the game's API names (e.g. trademoney)", function(text)
	text = strtrim(text or ""):lower()
	if text == "" then return Bonfire:Print("usage: /bf find <text>, e.g. /bf find trademoney") end
	local hits = {}
	for name, value in pairs(_G) do
		if type(name) == "string" then
			if type(value) == "function" and name:lower():find(text, 1, true) then hits[#hits + 1] = name end
			if name:sub(1, 2) == "C_" and type(value) == "table" then
				for key, member in pairs(value) do
					if type(key) == "string" and type(member) == "function" and (name .. "." .. key):lower():find(text, 1, true) then
						hits[#hits + 1] = name .. "." .. key
					end
				end
			end
		end
	end
	table.sort(hits)
	if #hits == 0 then return Bonfire:Printf("nothing matches '%s'", text) end
	Bonfire:Printf("%d match(es):", #hits)
	for i = 1, math.min(#hits, 25) do print("  " .. hits[i]) end
	if #hits > 25 then print(("  ...and %d more, try a longer search"):format(#hits - 25)) end
end)

-- Ask everyone running Bonfire to say hello, then list who answered. Works without any table.
ns.AddCommand("ping", "- find other Bonfire users on the channel", function()
	ns.Comm:Broadcast("Q", {}, "ALERT")
	if not ns.Comm:ChannelId() then
		Bonfire:Print("Not connected to the Bonfire channel yet, so only people within earshot can hear this.")
	end
	Bonfire:Print("Asking who's out there, results in 6 seconds...")
	C_Timer.After(6, function()
		local now, n = GetTime(), 0
		for peer, info in pairs(ns.Comm.peers) do
			if now - info.at < 10 then
				n = n + 1
				Bonfire:Printf("  %s answered (via %s)", peer, tostring(info.via))
			end
		end
		if n == 0 then Bonfire:Print("  nobody answered. Same faction and layer? Do they have Bonfire and a joined channel (/bf status)?") end
	end)
end)
