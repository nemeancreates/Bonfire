local _, ns = ...
local Bonfire = ns.Bonfire
local HBD = LibStub("HereBeDragons-2.0")
local Pins = LibStub("HereBeDragons-Pins-2.0")

-- Open tables announce where they are; everyone else keeps a list and pins them
-- on the minimap and world map. Stands in for the campfire smoke trail the game lacks.
local Beacon = { fires = {} }  -- host -> { mapID, x, y, game, seats, maxSeats, state, stake, seen }
ns.Beacon = Beacon

local EXPIRE = 95          -- seconds without a beacon before a fire drops off
local ANNOUNCE_EVERY = 30
local NEARBY = 60          -- yards: close enough to say a fire is nearby
local ICON = "Interface\\Icons\\Spell_Fire_Fire"

local function PinTooltip(pin)
	local fire = pin.fire
	GameTooltip:SetOwner(pin, "ANCHOR_RIGHT")
	GameTooltip:AddLine("Bonfire: " .. ns.Short(fire.host))
	if fire.state == "camp" then
		GameTooltip:AddLine("A campfire, no table yet", 1, 1, 1)
		GameTooltip:AddLine("Rest nearby for the campfire buff, or ask them to open a table.", 0.6, 0.8, 1, true)
		GameTooltip:Show()
		return
	end
	local game = ns.Games[fire.game]
	GameTooltip:AddLine(("%s  %d/%d seats %s"):format(game and game.name or "?", fire.seats or 0, fire.maxSeats or 0, ns.StakeBadge(fire.stake)), 1, 1, 1)
	GameTooltip:AddLine((fire.stake or 0) > 0 and ("Stake " .. ns.Coins(fire.stake)) or "For fun, no gold involved", 1, 1, 1)
	GameTooltip:AddLine(fire.state == "playing" and "Game in progress" or fire.state == "settling" and "Closing up" or "Open, /bf to join", 0.6, 0.8, 1)
	GameTooltip:Show()
end

local function MakePin(size)
	local pin = CreateFrame("Frame", nil, UIParent)
	pin:SetSize(size, size)
	local tex = pin:CreateTexture(nil, "OVERLAY")
	tex:SetAllPoints()
	tex:SetTexture(ICON)
	pin.coin = pin:CreateTexture(nil, "OVERLAY", nil, 1)
	pin.coin:SetTexture(ns.COIN_ICON)
	pin.coin:SetSize(size * 0.6, size * 0.6)
	pin.coin:SetPoint("BOTTOMRIGHT", size * 0.25, -size * 0.25)
	pin:EnableMouse(true)
	pin:SetScript("OnEnter", PinTooltip)
	pin:SetScript("OnLeave", GameTooltip_Hide)
	pin:SetScript("OnMouseUp", function() ns.UI:Show() end)
	return pin
end

function Beacon:Enable()
	ns.Comm.On("B", function(d, sender) self:OnBeacon(d, sender) end)
	ns.Comm.On("X", function(_, sender) self:Remove(sender) end)
	ns.Comm.On("Q", function() self:OnQuery() end)
	Bonfire:ScheduleRepeatingTimer(function() self:Tick() end, 5)
	-- Ask who's already out there once the channel is up.
	C_Timer.After(15, function() ns.Comm:Broadcast("Q", {}, "BULK") end)
end

function Beacon:Announce()
	local t = ns.Table.current
	if not t or t.host ~= ns.Me() then return end
	if t.stake > 0 and ns.Table:HasBots() then return end  -- practice gold tables stay off the map
	self.lastAnnounce = GetTime()
	ns.Comm:Broadcast("B", {
		m = t.fire[1], x = floor(t.fire[2] * 10000), y = floor(t.fire[3] * 10000),
		g = t.game, s = #t.seats, n = t.maxSeats, st = t.state, a = t.stake,
	}, "BULK")
end

-- A campfire you placed with no table at it is still worth showing on everyone's map.
function Beacon:AnnounceFire()
	local f = ns.Table.placed
	if ns.Table.current or not f then return end
	local ends = f.at + ns.Table.FIRE_LIFETIME
	if GetServerTime() >= ends then return end
	self.lastAnnounce = GetTime()
	ns.Comm:Broadcast("B", {
		m = f.map, x = floor(f.x * 10000), y = floor(f.y * 10000),
		s = 0, n = 0, st = "camp", a = 0, e = ends,
	}, "BULK")
