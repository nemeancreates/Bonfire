local _, ns = ...
local Bonfire = ns.Bonfire
local HBD = LibStub("HereBeDragons-2.0")
local Embers = ns.Games.embers
local Ledger = ns.Ledger

-- A table is host-authoritative. The host holds the real game, rolls the dice,
-- keeps the ledger of who has paid what, and broadcasts the full state after every
-- change; players only send requests. The state carries the host's name and the
-- server sets the sender, so nobody else can speak for a table.
--
-- current: { host, game, stake (copper, 0 = for fun), maxSeats, state = "open"|"playing"|"settling",
--   seats, fire = { mapID, x, y }, balances, cashout, left, committed, id, gs = packed game,
--   winners, share, lastRoll, payouts (players only), heard (players only) }
local Table = { current = nil, FOLD_RANGE = 35, FOLD_AFTER = 3, HOST_LEAVE_AFTER = 12 }
ns.Table = Table

local MAX_SEATS = 10
local ROLL_GAP = 3          -- seconds between rolls, so players get a chance to bank
local ROLL_TIMEOUT = 5      -- give up waiting for a roll that never showed up in chat
local HOST_TIMEOUT = 100    -- drop a table whose host has gone quiet
local WARN_RANGE = 28       -- yards from the fire before we warn you
local FOLD_AFTER = Table.FOLD_AFTER  -- seconds past FOLD_RANGE before you fold
local HOST_LEAVE_AFTER = Table.HOST_LEAVE_AFTER -- seconds a host can be past FOLD_RANGE before losing the table
local RESTORE_WINDOW = 3600 -- a hosted table survives a reload or relog this long
local FIRE_LIFETIME = 900   -- a Basic Campfire's listed duration (15 min, unconfirmed in beta)
local LAST_GAME_LINGER = 10 -- seconds the final result stays up before the table closes

local counted = {}  -- game id -> true once it's in your stats

local function RemoveValue(list, value)
	for i = #list, 1, -1 do
		if list[i] == value then table.remove(list, i) end
	end
end

local function Pack(g)
	local p = {}
	for i, name in ipairs(g.order) do
		local pl = g.players[name]
		p[i] = { name, pl.total, pl.pot, (pl.stoking and 1 or 0) + (pl.left and 2 or 0) }
	end
	return { r = g.round, R = g.rounds, o = g.over or nil, p = p }
end

local function Wire(t)
	local b = {}
	for i, name in ipairs(t.seats) do b[i] = Ledger.Balance(t, name) end
	return {
		h = t.host, g = t.game, a = t.stake, n = t.maxSeats, st = t.state, s = t.seats, b = b,
		f = { t.fire[1], floor(t.fire[2] * 10000), floor(t.fire[3] * 10000) },
		pq = Ledger.Payouts(t), id = t.id, gs = t.gs, w = t.winners, sh = t.share, lr = t.lastRoll,
		e = t.ends, cl = t.closing and 1 or nil,
	}
end

local function Unwire(d)
	if type(d.s) ~= "table" or type(d.a) ~= "number" or type(d.f) ~= "table" then return end
	local t = {
		host = d.h, game = d.g, stake = d.a, maxSeats = d.n, state = d.st, seats = d.s,
		fire = { d.f[1], (d.f[2] or 0) / 10000, (d.f[3] or 0) / 10000 }, payouts = d.pq or {},
		id = d.id, gs = d.gs, winners = d.w, share = d.sh, lastRoll = d.lr, balances = {},
		ends = d.e, closing = d.cl == 1,
	}
	for i, name in ipairs(t.seats) do t.balances[name] = type(d.b) == "table" and d.b[i] or 0 end
	return t
end

function Table:IsHosting()
	return self.current ~= nil and self.current.host == ns.Me()
end

