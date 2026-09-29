local _, ns = ...
local Bonfire = ns.Bonfire

-- A bar at the top of the screen showing how far you are from the fire whenever you
-- have a table, so nobody has to read chat to know they're about to fold.
local Range = {}
ns.Range = Range

local WARN_AT = 28
local hud, sounded

local function Color(d)
	if d < 20 then return 0.3, 0.9, 0.3 end
	if d < WARN_AT then return 1, 0.85, 0.2 end
	if d < ns.Table.FOLD_RANGE then return 1, 0.5, 0.1 end
	return 1, 0.15, 0.15
end

function Range:Place()
	if not hud then return end
	local pos = Bonfire.db.global.rangePos
	hud:ClearAllPoints()
	if pos then
		hud:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4])
	else
		hud:SetPoint("TOP", UIParent, "TOP", 0, -170)
	end
end

local function Build()
	hud = CreateFrame("Frame", "BonfireRange", UIParent)
	hud:SetSize(230, 26)
	hud:SetFrameStrata("HIGH")
	hud:SetMovable(true)
	hud:EnableMouse(true)
	hud:SetClampedToScreen(true)
	hud:RegisterForDrag("LeftButton")
	hud:SetScript("OnDragStart", hud.StartMoving)
	hud:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		local point, _, relPoint, x, y = self:GetPoint()
		Bonfire.db.global.rangePos = { point, relPoint, x, y }
	end)
	hud:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
		GameTooltip:SetText("Distance to the fire. Drag to move.", 1, 1, 1)
		GameTooltip:Show()
	end)
	hud:SetScript("OnLeave", GameTooltip_Hide)
	hud.bg = hud:CreateTexture(nil, "BACKGROUND")
	hud.bg:SetAllPoints()
	hud.bg:SetColorTexture(0, 0, 0, 0.6)
	hud.bar = CreateFrame("StatusBar", nil, hud)
	hud.bar:SetPoint("TOPLEFT", 2, -2)
	hud.bar:SetPoint("BOTTOMRIGHT", -2, 2)
	hud.bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
	hud.bar:SetMinMaxValues(0, ns.Table.FOLD_RANGE)
	hud.text = hud.bar:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	hud.text:SetPoint("CENTER")
	hud.warn = hud:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	hud.warn:SetPoint("TOP", hud, "BOTTOM", 0, -8)
	hud:Hide()
	Range:Place()
end

-- What leaving costs you right now, and how long you have.
local function Warning(d, fold)
	local Table = ns.Table
	local hosting = Table:IsHosting()
	if d >= fold then
		local secs = math.max(0, (hosting and Table.HOST_LEAVE_AFTER or Table.FOLD_AFTER) - (Table.away or 0))
		if hosting then
			return (Table:CanPass() and "YOU LEFT: HOST PASSES IN %d" or "YOU LEFT: TABLE CLOSES IN %d"):format(secs), 1, 0.2, 0.2
		end
		return ("OUT OF RANGE: FOLDING IN %d"):format(secs), 1, 0.2, 0.2
	end
	if d >= WARN_AT then
		local text = "RETURN TO THE FIRE OR FOLD"
		if hosting then
			text = Table:CanPass() and "RETURN TO THE FIRE OR LOSE HOST" or "RETURN TO THE FIRE OR THE TABLE CLOSES"
		end
		return text, 1, 0.55, 0.1
	end
end

local function Update()
	local t = ns.Table.current
	local d = t and ns.Table:DistanceToFire()
	if not d then
		if hud then hud:Hide() end
		return
	end
	if not hud then Build() end
	hud:Show()
	local fold = ns.Table.FOLD_RANGE
	hud.bar:SetStatusBarColor(Color(d))
	hud.bar:SetValue(math.min(d, fold))
	local left = ns.Table:TimeLeft(t)
	local burn = t.closing and "   last game" or (left and left > 0 and ("   %d:%02d"):format(math.floor(left / 60), left % 60) or "")
	hud.text:SetText(("Fire  %d yd%s"):format(d, burn))

	local text, r, g, b = Warning(d, fold)
	hud.warn:SetText(text or "")
	if text then hud.warn:SetTextColor(r, g, b) end
	hud.warn:SetAlpha(0.55 + 0.45 * math.sin(GetTime() * 8))

	if d >= WARN_AT and not sounded then
		sounded = true
		pcall(PlaySound, SOUNDKIT.RAID_WARNING)
	elseif d < WARN_AT - 3 then
		sounded = false
	end
end

function Range:Enable()
	local driver, elapsed = CreateFrame("Frame"), 0
	driver:SetScript("OnUpdate", function(_, dt)
		elapsed = elapsed + dt
		if elapsed < 0.1 then return end
		elapsed = 0
		Update()
	end)
end