end

function Beacon:OnQuery()
	-- Spread replies out so a query doesn't trigger a burst from every host at once.
	C_Timer.After(math.random() * 4, function()
		if ns.Table.current then self:Announce() else self:AnnounceFire() end
	end)
end

function Beacon:OnBeacon(d, sender)
	if sender == ns.Me() then return end
	if type(d.m) ~= "number" or type(d.x) ~= "number" or type(d.y) ~= "number" then return end
	local fire = self.fires[sender] or { host = sender }
	fire.mapID, fire.x, fire.y = d.m, d.x / 10000, d.y / 10000
	fire.game, fire.seats, fire.maxSeats, fire.state, fire.stake = d.g, d.s, d.n, d.st, tonumber(d.a) or 0
	fire.seen, fire.ends = GetTime(), d.e
	self.fires[sender] = fire
	self:Pin(fire)
	ns.UI:Refresh()
end

function Beacon:Pin(fire)
	if not Bonfire.db.global.pins then return end
	if not fire.mini then
		fire.mini, fire.world = MakePin(14), MakePin(18)
		fire.mini.fire, fire.world.fire = fire, fire
	end
	fire.mini.coin:SetShown(fire.stake > 0)
	fire.world.coin:SetShown(fire.stake > 0)
	Pins:AddMinimapIconMap(self, fire.mini, fire.mapID, fire.x, fire.y, true, true)
	Pins:AddWorldMapIconMap(self, fire.world, fire.mapID, fire.x, fire.y, HBD_PINS_WORLDMAP_SHOW_PARENT)
end

function Beacon:Unpin(fire)
	if not fire.mini then return end
	Pins:RemoveMinimapIcon(self, fire.mini)
	Pins:RemoveWorldMapIcon(self, fire.world)
	fire.mini:Hide()
	fire.world:Hide()
end

function Beacon:Remove(host)
	local fire = self.fires[host]
	if not fire then return end
	self:Unpin(fire)
	self.fires[host] = nil
	ns.UI:Refresh()
end

function Beacon:Tick()
	local now = GetTime()
	for host, fire in pairs(self.fires) do
		if now - fire.seen > EXPIRE or (fire.ends and GetServerTime() > fire.ends) then self:Remove(host) end
	end
	if now - (self.lastAnnounce or 0) >= ANNOUNCE_EVERY then
		if not ns.Table.current then
			self:AnnounceFire()
		elseif ns.Table.current.host == ns.Me() then
			self:Announce()
		end
	end
	-- Tell you when you come near a fire, once per visit (it resets once you're well away).
	if not ns.Table.current then
		for host, fire in pairs(self.fires) do
			local d = self:Distance(fire)
			local near = d ~= nil and d <= NEARBY
			if near and not fire.alerted then Bonfire:Printf("%s's fire is nearby.", ns.Short(host)) end
			fire.alerted = near or (fire.alerted and d ~= nil and d <= NEARBY + 40)
		end
	end
	ns.UI:Refresh()  -- distances drift as you walk
end

-- Yards from the player, or nil when the fire is on another continent.
function Beacon:Distance(fire)
	local x, y, mapID = HBD:GetPlayerZonePosition()
	if not x then return end
	return HBD:GetZoneDistance(mapID, x, y, fire.mapID, fire.x, fire.y)
end

-- Nearest first; fires on other continents sort last.
function Beacon:List()
	local list = {}
	for _, fire in pairs(self.fires) do
		fire.distance = self:Distance(fire)
		list[#list + 1] = fire
	end
	table.sort(list, function(a, b) return (a.distance or math.huge) < (b.distance or math.huge) end)
	return list
end

function Beacon:SetPins(on)
	Bonfire.db.global.pins = on
	for _, fire in pairs(self.fires) do
		if on then self:Pin(fire) else self:Unpin(fire) end
	end
end

ns.AddCommand("pins", "- toggle campfire pins on the minimap and world map", function()
	Beacon:SetPins(not Bonfire.db.global.pins)
	Bonfire:Print("map pins " .. (Bonfire.db.global.pins and "on" or "off"))
end)