function Table:Enable()
	ns.Comm.On("S", function(d, sender) self:OnState(d, sender) end)
	ns.Comm.On("X", function(_, sender) self:OnClosed(sender) end)
	ns.Comm.On("B", function(_, sender) self:Heard(sender) end)
	ns.Comm.On("N", function(d, sender) self:OnRefused(d, sender) end)
	ns.Comm.On("J", function(_, sender) self:OnJoin(sender) end)
	ns.Comm.On("L", function(_, sender) self:OnLeave(sender) end)
	ns.Comm.On("K", function(_, sender) self:OnBank(sender) end)
	ns.Comm.On("C", function(_, sender) self:OnCashOut(sender) end)
	ns.Comm.On("P", function(d, sender) self:OnOffer(d, sender) end)
	ns.Comm.On("PA", function(_, sender) self:OnOfferAccepted(sender) end)
	ns.Comm.On("T", function(d, sender) self:OnTakeover(d, sender) end)
	Bonfire:RegisterEvent("CHAT_MSG_SYSTEM", function(_, msg) self:OnSystemMessage(msg) end)
	Bonfire:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED", function(_, unit, _, spellID) self:OnCast(unit, spellID) end)
	Bonfire:ScheduleRepeatingTimer(function() self:Watchdog() end, 5)
	Bonfire:ScheduleRepeatingTimer(function() self:RangeCheck() end, 1)
	C_Timer.After(15, function() self:Restore() end)
end

-- Record keeping ------------------------------------------------------------------

function Table:CountStats(t)
	if not t.id or not t.winners or counted[t.id] or not t.gs then return end
	local me = ns.Me()
	for _, p in ipairs(t.gs.p) do
		if p[1] == me then
			counted[t.id] = true
			local stats = Bonfire.db.global.stats
			stats.played = stats.played + 1
			if tContains(t.winners, me) then
				stats.won = stats.won + 1
				if t.stake > 0 then
					Bonfire:Printf("You won %s! It's held as credit at the table; Cash out whenever you like.", ns.Coins(t.share))
				else
					Bonfire:Print("You won!")
				end
			end
			return
		end
	end
end

-- Range: you're at the fire while you're within FOLD_RANGE yards of where it was lit.
function Table:DistanceToFire(t)
	t = t or self.current
	if not t or not t.fire then return end
	local x, y, mapID = HBD:GetPlayerZonePosition()
	if not x then return end
	return HBD:GetZoneDistance(mapID, x, y, t.fire[1], t.fire[2], t.fire[3])
end

function Table:RangeCheck()
	local t = self.current
	if not t then return end
	local d = self:DistanceToFire()
	if d and d <= self.FOLD_RANGE then
		if d > WARN_RANGE and not self.warned then
			self.warned = true
			Bonfire:Printf("You're drifting from the fire (%d yd). Past %d yd you fold.", d, self.FOLD_RANGE)
		elseif d <= WARN_RANGE - 3 then
			self.warned = false
		end
		self.away = 0
		return
	end
	self.away = (self.away or 0) + 1
	if self:IsHosting() then
		if self.away == FOLD_AFTER then
			local heir = self:CanPass() and self:NextHost()
			Bonfire:Printf("You've left your fire. %s in %d seconds unless you go back.",
				heir and (ns.Short(heir) .. " takes over the table") or "The table closes", HOST_LEAVE_AFTER - FOLD_AFTER)
		elseif self.away == HOST_LEAVE_AFTER then
			self:PassHost()
		end
	elseif self.away == FOLD_AFTER then
		Bonfire:Print("You walked away from the fire and folded.")
		self:Leave()
	end
end

-- Host side ------------------------------------------------------------------

