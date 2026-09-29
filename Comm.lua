local _, ns = ...
local Bonfire = ns.Bonfire

-- Beacons and table state go out on one hidden custom channel so everyone running
-- Bonfire (same faction, same layer) hears them. Players -> host traffic is whispered.
local Comm = { PREFIX = "Bonfire1", CHANNEL = "BonfireCamp" }
ns.Comm = Comm

local handlers = {}

-- Discovery messages also go out on SAY, which needs no channel: everyone within earshot
-- running Bonfire hears them even if the shared channel isn't connecting us.
local DISCOVERY = { H = true, Q = true, B = true, X = true }

-- Diagnostics for /bf status and /bf ping: what we've sent and heard, and from whom.
Comm.sent, Comm.echoes, Comm.received, Comm.peers, Comm.seen = 0, 0, 0, {}, {}

function Comm.On(kind, fn)
	handlers[kind] = handlers[kind] or {}
	table.insert(handlers[kind], fn)
end

function Comm:Enable()
	-- Tags every message so a client can drop its own, whatever its sender name looks like.
	self.id = ("%s:%d:%x"):format(UnitGUID("player") or "?", GetServerTime(), math.random(0, 0xfffffff))
	Bonfire:RegisterComm(self.PREFIX, function(_, payload, distribution, sender)
		self:Receive(payload, distribution, sender)
	end)
	-- Anyone asking who's out there gets a hello back, so newcomers see every other user
	-- whether or not they're hosting.
	self.On("Q", function()
		C_Timer.After(math.random() * 4, function() self:Broadcast("H", {}, "BULK") end)
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

function Comm:Broadcast(kind, data, prio)
	local id = self:ChannelId()
	if not id and not DISCOVERY[kind] then return false end
	self.seq = (self.seq or 0) + 1
	data.k, data.i, data.n = kind, self.id, self.seq
	local text = Bonfire:Serialize(data)
	self.sent = self.sent + 1
	if id then
		Bonfire:SendCommMessage(self.PREFIX, text, "CHANNEL", tostring(id), prio or "NORMAL")
	end
	if DISCOVERY[kind] then
		pcall(Bonfire.SendCommMessage, Bonfire, self.PREFIX, text, "SAY", nil, "BULK")
	end
	return true
end

function Comm:Whisper(target, kind, data)
	data = data or {}
	data.k, data.i = kind, self.id
	self.sent = self.sent + 1
	Bonfire:SendCommMessage(self.PREFIX, Bonfire:Serialize(data), "WHISPER", target, "ALERT")
end

function Comm:Receive(payload, distribution, sender)
	local ok, data = Bonfire:Deserialize(payload)
	if not ok or type(data) ~= "table" then return end
	if data.i == self.id then
		if distribution == "CHANNEL" then self.selfSender = sender end
		self.echoes = self.echoes + 1
		return
	end
	if data.n then
		local key = data.i .. ":" .. data.n
		if self.seen[key] then return end
		self.seen[key] = true
	end
	self.lastSender = sender
	self.received = self.received + 1
	sender = ns.FullName(sender)
	self.peers[sender] = { at = GetTime(), via = distribution }
	for _, fn in ipairs(handlers[data.k] or {}) do
		fn(data, sender, distribution)
	end
end
