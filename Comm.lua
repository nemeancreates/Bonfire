local _, ns = ...
local Bonfire = ns.Bonfire

-- Beacons and table state go out on one hidden custom channel so everyone running
-- Bonfire (same faction, same layer) hears them. Players -> host traffic is whispered.
local Comm = { PREFIX = "Bonfire1", CHANNEL = "BonfireCamp" }
ns.Comm = Comm

local handlers = {}

-- Discovery messages also go out on SAY, which needs no channel: everyone within earshot
-- running Bonfire hears them even if the shared channel isn't connecting us.
local DISCOVERY = { H = true, Q = true, B = true, X = true, HI = true }

-- Diagnostics for /bf status and /bf ping: what we've sent and heard, and from whom. dropped
-- counts pieces of our messages the game refused to send; bad counts messages we threw away.
Comm.sent, Comm.echoes, Comm.received, Comm.peers, Comm.seen = 0, 0, 0, {}, {}
Comm.dropped, Comm.bad = 0, 0

function Comm.On(kind, fn)
	handlers[kind] = handlers[kind] or {}
	table.insert(handlers[kind], fn)
end

-- Every message carries a checksum of its text. A long message goes out in pieces, and when a
-- channel is busy the game can drop one; what's left can still decode into nonsense (a table
-- state with names and gold in the wrong places). A message that doesn't match its checksum
-- is thrown away instead.
function Comm.Checksum(text)
	local h = 0
	for i = 1, #text do h = (h * 31 + text:byte(i)) % 2147483647 end
	return h
end

function Comm.Seal(text)
	return ("#%x|%s"):format(Comm.Checksum(text), text)
end

-- The text inside a sealed message, or nil if it doesn't match its checksum. Unsealed text
-- (an older Bonfire, before 0.6.2) is refused too: it can't be checked.
function Comm.Unseal(payload)
	if type(payload) ~= "string" or payload:sub(1, 1) ~= "#" then return end
	local bar = payload:find("|", 2, true)
	if not bar then return end
	local body = payload:sub(bar + 1)
	if tonumber(payload:sub(2, bar - 1), 16) ~= Comm.Checksum(body) then return end
	return body
end

function Comm:Enable()
	-- Tags every message so a client can drop its own, whatever its sender name looks like.
	self.id = ("%s:%d:%x"):format(UnitGUID("player") or "?", GetServerTime(), math.random(0, 0xfffffff))
	Bonfire:RegisterComm(self.PREFIX, function(_, payload, distribution, sender)
		self:Receive(payload, distribution, sender)
	end)
	-- Anyone asking who's out there gets a hello back, so newcomers see every other user
	-- whether or not they're hosting.
	-- A question whispered to us (/bf ping <name>) is answered by whisper, so it tests that path alone.
	self.On("Q", function(_, sender, distribution)
		C_Timer.After(math.random() * 4, function()
			if distribution == "WHISPER" then return self:Whisper(sender, "H") end
			self:Broadcast("H", {}, "BULK")
		end)
	end)
	-- A message can arrive twice (channel and SAY); the copies land within moments of each other.
	Bonfire:ScheduleRepeatingTimer(function() self.seen = {} end, 60)
	-- Joining right at login can grab channel /1 or /2 ahead of General and Trade.
	C_Timer.After(10, function() self:JoinChannel() end)
	-- Our own message echoes back on the channel; the sender on that echo is our name as others see it.
	Bonfire:ScheduleRepeatingTimer(function()
		if not self.selfSender and self:ChannelId() then self:Broadcast("H", {}, "BULK") end
	end, 5)
end

function Comm:JoinChannel()
	if self:ChannelId() then return end
	JoinTemporaryChannel(self.CHANNEL)
	C_Timer.After(3, function()
		if ns.Log then ns.Log:Note(self:ChannelId() and ("joined the Bonfire channel as /" .. self:ChannelId()) or "couldn't join the Bonfire channel") end
	end)
	-- Players never type here; keep it out of the chat windows.
	C_Timer.After(1, function()
		if not ChatFrame_RemoveChannel then return end
		for i = 1, NUM_CHAT_WINDOWS do
			local frame = _G["ChatFrame" .. i]
			if frame then pcall(ChatFrame_RemoveChannel, frame, self.CHANNEL) end
		end
	end)
end

function Comm:ChannelId()
	local id = GetChannelName(self.CHANNEL)
	return id and id > 0 and id or nil
end

-- Your party or raid, if you're in one (not a queued instance group).
function Comm:Group()
	local home = LE_PARTY_CATEGORY_HOME
	if IsInRaid(home) then return "RAID" end
	if IsInGroup(home) then return "PARTY" end
end