-- anywhere skips the campfire check (/bf host, and right after our own kit cast).
function Table:Host(anywhere)
	if self.current then return Bonfire:Print("You're already at a table.") end
	if not ns.BetReady() then return Bonfire:Print("Add an amount and Confirm bet first, or switch to For fun.") end
	if not anywhere and not ns.AtCampfire() then
		return Bonfire:Print("Stand at a campfire (the Welcoming Campfire buff), or light one with a Basic Campfire Kit. /bf host skips this check.")
	end
	if not ns.Comm:ChannelId() or not ns.Comm.selfSender then
		return Bonfire:Print("Still connecting to the Bonfire channel, try again in a few seconds.")
	end
	local x, y, mapID = HBD:GetPlayerZonePosition()
	if not x then return Bonfire:Print("Can't host here: no map position.") end
	self.game = nil
	self.current = {
		host = ns.Me(), game = "embers", stake = ns.StakeCopper(), maxSeats = MAX_SEATS, state = "open",
		seats = { ns.Me() }, fire = { mapID, x, y }, ends = GetServerTime() + FIRE_LIFETIME,
	}
	Ledger.Init(self.current)
	ns.Beacon:Announce()
	self:Push()
end

-- The Light a fire button just used the kit. The first spell that lands in the
-- next few seconds is the campfire going down, so start the table where it is.
function Table:Armed()
	self.armedAt = GetTime()
end

function Table:OnCast(unit, spellID)
	if unit ~= "player" or not self.armedAt then return end
	if GetTime() - self.armedAt > 12 then
		self.armedAt = nil
		return
	end
	self.armedAt = nil
	local name = C_Spell.GetSpellName(spellID) or "?"
	Bonfire:Printf("Campfire lit (%s). Your table is open.", name)
	self:Host(true)
end

-- Picks up the stake setting (amount, coin, for fun) between games.
function Table:SetStake()
	local t = self.current
	if not self:IsHosting() or t.state ~= "open" then return end
	t.stake = ns.StakeCopper()
	self:Push()
	ns.Beacon:Announce()
end

-- First click stops new games and queues everyone's credit for payout; the fire
-- goes out once everyone is paid back, or on a second click.
function Table:Close()
	local t = self.current
	if not self:IsHosting() then return end
	if t.state == "playing" then self:Abandon() end
	if t.state ~= "settling" then
		t.state = "settling"
		if #Ledger.Payouts(t) > 0 then
			Bonfire:Print("Pay everyone back from the queue before your fire goes out. Click Close again to put it out anyway.")
			self:Push()
			ns.Beacon:Announce()
			return
		end
	elseif #Ledger.Payouts(t) > 0 then
		for _, p in ipairs(Ledger.Payouts(t)) do
			Bonfire:Printf("|cffff6666You still owe %s %s.|r", ns.Short(p[1]), ns.Coins(p[2]))
		end
	end
	self:PutOut()
end

function Table:PutOut()
	ns.Comm:Broadcast("X", {})
	self.current, self.game, self.awaitingRoll = nil, nil, false
	Bonfire.db.char.hosted = nil
	ns.UI:Refresh()
end

function Table:Abandon()
	local t = self.current
	Ledger.Void(t)
	self.game, t.gs, t.state = nil, nil, "open"
	Bonfire:Print("Game abandoned; stakes returned to everyone's balance.")
end

function Table:Push()
	if self.pushTimer then return end
	self.pushTimer = C_Timer.NewTimer(0.3, function()
		self.pushTimer = nil
		self:SendState()
	end)
end

function Table:SendState()
	local t = self.current
	if not self:IsHosting() then return end
	t.gs = self.game and Pack(self.game) or t.gs
	t.savedAt = GetServerTime()
	Bonfire.db.char.hosted = t  -- the ledger is real money; keep it through reloads
	ns.Comm:Broadcast("S", Wire(t), "ALERT")
	self:CountStats(t)
	ns.UI:Refresh()
end

