local _, ns = ...
local Bonfire = ns.Bonfire

-- Bonfire gets its own chat tab, so its messages don't drown in a busy chat, and each table
-- gets a small chat channel that everyone at the fire joins when they sit down and leaves
-- when the table ends. Each has its own switch on the settings page (/bf chat flips the tab).
local Chat = {}
ns.Chat = Chat

local TAB = "Bonfire"

local function FindTab()
	if not GetChatWindowInfo then return end
	for i = 1, NUM_CHAT_WINDOWS do
		if GetChatWindowInfo(i) == TAB then return _G["ChatFrame" .. i] end
	end
end

-- The Bonfire tab, made the first time it's needed and reused afterwards. nil if this
-- client can't make chat windows, in which case messages stay in the main chat.
function Chat:EnsureTab()
	if not Bonfire.db.global.chatTab then return end
	if self.frame then return self.frame end
	local frame = FindTab()
	if not frame and GetChatWindowInfo and FCF_OpenNewWindow then
		local ok, made = pcall(FCF_OpenNewWindow, TAB, true)
		frame = (ok and made) or FindTab()
	end
	self.frame = frame
	return frame
end

-- One channel per campfire, named for where the fire is so it survives a change of host.
local function ChannelFor(t)
	local f = t.fire
	if not f then return end
	return ("BFT%d%d%d"):format(f[1], math.floor(f[2] * 10000 + 1e-6), math.floor(f[3] * 10000 + 1e-6))
end

-- Join the table's channel while you have a table, leave it when the table ends.
function Chat:Sync()
	local t = ns.Table.current
	local want = Bonfire.db.global.tableChat and t and ChannelFor(t) or nil
	if want == self.channel then return end
	if self.channel then
		if LeaveChannelByName then pcall(LeaveChannelByName, self.channel) end
		self.channel = nil
	end
	if not want then return end
	self.channel = want
	JoinTemporaryChannel(want)
	local frame = self:EnsureTab()
	C_Timer.After(1, function()
		if self.channel ~= want then return end
		-- Keep the table's chat in the Bonfire tab and out of the other windows.
		for i = 1, NUM_CHAT_WINDOWS do
			local f = _G["ChatFrame" .. i]
			if f and f ~= frame and ChatFrame_RemoveChannel then pcall(ChatFrame_RemoveChannel, f, want) end
		end
		if frame and ChatFrame_AddChannel then pcall(ChatFrame_AddChannel, frame, want) end
		local id = GetChannelName(want)
		if id and id > 0 then
			Bonfire:Printf("Table chat: type /%d and your message to talk to everyone at this fire.", id)
		end
	end)
end

function Chat:Enable()
	C_Timer.After(4, function() self:EnsureTab() end)
	C_Timer.NewTicker(2, function() self:Sync() end)
end

-- The Bonfire tab on or off (the settings page has the same switch).
function Chat:SetTab(on)
	Bonfire.db.global.chatTab = on
	if on then self:EnsureTab() else self.frame = nil end
end

ns.AddCommand("chat", "- Bonfire's own chat tab on or off (more switches on the settings page, the gear)", function()
	Chat:SetTab(not Bonfire.db.global.chatTab)
	Bonfire:Print("Bonfire's chat tab is " .. (Bonfire.db.global.chatTab and "on: look for the Bonfire tab." or "off: messages are back in your main chat."))
end)
