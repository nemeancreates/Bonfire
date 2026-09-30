local _, ns = ...
local Bonfire = ns.Bonfire

-- Beta check kit: each command answers one open question from docs/BETA-NOTES.md.

-- The passive log: a quiet record, kept between sessions, of which Bonfire users we heard and by
-- which path (channel, say, party, whisper), plus the moments that matter for playing together
-- (join requests, invites, errors). A few minutes online at the same time as another player, even
-- just questing, answers the open questions without a test script. /bf report (or Report on the
-- settings page) prints it. Always on; it stays on this computer. (What travels between players
-- is the Honest Broker's host reputation, in Broker.lua.)
local Log = { EVENTS = 80, PEERS = 40 }
ns.Log = Log

function Log:Data()
	local g = Bonfire.db and Bonfire.db.global
	if not g then return end
	g.diag = g.diag or { peers = {}, events = {} }
	return g.diag
end

function Log:Note(fmt, ...)
	local d = self:Data()
	if not d then return end
	table.insert(d.events, 1, { GetServerTime(), select("#", ...) > 0 and fmt:format(...) or fmt })
	while #d.events > self.EVENTS do table.remove(d.events) end
end

-- A message arrived from sender over path. The first time a player is heard on a path is noted.
function Log:Heard(sender, path, kind)
	local d = self:Data()
	if not d then return end
	local p = d.peers[sender]
	if not p then
		p = { first = GetServerTime(), paths = {} }
		d.peers[sender] = p
		-- Keep it small: forget the player heard longest ago.
		local count, oldest, oldestAt = 0, nil, math.huge
		for name, q in pairs(d.peers) do
			count = count + 1
			if (q.last or 0) < oldestAt then oldest, oldestAt = name, q.last or 0 end
		end
		if count > self.PEERS and oldest then d.peers[oldest] = nil end
	end
	p.last = GetServerTime()
	p.paths[path] = (p.paths[path] or 0) + 1
	if p.paths[path] == 1 then self:Note("first heard %s via %s (%s)", ns.Short(sender), path, tostring(kind)) end
end

local function Ago(at)
	local s = GetServerTime() - at
	if s < 90 then return s .. "s" end
	if s < 5400 then return math.floor(s / 60 + 0.5) .. "m" end
	if s < 129600 then return math.floor(s / 3600 + 0.5) .. "h" end
	return math.floor(s / 86400 + 0.5) .. "d"
end

function Log:Report()
	local d = self:Data()
	if not d then return end
	Bonfire:Printf("Bonfire %s report: %s, %s, channel %s, group %s", C_AddOns.GetAddOnMetadata("Bonfire", "Version"),
		tostring(GetNormalizedRealmName()), tostring(UnitFactionGroup("player")),
		ns.Comm:ChannelId() and ("/" .. ns.Comm:ChannelId()) or "not joined", ns.Comm:Group() and ns.Comm:Group():lower() or "none")
	local names = {}
	for name in pairs(d.peers) do names[#names + 1] = name end
	table.sort(names, function(a, b) return (d.peers[a].last or 0) > (d.peers[b].last or 0) end)
	if #names == 0 then Bonfire:Print("  No other Bonfire users heard yet.") end
	for i = 1, math.min(#names, 8) do
		local p, parts = d.peers[names[i]], {}
		for _, path in ipairs({ "CHANNEL", "SAY", "PARTY", "RAID", "WHISPER" }) do
			parts[#parts + 1] = ("%s %d"):format(path:lower(), p.paths[path] or 0)
		end
		Bonfire:Printf("  %s (last %s ago): %s", ns.Short(names[i]), Ago(p.last or p.first), table.concat(parts, ", "))
	end
	for i = 1, math.min(#d.events, 12) do
		Bonfire:Printf("  %s ago: %s", Ago(d.events[i][1]), d.events[i][2])
	end
end

ns.AddCommand("report", "[clear] - the passive log: who your addon heard, how, and what happened", function(arg)
	if strtrim(arg or ""):lower() == "clear" then
		Bonfire.db.global.diag = nil
		return Bonfire:Print("Passive log cleared.")
	end
	Log:Report()
end)

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
ns.AddHiddenCommand("sound", "[fileID] - play a sound file, or a ready-check sound with no ID", function(arg)
	local id = tonumber(arg)
	if not id then
		Bonfire:Printf("PlaySound(READY_CHECK): %s", tostring(select(2, pcall(PlaySound, SOUNDKIT.READY_CHECK))))
		return
	end
	local ok, willPlay, handle = pcall(PlaySoundFile, id, "Master")
	Bonfire:Printf("PlaySoundFile(%d): ok=%s willPlay=%s handle=%s", id, tostring(ok), tostring(willPlay), tostring(handle))
end)

ns.AddHiddenCommand("music", "<fileID>|stop - play or stop a music file", function(arg)
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
	-- The channel is per realm and per faction: two players only share it if both of these match.
	Bonfire:Printf("faction: %s   realm: %s   group: %s", tostring(UnitFactionGroup("player")), tostring(GetNormalizedRealmName()),
		ns.Comm:Group() and ns.Comm:Group():lower() or "none")
	Bonfire:Printf("position: map %s  %.1f, %.1f", tostring(mapID), (x or 0) * 100, (y or 0) * 100)
	Bonfire:Printf("me: %s (%s)   last sender seen: %s", ns.Me(),
		ns.Comm.selfSender and "learned from the channel" or "NOT learned yet", tostring(ns.Comm.lastSender))
	local comm, now, peers = ns.Comm, GetTime(), 0
	Bonfire:Printf("comms: sent %d, own echoes %d, from others %d, pieces dropped by the game %d, damaged messages thrown away %d",
		comm.sent, comm.echoes, comm.received, comm.dropped, comm.bad)
	for peer, info in pairs(comm.peers) do
		peers = peers + 1
		Bonfire:Printf("  Bonfire user heard: %s (%ds ago, via %s)", peer, now - info.at, ns.Comm:Paths(info, 300))
	end
	if peers == 0 then Bonfire:Print("  no other Bonfire users heard yet (try /bf ping)") end
	local count = 0
	for host, fire in pairs(ns.Beacon.fires) do
		count = count + 1
		Bonfire:Printf("  fire: %s (%s)", host, fire.stake > 0 and "gold" or "for fun")
	end
	Bonfire:Printf("fires heard: %d", count)
	Bonfire:Printf("your fire: %s", ns.Beacon:Visibility())
	local kit, kitName = ns.FindCampfireKit()
	local buff, yards = ns.CampfireBuff(), ns.Table:PlacedDistance()
	Bonfire:Printf("at a campfire: %s   campfire buff: %s   your fire: %s   campfire kit: %s", ns.AtCampfire() and "yes" or "no",
		buff or "none", yards and ("%d yd away"):format(yards) or "not placed", kit and (kitName .. " in bags") or "none found")
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
		"GetTargetTradeMoney", "GetTime", "InCombatLockdown", "InitiateTrade", "IsInRaid", "IsInGroup", "UnitFactionGroup", "UnitIsGroupLeader", "UnitIsGroupAssistant",
		"C_PartyInfo.InviteUnit", "C_PartyInfo.ConvertToRaid", "C_PartyInfo.LeaveParty", "AcceptGroup", "StaticPopup_Hide",
		"IsShiftKeyDown", "JoinTemporaryChannel", "PlayMusic", "PlaySound", "PlaySoundFile",
		"RandomRoll", "StopMusic", "UnitName", "tContains", "tinsert",
		"C_AddOns.GetAddOnMetadata", "C_Container.GetContainerItemInfo", "C_Container.GetContainerNumSlots",
		"C_Item.GetItemNameByID", "C_Map.GetPlayerMapPosition", "C_Spell.GetSpellDescription", "C_Spell.GetSpellName", "C_Timer.After",
		"C_Timer.NewTimer", "C_UnitAuras.GetAuraDataByIndex", "C_UnitAuras.GetPlayerAuraBySpellID",
		"ERR_TRADE_COMPLETE", "NUM_CHAT_WINDOWS", "RANDOM_ROLL_RESULT", "SOUNDKIT", "UISpecialFrames",
		"MoneyInputFrame_SetCopper", "TradePlayerInputMoneyFrame",
		"StartDuel", "AcceptDuel", "CancelDuel", "DUEL_WINNER_KNOCKOUT", "DUEL_WINNER_RETREAT",
		"FCF_OpenNewWindow", "GetChatWindowInfo", "ChatFrame_AddChannel", "LeaveChannelByName",
		"DoEmote", "SendChatMessage",
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
-- Hosts announce their fires in answer and everyone says hello with where they are, so it also
-- fills the fire list and a host's list of players nearby (the spyglass in the window does this).
-- With a name, it whispers just that player (and they whisper back), which works across layers
-- and tells a channel problem apart from a player who isn't running Bonfire at all.
function ns.Ping(name)
	name = strtrim(name or "")
	if name ~= "" then
		local target = ns.FullName(name)
		ns.Comm:Whisper(target, "Q")
		Bonfire:Printf("Whispered %s (on another realm, add it: Name-Realm). Results in 6 seconds...", target)
	else
		ns.Comm:Broadcast("Q", {}, "ALERT")
		if not ns.Comm:ChannelId() then
			Bonfire:Print("Not connected to the Bonfire channel yet, so only people within earshot can hear this.")
		end
		Bonfire:Print("Asking who's out there, results in 6 seconds...")
	end
	C_Timer.After(6, function()
		local now, n = GetTime(), 0
		local groupOnly = false
		for peer, info in pairs(ns.Comm.peers) do
			if now - info.at < 10 then
				n = n + 1
				local paths = ns.Comm:Paths(info, 10)
				Bonfire:Printf("  %s answered (via %s)", peer, paths)
				if not paths:find("CHANNEL", 1, true) and not paths:find("SAY", 1, true) then groupOnly = true end
			end
		end
		if groupOnly then
			Bonfire:Print("  Only your group or a whisper reached them: the Bonfire channel and /say didn't, so players who aren't grouped wouldn't find each other.")
		end
		if n == 0 then
			Bonfire:Print("  nobody answered. Compare /bf status on both: same faction and realm? Try /bf ping <their name>, or group up and ping again.")
		end
	end)
end

ns.AddCommand("ping", "[name] - find other Bonfire users (with a name: whisper just them)", function(arg) ns.Ping(arg) end)

-- What the game calls your character, so race and class lines can be matched to it.
ns.AddCommand("whoami", "- your race and class as the game reports them", function()
	local race, raceFile = UnitRace("player")
	local class, classFile = UnitClass("player")
	Bonfire:Printf("race: %s (%s)   class: %s (%s)", tostring(race), tostring(raceFile), tostring(class), tostring(classFile))
end)
