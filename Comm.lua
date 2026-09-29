local _, ns = ...
local Bonfire = ns.Bonfire

-- Beacons and table state go out on one hidden custom channel so everyone running
-- Bonfire (same faction, same layer) hears them. Players -> host traffic is whispered.
local Comm = { PREFIX = "Bonfire1", CHANNEL = "BonfireCamp" }
ns.Comm = Comm

local handlers = {}

-- Tags every message so a client can drop its own, whatever its sender name looks like.
Comm.id = ("%x%x"):format(math.random(0, 0xfffffff), GetServerTime())

function Comm.On(kind, fn)
	handlers[kind] = handlers[kind] or {}
	table.insert(handlers[kind], fn)
end

function Comm:Enable()
	Bonfire:RegisterComm(self.PREFIX, function(_, payload, distribution, sender)
		self:Receive(payload, distribution, sender)
	end)
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
	if not id then return false end
	data.k, data.i = kind, self.id
	Bonfire:SendCommMessage(self.PREFIX, Bonfire:Serialize(data), "CHANNEL", tostring(id), prio or "NORMAL")
	return true
end

function Comm:Whisper(target, kind, data)
	data = data or {}
	data.k, data.i = kind, self.id
	Bonfire:SendCommMessage(self.PREFIX, Bonfire:Serialize(data), "WHISPER", target, "ALERT")
end

function Comm:Receive(payload, distribution, sender)
	local ok, data = Bonfire:Deserialize(payload)
	if not ok or type(data) ~= "table" then return end
	if data.i == self.id then
		if distribution == "CHANNEL" then self.selfSender = sender end
		return
	end
	self.lastSender = sender
	sender = ns.FullName(sender)
	for _, fn in ipairs(handlers[data.k] or {}) do
		fn(data, sender, distribution)
	end
end