-- After a reload the game in progress is gone, so its stakes go back; balances stay.
function Table:Restore()
	local saved = Bonfire.db.char.hosted
	if not saved or self.current then return end
	-- The name others see us as is learned from the channel a few seconds after login.
	if not ns.Comm.selfSender then return C_Timer.After(5, function() self:Restore() end) end
	Bonfire.db.char.hosted = nil
	saved.ends = saved.ends or GetServerTime()  -- older saves have no timer: let them run out
	Ledger.Init(saved)
	if saved.host ~= ns.Me() or GetServerTime() - (saved.savedAt or 0) > RESTORE_WINDOW then
		for name, balance in pairs(saved.balances) do
			if balance > 0 then Bonfire:Printf("|cffff6666From your last fire you still owe %s %s.|r", ns.Short(name), ns.Coins(balance)) end
		end
		return
	end
	self.current = saved
	if saved.state == "playing" then self:Abandon() end
	Bonfire:Print("Your fire is back, balances and all.")
	self:Push()
	ns.Beacon:Announce()
end

function Table:OnJoin(sender)
	local t = self.current
	if not self:IsHosting() then return ns.Comm:Whisper(sender, "N", { r = "that fire is out" }) end
	if tContains(t.seats, sender) then return self:Push() end
	if t.state == "settling" or t.closing then return ns.Comm:Whisper(sender, "N", { r = "the fire is dying" }) end
	if #t.seats >= t.maxSeats then return ns.Comm:Whisper(sender, "N", { r = "the table is full" }) end
	t.seats[#t.seats + 1] = sender
	t.left[sender] = nil  -- back again: any credit is theirs to play with
	self:Push()
	ns.Beacon:Announce()
end

function Table:OnLeave(sender)
	local t = self.current
	if not self:IsHosting() or not tContains(t.seats, sender) then return end
	if self.game and self.game.players[sender] and t.state == "playing" then
		Embers.Leave(self.game, sender)  -- forfeits their stake
		if self.game.over then self:Finish() end
	end
	RemoveValue(t.seats, sender)
	Ledger.Leave(t, sender)
	self:Push()
	ns.Beacon:Announce()
end

function Table:OnCashOut(sender)
	local t = self.current
	if not self:IsHosting() or not tContains(t.seats, sender) then return end
	t.cashout[sender] = true
	self:Push()
end

function Table:OnBank(sender)
	if not self:IsHosting() or self.current.state ~= "playing" then return end
	if Embers.Bank(self.game, sender) then
		if self.game.over then self:Finish() end
		self:Push()
	end
end

-- The host's Stoke button: deals in everyone who's paid up and starts the game.
function Table:Start()
	local t = self.current
	if not self:IsHosting() or t.state ~= "open" then return end
	if t.ends and GetServerTime() >= t.ends then return Bonfire:Print("Your fire has burned out; no new games.") end
	local players = Ledger.Eligible(t)
	if #players < 2 then
		return Bonfire:Print(t.stake > 0 and "Need at least 2 paid-up players to stoke the fire." or "Need at least 2 players to stoke the fire.")
	end
	Ledger.Commit(t, players)
	self.game = Embers.New(players)
	t.state, t.id, t.winners, t.share, t.lastRoll = "playing", ns.Me() .. ":" .. GetServerTime(), nil, nil, nil
	self.lastRollAt = GetTime()
	self:Push()
	ns.Beacon:Announce()
end

function Table:CanRoll()
	return self:IsHosting() and self.current.state == "playing" and not self.awaitingRoll
		and GetTime() - (self.lastRollAt or 0) >= ROLL_GAP
end

-- From the Roll button: it has to be a real server /roll everyone nearby sees.
function Table:Roll()
	if not self:CanRoll() then return end
	self.awaitingRoll = true
	RandomRoll(1, Embers.sides)
	C_Timer.After(ROLL_TIMEOUT, function()
		if self.awaitingRoll then
			self.awaitingRoll = false
			ns.UI:Refresh()
		end
	end)
	ns.UI:Refresh()
end

function Table:OnSystemMessage(msg)
	if not self.awaitingRoll then return end
	local who, value, low, high = ns.ParseRoll(msg)
	if not who or ns.NameKey(who) ~= ns.NameKey(UnitName("player")) or low ~= 1 or high ~= Embers.sides then return end
	self.awaitingRoll = false
	self.lastRollAt = GetTime()
	self.current.lastRoll = value
	Embers.Roll(self.game, value)
	if self.game.over then self:Finish() end
	self:Push()
	C_Timer.After(ROLL_GAP, function() ns.UI:Refresh() end)
end

function Table:Finish()
	local t = self.current
	t.gs = Pack(self.game)
	t.winners = Embers.Winners(self.game)
	t.share = Ledger.Settle(t, t.winners)
	t.state = "open"
	self.game = nil
	ns.Beacon:Announce()
	if t.closing then
		-- The fire burned out mid-game; that was the last one. Let the result show, then close up.
		C_Timer.After(LAST_GAME_LINGER, function()
			if self.current == t and t.state == "open" then self:Close() end
		end)
	end
end

-- Host: when the fire's time is up, finish the game in progress and close; otherwise close now.
function Table:CheckExpiry()
	local t = self.current
	if not self:IsHosting() or t.state == "settling" or not t.ends or GetServerTime() < t.ends then return end
	if t.state == "playing" then
		if not t.closing then
			t.closing = true
			Bonfire:Print("Your fire is dying. This is the last game; the table closes after it.")
			self:Push()
		end
	else
		Bonfire:Print("Your fire has burned out.")
		self:Close()
	end
end

-- Trades ----------------------------------------------------------------------

-- Seconds until the fire burns out, or nil if the table has no timer.
function Table:TimeLeft(t)
	t = t or self.current
	if not t or not t.ends then return end
	return math.max(0, t.ends - GetServerTime())
end

-- Hand-off -----------------------------------------------------------------------

-- Who's next in line: the first player who sat down after the host.
function Table:NextHost()
	local t = self.current
	for _, name in ipairs(t and t.seats or {}) do
		if name ~= t.host then return name end
	end
end

-- A host who leaves while the fire still burns passes the table to whoever sat down
-- first. Gold can't change hands, so a table holding anyone's credit closes instead.
function Table:CanPass()
	local t = self.current
	if not t or not self:IsHosting() or t.state == "settling" or not self:NextHost() then return false end
	if t.ends and GetServerTime() >= t.ends then return false end
	return Ledger.Empty(t)
end

function Table:PassHost()
	local t = self.current
	if not self:CanPass() then return self:Close() end
	if t.state == "playing" then self:Abandon() end
	local queue = {}
	for _, name in ipairs(t.seats) do
		if name ~= t.host then queue[#queue + 1] = name end
	end
	self.passing = { queue = queue, i = 0 }
	self:OfferHost()
end

-- Offers the table to each player in turn; someone who isn't at the fire stays silent
-- and the offer moves on after a few seconds.
function Table:OfferHost()
	local p = self.passing
	if not p then return end
	p.i = p.i + 1
	local name = p.queue[p.i]
	if not name then
		self.passing = nil
		Bonfire:Print("Nobody at the fire could take over, so the table is closing.")
		return self:Close()
	end
	p.offered = name
	ns.Comm:Whisper(name, "P", Wire(self.current))
	C_Timer.After(4, function()
		if self.passing == p and p.offered == name then self:OfferHost() end
	end)
end

-- Player side: accept if we're still at the fire.
function Table:OnOffer(d, sender)
	local t = self.current
	if not t or t.host ~= sender or self:IsHosting() then return end
	local away = self:DistanceToFire()
	if not away or away > self.FOLD_RANGE then return end
	local offered = Unwire(d)
	if not offered or not tContains(offered.seats, ns.Me()) then return end
	self.offer = { from = sender, t = offered }
	ns.Comm:Whisper(sender, "PA")
end

function Table:OnOfferAccepted(sender)
	local p = self.passing
	if not p or p.offered ~= sender or not self:IsHosting() then return end
	self.passing = nil
	ns.Comm:Broadcast("T", { to = sender }, "ALERT")
	Bonfire:Printf("%s took over your table.", ns.Short(sender))
	self.current, self.game, self.awaitingRoll = nil, nil, false
	Bonfire.db.char.hosted = nil
	ns.UI:Refresh()
end

-- Everyone: the host named a successor. The new host starts fresh at the same fire.
function Table:OnTakeover(d, sender)
	ns.Beacon:Remove(sender)  -- the old host's beacon is stale now
	local t = self.current
	if not t or t.host ~= sender or type(d.to) ~= "string" then return end
	if d.to == ns.Me() then
		local offer = self.offer
		if not offer or offer.from ~= sender then return end
		self.offer = nil
		local nt = offer.t
		RemoveValue(nt.seats, sender)
		nt.host, nt.state, nt.gs, nt.winners, nt.payouts, nt.heard = ns.Me(), "open", nil, nil, nil, nil
		Ledger.Init(nt)
		self.current, self.game, self.away, self.warned = nt, nil, 0, false
		Bonfire:Print("The host left the fire, so you're hosting the table now.")
		ns.Beacon:Announce()
		self:Push()
	elseif tContains(t.seats, d.to) then
		t.host = d.to
		RemoveValue(t.seats, sender)
		t.heard = GetTime()
		Bonfire:Printf("%s left the fire; %s hosts now.", ns.Short(sender), ns.Short(d.to))
		ns.UI:Refresh()
	end
end

-- The seat name we use for someone, given any form of their name.
function Table:Resolve(name)
	local t = self.current
	local key = ns.NameKey(name)
	if not t or not key then return name end
	local function match(n) return n and ns.NameKey(n) == key and n or nil end
	local found = match(t.host)
	for _, n in ipairs(t.seats) do found = found or match(n) end
	for n in pairs(t.left or {}) do found = found or match(n) end
	for n in pairs(t.balances or {}) do found = found or match(n) end
	return found or name
end

-- What to fill into a trade window that just opened with this partner.
function Table:AmountToGive(partner)
	local t = self.current
	if not t or not partner then return end
	if self:IsHosting() then
		for _, p in ipairs(Ledger.Payouts(t)) do
			if p[1] == partner then return p[2] end
		end
	elseif partner == t.host and t.state ~= "settling" then
		return Ledger.Owes(t, ns.Me())
	end
end

-- copper > 0: we received it from partner.
function Table:OnTradeComplete(partner, copper)
	local t = self.current
	if not t then return end
	if self:IsHosting() then
		if not tContains(t.seats, partner) and not t.left[partner] then return end
		Ledger.Credit(t, partner, copper)
		Bonfire:Printf("%s %s %s. Balance now %s.", ns.Short(partner), copper > 0 and "paid in" or "was paid",
			ns.CoinString(math.abs(copper)), ns.Coins(Ledger.Balance(t, partner)))
		if t.state == "settling" and #Ledger.Payouts(t) == 0 then
			Bonfire:Print("Everyone's paid back. Your fire is out.")
			return self:PutOut()
		end
		self:Push()
	elseif partner == t.host then
		Bonfire:Printf(copper < 0 and "You paid %s to %s." or "You received %s from %s.",
			ns.CoinString(math.abs(copper)), ns.Short(partner))
	end
end

-- Host fix-up for a trade the addon missed (or gold handed over outside Bonfire).
function Table:Adjust(who, copper)
	local t = self.current
	if not self:IsHosting() then return Bonfire:Print("Only the host keeps the ledger.") end
	local match
	for _, name in ipairs(t.seats) do
		if ns.NameKey(name) == ns.NameKey(who) then match = name end
	end
	for name in pairs(t.left) do
		if ns.NameKey(name) == ns.NameKey(who) then match = name end
	end
	if not match then return Bonfire:Printf("No one called %s at your fire.", who) end
	Ledger.Credit(t, match, copper)
	Bonfire:Printf("%s's balance is now %s.", ns.Short(match), ns.Coins(Ledger.Balance(t, match)))
	self:Push()
end

-- Player side ----------------------------------------------------------------

function Table:Join(host)
	if self.current then return Bonfire:Print("Leave your current table first.") end
	local fire = ns.Beacon.fires[host]
	local d = fire and ns.Beacon:Distance(fire)
	if not d or d > self.FOLD_RANGE then
		return Bonfire:Printf("Walk over to %s's fire first (within %d yd).", ns.Short(host), self.FOLD_RANGE)
	end
	self.pendingJoin = host
	ns.Comm:Whisper(host, "J")
end

function Table:Leave()
	local t = self.current
	if not t then return end
	if self:IsHosting() then
		if self:CanPass() then return self:PassHost() end
		return self:Close()
	end
	ns.Comm:Whisper(t.host, "L")
	local balance = Ledger.Balance(t, ns.Me())
	if balance > 0 then
		Bonfire:Printf("%s still holds %s for you. Trade them to collect.", ns.Short(t.host), ns.Coins(balance))
	end
	self.current, self.away, self.warned = nil, 0, false
	ns.UI:Refresh()
end

function Table:Bank()
	local t = self.current
	if not t or t.state ~= "playing" then return end
	if self:IsHosting() then self:OnBank(ns.Me()) else ns.Comm:Whisper(t.host, "K") end
end

function Table:CashOut()
	local t = self.current
	if t and not self:IsHosting() then ns.Comm:Whisper(t.host, "C") end
end

function Table:PayHost()
	local t = self.current
	if t and not self:IsHosting() then ns.Trade:Open(t.host) end
end

function Table:OnState(d, sender)
	if d.h ~= sender or sender == ns.Me() then return end
	local ours = self.current and self.current.host == sender
	if not ours and self.pendingJoin ~= sender then return end
	local t = Unwire(d)
	if not t or not tContains(t.seats, ns.Me()) then
		-- Either our join hasn't landed yet, or the host dropped us.
		if ours and t then
			self.current = nil
			ns.UI:Refresh()
		end
		return
	end
	self.pendingJoin = nil
	t.heard = GetTime()
	self.current = t
	self:CountStats(t)
	ns.UI:Refresh()
end

function Table:OnRefused(d, sender)
	if self.pendingJoin ~= sender then return end
	self.pendingJoin = nil
	Bonfire:Printf("Couldn't join %s: %s.", ns.Short(sender), tostring(d.r))
end

function Table:OnClosed(sender)
	local t = self.current
	if t and t.host == sender and sender ~= ns.Me() then
		self.current = nil
		Bonfire:Printf("%s put out their fire.", ns.Short(sender))
		local balance = Ledger.Balance(t, ns.Me())
		if balance > 0 then Bonfire:Printf("|cffff6666They still held %s for you.|r", ns.Coins(balance)) end
		ns.UI:Refresh()
	end
end

function Table:Heard(sender)
	if self.current and self.current.host == sender then self.current.heard = GetTime() end
end

function Table:Watchdog()
	self:CheckExpiry()
	local t = self.current
	if t and not self:IsHosting() and GetTime() - (t.heard or 0) > HOST_TIMEOUT then
		self.current = nil
		Bonfire:Printf("Lost contact with %s's fire.", ns.Short(t.host))
		ns.UI:Refresh()
	end
end

ns.AddCommand("host", "- host a table where you stand (no campfire needed, for testing)", function()
	Table:Host(true)
end)

ns.AddCommand("leave", "- leave your table, or close it if you're hosting", function()
	Table:Leave()
end)

ns.AddCommand("adjust", "<name> <amount> - host only: fix a balance (5g, -20s; + means they paid you)", function(arg)
	local who, sign, amount = arg:match("^(%S+)%s+(%-?)(.+)$")
	local copper = amount and ns.ParseMoney(amount)
	if not copper then return Bonfire:Print("usage: /bf adjust <name> <amount>, e.g. /bf adjust Oppa 5g") end
	Table:Adjust(who, sign == "-" and -copper or copper)
end)

ns.AddCommand("stats", "- your games played and won", function()
	local stats = Bonfire.db.global.stats
	Bonfire:Printf("%d won of %d played.", stats.won, stats.played)
end)