-- Everything goes on the realm channel. Discovery also goes out on SAY, which needs no channel.
-- In a party or raid it goes to the group as well, so friends playing together hear each other
-- even when the channel doesn't join them (it's per realm and per faction). Copies are dropped
-- on arrival. sent(done, total, ok) is called as each piece goes out (see SendLatest).
function Comm:Broadcast(kind, data, prio, sent)
	local id, group = self:ChannelId(), self:Group()
	if not id and not group and not DISCOVERY[kind] then return false end
	self.seq = (self.seq or 0) + 1
	data.k, data.i, data.n = kind, self.id, self.seq
	local text = Comm.Seal(Bonfire:Serialize(data))
	self.sent = self.sent + 1
	local function track(_, done, total, ok) sent(done, total, ok) end
	if id then
		Bonfire:SendCommMessage(self.PREFIX, text, "CHANNEL", tostring(id), prio or "NORMAL", sent and track)
	end
	if group then
		-- Tracked here only when there's no channel send to track.
		pcall(Bonfire.SendCommMessage, Bonfire, self.PREFIX, text, group, nil, prio or "NORMAL", (sent and not id) and track or nil)
	end
	if DISCOVERY[kind] then
		pcall(Bonfire.SendCommMessage, Bonfire, self.PREFIX, text, "SAY", nil, "BULK")
	end
	return id ~= nil or group ~= nil
end

-- For a message that replaces whatever was sent before it (the table state): only the newest
-- is worth sending. One goes out at a time. The game limits how fast addons can send, so a
-- state can take a moment to leave; anything made meanwhile just marks that a newer one is
-- waiting, and the newest follows as soon as the last piece is out. If a piece was dropped on
-- the way, the newest state goes again a second later. make() builds the message when it's
-- sent, or returns nil when there's nothing to send; dropped() is told when a piece was lost.
Comm.latest = {}
function Comm:SendLatest(kind, make, prio, dropped)
	local slot = self.latest[kind]
	if not slot then
		slot = {}
		self.latest[kind] = slot
	end
	slot.make, slot.prio, slot.dropped = make, prio, dropped
	-- Still sending the last one (a stuck send gives up after 20 s).
	if slot.busy and GetTime() - slot.busy < 20 then
		slot.waiting = true
		return
	end
	local data = make()
	slot.busy, slot.waiting, slot.failed = nil, false, false
	if not data then return end
	slot.busy = GetTime()
	local ok = self:Broadcast(kind, data, prio, function(done, total, sent)
		if sent == false then
			if not slot.failed and slot.dropped then slot.dropped() end
			slot.failed = true
			self.dropped = self.dropped + 1
			if ns.Log then ns.Log:Note("the game dropped part of a %s message; resending", kind) end
		end
		if done >= total then self:LatestSent(kind, slot) end
	end)
	if not ok then slot.busy = nil end
end

-- After a lost piece the retry waits 1 s, then 2, 4 and 8 while the channel stays busy.
function Comm:LatestSent(kind, slot)
	slot.busy = nil
	if not slot.failed then slot.retry = nil end
	if slot.waiting then return self:SendLatest(kind, slot.make, slot.prio, slot.dropped) end
	if slot.failed then
		slot.retry = math.min((slot.retry or 0.5) * 2, 8)
		C_Timer.After(slot.retry, function()
			if not slot.busy then self:SendLatest(kind, slot.make, slot.prio, slot.dropped) end
		end)
	end
end

-- The paths a player was heard on within the last `within` seconds, e.g. "PARTY, SAY".
function Comm:Paths(peer, within)
	local list = {}
	for path, at in pairs(peer.paths or {}) do
		if GetTime() - at <= within then list[#list + 1] = path end
	end
	table.sort(list)
	return #list > 0 and table.concat(list, ", ") or tostring(peer.via)
end

function Comm:Whisper(target, kind, data)
	data = data or {}
	data.k, data.i = kind, self.id
	self.sent = self.sent + 1
	Bonfire:SendCommMessage(self.PREFIX, Comm.Seal(Bonfire:Serialize(data)), "WHISPER", ns.SendName(target), "ALERT")
end

function Comm:Receive(payload, distribution, sender)
	local text = Comm.Unseal(payload)
	local ok, data
	if text then ok, data = Bonfire:Deserialize(text) end
	-- Every message says what it is and which client sent it; anything else is damaged.
	if not ok or type(data) ~= "table" or type(data.k) ~= "string" or type(data.i) ~= "string" then
		self.bad = self.bad + 1
		if ns.Log then ns.Log:Note("threw away a damaged message from %s via %s", tostring(sender), tostring(distribution)) end
		return
	end
	if data.i == self.id then
		if distribution == "CHANNEL" then self.selfSender = sender end
		self.echoes = self.echoes + 1
		return
	end
	sender = ns.FullName(sender)
	-- Every path we've heard this player on (channel, SAY, party, whisper), noted before the
	-- duplicate check so /bf ping can say which ones actually reach.
	local peer = self.peers[sender] or { paths = {} }
	self.peers[sender] = peer
	peer.at, peer.via, peer.paths[distribution] = GetTime(), distribution, GetTime()
	if ns.Log then ns.Log:Heard(sender, distribution, data.k) end
	if data.n then
		local key = data.i .. ":" .. data.n
		if self.seen[key] then return end
		self.seen[key] = true
	end
	self.lastSender = sender
	self.received = self.received + 1
	-- One handler tripping over an odd message mustn't stop the others hearing it.
	for _, fn in ipairs(handlers[data.k] or {}) do
		local fine, err = pcall(fn, data, sender, distribution)
		if not fine then
			if ns.Log then ns.Log:Note("error handling %s from %s: %s", data.k, ns.Short(sender), tostring(err):sub(1, 120)) end
			geterrorhandler()(err)
		end
	end
end
