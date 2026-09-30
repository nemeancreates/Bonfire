local _, ns = ...
local Bonfire = ns.Bonfire

-- Gold only moves through the trade window, and Blizzard makes both players click
-- Trade themselves. Bonfire opens the window from a button, fills in what's owed,
-- and tells the table ledger once a trade completes.
local Trade = {}
ns.Trade = Trade

local function UnitFor(name)
	local key = ns.NameKey(name)
	for _, unit in ipairs({ "target", "mouseover", "focus" }) do
		if ns.NameKey(UnitName(unit)) == key then return unit end
	end
	local prefix = IsInRaid() and "raid" or "party"
	for i = 1, GetNumGroupMembers() do
		if ns.NameKey(UnitName(prefix .. i)) == key then return prefix .. i end
	end
end

-- SetTradeMoney isn't in every client, so fall back to the trade window's own money box.
local function FillMoney(copper)
	local set = _G.SetTradeMoney or (C_TradeInfo and C_TradeInfo.SetTradeMoney)
	if set then return pcall(set, copper) end
	if MoneyInputFrame_SetCopper and TradePlayerInputMoneyFrame then
		return pcall(MoneyInputFrame_SetCopper, TradePlayerInputMoneyFrame, copper)
	end
end

function Trade:Enable()
	ns.OnEvent("TRADE_SHOW", function() self:OnShow() end)
	ns.OnEvent("TRADE_MONEY_CHANGED", function() self:Update() end)
	ns.OnEvent("TRADE_ACCEPT_UPDATE", function() self:Update() end)
	ns.OnEvent("TRADE_CLOSED", function() self:OnClosed() end)
	ns.OnEvent("UI_INFO_MESSAGE", function(_, _, msg) self:OnInfo(msg) end)
end

-- Must run from a click. Falls back to asking the player to target and retry.
function Trade:Open(name)
	if ns.Table:IsBot(name) then return ns.Table:BotTrade(name) end
	if self.partner then return end
	pcall(InitiateTrade, UnitFor(name) or Ambiguate(name, "none"))
	C_Timer.After(1.5, function()
		if self.partner ~= name then
			Bonfire:Printf("Couldn't open a trade with %s. Target them and click again, or right-click their portrait and pick Trade. (Trade range is about 10 yd.)", ns.Short(name))
		end
	end)
end

function Trade:OnShow()
	self.partner = ns.Table:Resolve(UnitName("NPC"))
	self.give, self.get = 0, 0
	local amount = ns.Table:AmountToGive(self.partner)
	if not amount or amount <= 0 then return end
	-- The trade frame zeroes the money box as it opens; fill in after it settles.
	C_Timer.After(0.3, function()
		if not self.partner then return end
		local fill = math.min(amount, GetMoney())
		FillMoney(fill)
		-- Check it took before claiming so.
		C_Timer.After(0.5, function()
			if not self.partner then return end
			if GetPlayerTradeMoney() == fill then
				Bonfire:Printf("Filled in %s for your Bonfire table. Check it, then click Trade.", ns.Coins(fill))
			else
				Bonfire:Printf("Enter %s in the trade window for your Bonfire table.", ns.Coins(fill))
			end
		end)
	end)
end

function Trade:Update()
	if not self.partner then return end
	self.give, self.get = GetPlayerTradeMoney(), GetTargetTradeMoney()
end

-- "Trade complete" can land just before or just after TRADE_CLOSED, so keep the
-- last trade around for a moment.
function Trade:OnClosed()
	if not self.partner then return end
	self.last = { partner = self.partner, give = self.give, get = self.get, at = GetTime() }
	self.partner = nil
end

function Trade:OnInfo(msg)
	if msg ~= ERR_TRADE_COMPLETE then return end
	self:Update()
	local done = self.partner and { partner = self.partner, give = self.give, get = self.get } or self.last
	self.last = nil
	if done and (not done.at or GetTime() - done.at < 3) and done.give ~= done.get then
		ns.Table:OnTradeComplete(done.partner, done.get - done.give)
	end
end
