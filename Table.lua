local _, ns = ...
local Bonfire = ns.Bonfire
local HBD = LibStub("HereBeDragons-2.0")
local Embers = ns.Games.embers
local Ledger = ns.Ledger
local Bets = ns.Bets

-- A table is host-authoritative. The host holds the real game, rolls the dice,
-- keeps the ledger of who has paid what, and broadcasts the full state after every
-- change; players only send requests. The state carries the host's name and the
-- server sets the sender, so nobody else can speak for a table.
--
-- current: { host, game, stake (copper, 0 = for fun), maxSeats, state = "open"|"playing"|"settling",
--   seats, fire = { mapID, x, y }, balances, cashout, left, committed, id, gs = packed game,
--   winners, share, lastRoll, payouts (players only), heard (players only) }
local Table = { current = nil, FOLD_RANGE = 35, FOLD_AFTER = 3, HOST_LEAVE_AFTER = 12, botLimit = {} }
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
local FIRE_GONE_AFTER = 20  -- seconds without the campfire buff, at the fire, before we call it out

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

local function PackMarket(m)
	local r, b = {}, {}
	for i, rd in ipairs(m.rounds) do
		r[i] = { ti = rd.title, sd = rd.sides, st = rd.state, w = rd.winner, lk = rd.lockAt, gm = rd.game, sr = rd.started and 1 or nil }
	end
	for i, bet in ipairs(m.bets) do
		b[i] = { bet.id, bet.who, bet.round, bet.side, bet.amount, bet.paid and 1 or 0 }
	end
	return { c = m.cut, cur = m.current, r = r, b = b }
end

local function UnpackMarket(d)
	if type(d) ~= "table" or type(d.r) ~= "table" then return end
	local m = { cut = d.c or 0, current = d.cur or 1, rounds = {}, bets = {}, nextBet = 1 }
	for i, rd in ipairs(d.r) do
		m.rounds[i] = { title = rd.ti, sides = rd.sd, state = rd.st, winner = rd.w, lockAt = rd.lk, game = rd.gm or "Custom", started = rd.sr == 1 }
	end
	for i, b in ipairs(type(d.b) == "table" and d.b or {}) do
		m.bets[i] = { id = b[1], who = b[2], round = b[3], side = b[4], amount = b[5], paid = b[6] == 1 }
	end
	return m
end

local function Wire(t)
	local b = {}
	local tl = {}
	for i, name in ipairs(t.seats) do
		b[i] = Ledger.Balance(t, name)
		local r = t.tally and t.tally[name]
		tl[i] = r and { r.w, r.l, r.net, r.streak } or { 0, 0, 0, 0 }
	end
	return {
		h = t.host, g = t.game, a = t.stake, n = t.maxSeats, st = t.state, s = t.seats, b = b, tl = tl,
		f = { t.fire[1], floor(t.fire[2] * 10000), floor(t.fire[3] * 10000) },
		pq = Ledger.Payouts(t), id = t.id, gs = t.gs, w = t.winners, sh = t.share, lr = t.lastRoll,
		e = t.ends, cl = t.closing and 1 or nil, mk = t.market and PackMarket(t.market) or nil,
	}
end

local function Unwire(d)
	if type(d.s) ~= "table" or type(d.a) ~= "number" or type(d.f) ~= "table" then return end
	local t = {
		host = d.h, game = d.g, stake = d.a, maxSeats = d.n, state = d.st, seats = d.s,
		fire = { d.f[1], (d.f[2] or 0) / 10000, (d.f[3] or 0) / 10000 }, payouts = d.pq or {},
		id = d.id, gs = d.gs, winners = d.w, share = d.sh, lastRoll = d.lr, balances = {},
		ends = d.e, closing = d.cl == 1, market = UnpackMarket(d.mk),
	}
	t.tally = {}
	for i, name in ipairs(t.seats) do
		t.balances[name] = type(d.b) == "table" and d.b[i] or 0
		local r = type(d.tl) == "table" and d.tl[i]
		if type(r) == "table" then t.tally[name] = { w = r[1] or 0, l = r[2] or 0, net = r[3] or 0, streak = r[4] or 0 } end
	end
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
	ns.Comm.On("BP", function(d, sender) self:OnBetPlace(d, sender) end)
	ns.Comm.On("BC", function(d, sender) self:OnBetCancel(d, sender) end)
	ns.Comm.On("BX", function(d) self:Refuse(("Bet refused: %s."):format(tostring(d.r))) end)
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
			self:PassHost(true)
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
		return Bonfire:Print("Rest at a campfire until you get the Welcoming Campfire buff (about a minute), or light one with a Basic Campfire Kit. /bf host skips this check.")
	end
	if not ns.Comm:ChannelId() or not ns.Comm.selfSender then
		return Bonfire:Print("Still connecting to the Bonfire channel, try again in a few seconds.")
	end
	local x, y, mapID = HBD:GetPlayerZonePosition()
	if not x then return Bonfire:Print("Can't host here: no map position.") end
	self.game = nil
	self.sawAura, self.noAuraSince = false, nil
	self.current = {
		host = ns.Me(), game = "embers", stake = ns.StakeCopper(), maxSeats = MAX_SEATS, state = "open",
		seats = { ns.Me() }, fire = { mapID, x, y }, ends = GetServerTime() + FIRE_LIFETIME,
	}
	Ledger.Init(self.current)
	ns.Beacon:Announce()
	self:Push()
end

-- Where we placed our own fire. The campfire buff takes about a minute to show up,
-- so until then this is what says "you're at a campfire".
function Table:Placed()
	local x, y, mapID = HBD:GetPlayerZonePosition()
	if x then self.placed = { at = GetTime(), map = mapID, x = x, y = y } end
	if x and self:IsHosting() then self:RelightTable(mapID, x, y) end
end

-- The host placed a fresh campfire: the table follows it, and its clock starts over.
function Table:RelightTable(mapID, x, y)
	local t = self.current
	t.fire = { mapID, x, y }
	t.ends, t.closing = GetServerTime() + FIRE_LIFETIME, nil
	self.sawAura, self.noAuraSince = false, nil
	Bonfire:Print("New campfire down: your table moved to it and the timer restarted.")
	self:Push()
	ns.Beacon:Announce()
end

-- The campfire buff shows the fire is still burning. Once it has been seen at this table,
-- losing it for a while while still standing at the fire means the fire has gone out,
-- whatever the timer says. Skipped in combat, when buff data can't be read.
function Table:CheckFire()
	local t = self.current
	if not self:IsHosting() or t.state == "settling" or InCombatLockdown() then
		self.noAuraSince = nil
		return
	end
	if ns.CampfireBuff() then
		self.sawAura, self.noAuraSince = true, nil
		return
	end
	local d = self:DistanceToFire()
	if not self.sawAura or not d or d > self.FOLD_RANGE then
		self.noAuraSince = nil
		return
	end
	self.noAuraSince = self.noAuraSince or GetTime()
	if GetTime() - self.noAuraSince >= FIRE_GONE_AFTER and t.ends and GetServerTime() < t.ends then
		Bonfire:Print("The campfire has gone out.")
		t.ends = GetServerTime()
		self:Push()
	end
end

function Table:NearOwnFire()
	local f = self.placed
	if not f or GetTime() - f.at > FIRE_LIFETIME then return false end
	local x, y, mapID = HBD:GetPlayerZonePosition()
	if not x then return false end
	local d = HBD:GetZoneDistance(mapID, x, y, f.map, f.x, f.y)
	return d ~= nil and d <= self.FOLD_RANGE
end

-- The Light a fire button just used the kit. The first spell that lands in the
-- next few seconds is the campfire going down, so start the table where it is.
function Table:Armed()
	self.armedAt = GetTime()
end

function Table:OnCast(unit, spellID)
	if unit ~= "player" then return end
	if not self.armedAt then
		-- A campfire placed any other way (kit from the bags): open the window so the
		-- bet and the Host button are right there.
		local name = C_Spell.GetSpellName(spellID)
		if name and name:lower():find("campfire", 1, true) then
			self:Placed()
			if not self.current then ns.UI:Show() end
		end
		return
	end
	if GetTime() - self.armedAt > 12 then
		self.armedAt = nil
		return
	end
	self.armedAt = nil
	self:Placed()
	local name = C_Spell.GetSpellName(spellID) or "?"
	Bonfire:Printf("Campfire lit (%s). Your table is open.", name)
	self:Host(true)
end

-- Picks up the stake setting (amount, coin, for fun) between games.
function Table:SetStake()
	local t = self.current
	if not self:IsHosting() or t.state ~= "open" then return end
	local stake = ns.StakeCopper()
	if stake == 0 and t.market and Bets.HoldsGold(t) then
		return Bonfire:Print("Side bets have gold in them. Settle or call them off before switching to For fun.")
	end
	if stake > 0 and self:HasBots() and self:RealPlayers() > 1 then
		return Bonfire:Print("Practice players play on pretend gold, so a real bet can't be set while other players are seated. /bf dummy clear first.")
	end
	t.stake, t.practiceStake = stake, nil
	self:Push()
	ns.Beacon:Announce()
end

-- First click stops new games and queues everyone's credit for payout; the fire
-- goes out once everyone is paid back, or on a second click.
-- force: the host has walked away, so the table ends now and lists what's still owed
-- instead of waiting to pay everyone back.
function Table:Close(force)
	local t = self.current
	if not self:IsHosting() then return end
	if t.state == "playing" then self:Abandon() end
	if t.market then Bets.VoidAll(t) end
	if force then t.state = "settling" end
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
	self:Recap(self.current)
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
	if t.stake > 0 and self:HasBots() then return ns.Comm:Whisper(sender, "N", { r = "this is a practice table" }) end
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
	for _, name in ipairs(players) do
		if self:IsBot(name) then self.botLimit[name] = math.random(6, 14) end
	end
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
	local bust = Embers.Roll(self.game, value)
	if bust then
		Bonfire:Printf("Rolled a 1: the fire went out! Unbanked pots are lost.%s",
			self.game.over and "" or (" Round %d of %d."):format(self.game.round, self.game.rounds))
	end
	if self.game.over then self:Finish() end
	self:Push()
	self:BotTurns()
	C_Timer.After(ROLL_GAP, function() ns.UI:Refresh() end)
end

function Table:Finish()
	local t = self.current
	t.gs = Pack(self.game)
	t.winners = Embers.Winners(self.game)
	local dealt = t.committed
	t.share = Ledger.Settle(t, t.winners)
	Ledger.Record(t, dealt, t.winners, t.share)
	t.state = "open"
	self.game = nil
	ns.Beacon:Announce()
	self:BotsAfterGame()
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

-- Side bets ----------------------------------------------------------------------
-- The host runs the card. Players send bet requests by whisper; the host checks them and
-- keeps the real ledger, and everyone sees the same market in the table state.

-- What a player still has to trade the host: unpaid bets (plus the game stake, off a
-- market table it's just bets), less any credit the host already holds for them.
function Table:OwedTotal(t, name)
	local base = (t.market or name == t.host) and 0 or t.stake
	local unpaid = t.market and Bets.Unpaid(t.market, name) or 0
	return math.max(0, base + unpaid - Ledger.Balance(t, name))
end

-- Says why something was refused, in chat and in red in the window, since a click that
-- silently does nothing looks like a bug.
function Table:Refuse(msg)
	Bonfire:Print(msg)
	ns.UI:Notice(msg)
end

function Table:PlaceBet(ri, side, amount)
	local t = self.current
	if not t or not t.market then return end
	if t.stake == 0 then return self:Refuse("This table is for fun, so side bets are off.") end
	if self:IsHosting() then
		if not self:HasBots() then return self:Refuse("Hosts can't bet on their own table.") end
		local ok, err = Bets.Place(t, ns.Me(), ri, side, amount, true)  -- practice: pretend gold
		if not ok then return self:Refuse("Can't bet: " .. err .. ".") end
		return self:Push()
	end
	ns.Comm:Whisper(t.host, "BP", { r = ri, s = side, a = amount })
end

function Table:CancelBets(ri)
	local t = self.current
	if not t or not t.market then return end
	if self:IsHosting() then
		Bets.CancelUnpaid(t, ns.Me(), ri)
		return self:Push()
	end
	ns.Comm:Whisper(t.host, "BC", { r = ri })
end

function Table:OnBetPlace(d, sender)
	local t = self.current
	if not self:IsHosting() or not t.market or not tContains(t.seats, sender) then return end
	if t.stake == 0 then return ns.Comm:Whisper(sender, "BX", { r = "this table is for fun" }) end
	local ok, err = Bets.Place(t, sender, tonumber(d.r), tonumber(d.s), d.a, false)
	if not ok then return ns.Comm:Whisper(sender, "BX", { r = err }) end
	self:Push()
end

function Table:OnBetCancel(d, sender)
	local t = self.current
	if not self:IsHosting() or not t.market or not tContains(t.seats, sender) then return end
	Bets.CancelUnpaid(t, sender, tonumber(d.r))
	self:Push()
end

function Table:LockRound(ri)
	local t = self.current
	if not self:IsHosting() or not t.market then return end
	if Bets.Lock(t, ri) == false then return end
	Bonfire:Printf("Round %d: bets are locked.", ri)
	if Bets.Phase(t.market) == "payment" then
		Bonfire:Print("Every round is locked. Collect what everyone owes, then start the games.")
	end
	self:Push()
end

-- Locks every round still open (Shift-click on Lock bets).
function Table:LockAll()
	local t = self.current
	if not self:IsHosting() or not t.market then return end
	for i, r in ipairs(t.market.rounds) do
		if r.state == "open" then Bets.Lock(t, i) end
	end
	Bonfire:Print("Every round is locked. Collect what everyone owes, then start the games.")
	self:Push()
end

-- The payment window's Start games: unpaid bets are dropped and the rounds go live.
function Table:BeginGames()
	local t = self.current
	if not self:IsHosting() or not t.market then return end
	local dropped = Bets.Begin(t)
	Bonfire:Printf("The games begin.%s", dropped > 0 and (" %d unpaid bet%s dropped."):format(dropped, dropped == 1 and "" or "s") or "")
	self:Push()
end

function Table:ResolveRound(ri, side)
	local t = self.current
	if not self:IsHosting() or not t.market then return end
	local r = t.market.rounds[ri]
	local ok, summary = Bets.Resolve(t, ri, side)
	if not ok then return end
	if summary.refunded then
		Bonfire:Printf("Round %d: nobody bet against %s, so every bet is refunded.", ri, r.sides[side])
	else
		Bonfire:Printf("Round %d: %s wins. %s paid out as held credit%s.", ri, r.sides[side], ns.CoinString(summary.paidOut),
			summary.cut > 0 and (", host cut " .. ns.CoinString(summary.cut)) or "")
	end
	self:Push()
end

function Table:RemoveRound(ri)
	local t = self.current
	if not self:IsHosting() or not t.market then return end
	if not Bets.CanRemove(t, ri) then
		return Bonfire:Print("That round can't be removed: bets are paid on it. Call it off to refund them.")
	end
	Bets.RemoveRound(t, ri)
	if #t.market.rounds == 0 then t.market = nil end
	Bonfire:Printf("Round %d removed.", ri)
	self:Push()
end

function Table:VoidRound(ri)
	local t = self.current
	if not self:IsHosting() or not t.market then return end
	if Bets.Void(t, ri) then
		Bonfire:Printf("Round %d called off; every stake is back on its owner's balance.", ri)
		self:Push()
	end
end

-- Rounds close themselves when their timer runs out.
function Table:CheckBets()
	local t = self.current
	if not self:IsHosting() or not t.market then return end
	for i, r in ipairs(t.market.rounds) do
		if r.state == "open" and r.lockAt and GetServerTime() >= r.lockAt then self:LockRound(i) end
	end
end

function Table:AddRound(sides, seconds, game)
	local t = self.current
	if not self:IsHosting() then return Bonfire:Print("Host a table first (/bf host).") end
	if t.stake == 0 then return Bonfire:Print("Side bets use gold: switch the table to Gambling and Confirm a bet first.") end
	t.market = t.market or Bets.NewMarket(Bonfire.db.global.betCut)
	seconds = seconds or 120
	local title = table.concat(sides, " vs ")
	local ri = Bets.AddRound(t.market, title, sides, GetServerTime() + seconds, game)
	Bonfire:Printf("Round %d added (%s): %s. Bets close in %d seconds.", ri, game or "Custom", title, seconds)
	self:Push()
	return ri
end

-- The host's cut: 2, 5, 10 or 20 percent. Locked while anyone's money is in, so the odds
-- can't change under a bettor.
function Table:SetCut(pct)
	local t = self.current
	if not self:IsHosting() or not t.market then return end
	if Bets.HoldsGold(t) then return Bonfire:Print("The cut is locked while bets are in.") end
	t.market.cut = pct
	Bonfire.db.global.betCut = pct
	self:Push()
end

-- Six practice players and a card of three fights they bet pretend gold on, so the betting
-- window can be tried alone.
function Table:BetsDemo()
	if not self.current then self:Host(true) end  -- practice: no campfire needed
	local t = self.current
	if not self:IsHosting() then return end  -- Host already said what's missing
	if t.stake == 0 then
		-- The demo plays on pretend gold, so give the table a practice stake so bets are allowed.
		if self:RealPlayers() > 1 then return Bonfire:Print("Side bets use gold: switch the table to Gambling and Confirm a bet first.") end
		t.stake, t.practiceStake = 5 * ns.COIN_UNITS[2].copper, true
	end
	local bots = 0
	for _, name in ipairs(t.seats) do
		if self:IsBot(name) then bots = bots + 1 end
	end
	if bots < 6 then self:AddBots(6 - bots) end
	t.market = Bets.NewMarket(Bonfire.db.global.betCut)
	local matches = { { "Ratty", "Gopher", "Duel" }, { "Bunny", "Squirrel", "Deathroll" }, { "Roach", "Toad", "Dice" } }
	for i, m in ipairs(matches) do
		local ri = Bets.AddRound(t.market, m[1] .. " vs " .. m[2], { m[1], m[2] }, GetServerTime() + 90 * i, m[3])
		local bettors = 0
		for _, name in ipairs(t.seats) do
			local key = ns.NameKey(name)
			if self:IsBot(name) and key ~= ns.NameKey(m[1]) and key ~= ns.NameKey(m[2]) then
				-- Every other bot's bet starts unpaid, so Collect can be tried on it.
				bettors = bettors + 1
				Bets.Place(t, name, ri, math.random(2), math.random(1, 4) * 5 * 10000, bettors % 2 == 0)
			end
		end
	end
	Bonfire:Print("Demo card ready: three fights, practice players betting pretend gold. Some bets are unpaid: click Collect to try paying in.")
	ns.UI.view = "bets"
	self:Push()
	ns.UI:Show()
end

-- Practice players ---------------------------------------------------------------
-- /bf dummy adds pretend players so a whole table can be tried alone. They play
-- Embers on their own, "trade" instantly when the host clicks Collect or Pay, and
-- sometimes cash out. They play on pretend gold, so a gold table with practice
-- players is closed to real ones and kept off the map.
local BOT_NAMES = { "Ratty", "Gopher", "Bunny", "Squirrel", "Roach", "Toad", "Newt", "Crab", "Frog" }
local BOT_TAG = " (bot)"

function Table:IsBot(name)
	return type(name) == "string" and name:sub(-#BOT_TAG) == BOT_TAG
end

function Table:HasBots()
	local t = self.current
	for _, name in ipairs(t and t.seats or {}) do
		if self:IsBot(name) then return true end
	end
	return false
end

function Table:RealPlayers()
	local t, n = self.current, 0
	for _, name in ipairs(t and t.seats or {}) do
		if not self:IsBot(name) then n = n + 1 end
	end
	return n
end

function Table:AddBots(count)
	local t = self.current
	if not self:IsHosting() then return Bonfire:Print("Host a table first (/bf host), then add practice players.") end
	if t.state ~= "open" then return Bonfire:Print("Add practice players between games.") end
	if t.stake > 0 and self:RealPlayers() > 1 then
		return Bonfire:Print("Real players are seated at a gold table, so practice players can't join it.")
	end
	local added = 0
	for _, base in ipairs(BOT_NAMES) do
		local name = base .. BOT_TAG
		if added >= count or #t.seats >= t.maxSeats then break end
		if not tContains(t.seats, name) then
			t.seats[#t.seats + 1] = name
			added = added + 1
			C_Timer.After(added * 0.7, function() self:BotPayIn(name) end)
		end
	end
	if added == 0 then return Bonfire:Print("The table is full.") end
	Bonfire:Printf("%d practice player%s sat down. They play on pretend gold.", added, added == 1 and "" or "s")
	self:Push()
	ns.Beacon:Announce()
end

function Table:ClearBots()
	local t = self.current
	if not self:IsHosting() or t.state == "playing" then return Bonfire:Print("Clear practice players between games.") end
	for i = #t.seats, 1, -1 do
		local name = t.seats[i]
		if self:IsBot(name) then
			table.remove(t.seats, i)
			t.balances[name], t.cashout[name], t.left[name] = nil, nil, nil
		end
	end
	self:Push()
	ns.Beacon:Announce()
end

-- The host clicked Collect or Pay on a bot: the trade happens instantly.
function Table:BotTrade(name)
	local t = self.current
	if not self:IsHosting() then return end
	for _, p in ipairs(Ledger.Payouts(t)) do
		if p[1] == name then return self:OnTradeComplete(name, -p[2]) end
	end
	local owed = self:OwedTotal(t, name)  -- unpaid side bets
	if owed > 0 then return self:OnTradeComplete(name, owed) end
	self:BotPayIn(name)
end

function Table:BotPayIn(name)
	local t = self.current
	if not t or not self:IsHosting() or not tContains(t.seats, name) then return end
	local owes = Ledger.Owes(t, name)
	if owes > 0 then self:OnTradeComplete(name, owes) end
end

-- Bots bank once their pot passes their own comfort level.
function Table:BotTurns()
	local t, g = self.current, self.game
	if not self:IsHosting() or t.state ~= "playing" or not g then return end
	for _, name in ipairs(g.order) do
		local p = g.players[name]
		if self:IsBot(name) and p.stoking and p.pot >= (self.botLimit[name] or 10) then
			C_Timer.After(0.4 + math.random() * 1.6, function()
				local now = self.game
				if self.current == t and now and t.state == "playing" and now.players[name] and now.players[name].stoking then
					self:OnBank(name)
				end
			end)
		end
	end
end

-- After a game: bots that lost pay in again, and some winners cash out.
function Table:BotsAfterGame()
	local t = self.current
	for i, name in ipairs(t.seats) do
		if self:IsBot(name) then
			C_Timer.After(1 + i * 0.6, function()
				if self.current ~= t or t.state ~= "open" or not tContains(t.seats, name) then return end
				if Ledger.Balance(t, name) > 0 and math.random() < 0.4 then
					t.cashout[name] = true
					self:Push()
				else
					self:BotPayIn(name)
				end
			end)
		end
	end
end

-- End-of-table summary: the record, and who owes whom. The host sees everyone; a player
-- sees their own line and what the host is still holding for them.
function Table:Recap(t)
	if not t then return end
	local function record(name)
		local r = t.tally and t.tally[name]
		if not r or r.w + r.l == 0 then return end
		local text = ("%s: %d won, %d lost"):format(ns.Short(name), r.w, r.l)
		if t.stake > 0 then text = text .. ", net " .. ns.SignedCoins(r.net) end
		return text
	end
	if t.host == ns.Me() then
		local names = {}
		for name in pairs(t.tally or {}) do names[#names + 1] = name end
		table.sort(names)
		for _, name in ipairs(names) do
			local text = record(name)
			if text then
				local owed = Ledger.Balance(t, name)
				if owed > 0 then text = text .. ", you owe them " .. ns.Coins(owed) end
				Bonfire:Print(text)
			end
		end
	else
		local text = record(ns.Me())
		if text then
			local held = Ledger.Balance(t, ns.Me())
			if held > 0 then text = text .. (", %s holds %s for you"):format(ns.Short(t.host), ns.Coins(held)) end
			Bonfire:Print("Your table: " .. text)
		end
	end
end

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
		if name ~= t.host and not self:IsBot(name) then return name end
	end
end

-- A host who leaves while the fire still burns passes the table to whoever sat down
-- first. Gold can't change hands, so a table holding anyone's credit closes instead.
function Table:CanPass()
	local t = self.current
	if not t or not self:IsHosting() or t.state == "settling" or not self:NextHost() then return false end
	if t.ends and GetServerTime() >= t.ends then return false end
	return Ledger.Empty(t) and not Bets.HoldsGold(t)
end

function Table:PassHost(left)
	local t = self.current
	if not self:CanPass() then return self:Close(left) end
	if t.state == "playing" then self:Abandon() end
	local queue = {}
	for _, name in ipairs(t.seats) do
		if name ~= t.host and not self:IsBot(name) then queue[#queue + 1] = name end
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
		return self:Close(true)
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
		return self:OwedTotal(t, ns.Me())
	end
end

-- copper > 0: we received it from partner.
function Table:OnTradeComplete(partner, copper)
	local t = self.current
	if not t then return end
	if self:IsHosting() then
		if not tContains(t.seats, partner) and not t.left[partner] then return end
		Ledger.Credit(t, partner, copper)
		if t.market then Bets.Fund(t) end
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
	self:Recap(t)
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
		self:Recap(t)
		local balance = Ledger.Balance(t, ns.Me())
		if balance > 0 then Bonfire:Printf("|cffff6666They still held %s for you.|r", ns.Coins(balance)) end
		ns.UI:Refresh()
	end
end

function Table:Heard(sender)
	if self.current and self.current.host == sender then self.current.heard = GetTime() end
end

function Table:Watchdog()
	self:CheckFire()
	self:CheckExpiry()
	self:CheckBets()
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

ns.AddCommand("burn", "<seconds> - host only: set how long your fire has left (for testing)", function(arg)
	local t, secs = Table.current, tonumber(arg)
	if not t or not Table:IsHosting() or not secs then return Bonfire:Print("usage: /bf burn <seconds>, while hosting a table") end
	t.ends, t.closing = GetServerTime() + secs, nil
	Table:Push()
end)

ns.AddCommand("dummy", "[n|clear] - practice: seat n pretend players at your table (default 1)", function(arg)
	arg = strtrim(arg or ""):lower()
	if arg == "clear" then return Table:ClearBots() end
	Table:AddBots(math.max(1, math.floor(tonumber(arg) or 1)))
end)

ns.AddCommand("bets", "demo | add <A> <B> | close - side bets: try a practice card, add a round, or end betting", function(arg)
	local cmd, rest = strtrim(arg or ""):match("^(%S*)%s*(.-)$")
	cmd = cmd:lower()
	if cmd == "demo" then return Table:BetsDemo() end
	if cmd == "add" then
		local a, b = rest:match("^(%S+)%s+(%S+)$")
		if not a then return Bonfire:Print("usage: /bf bets add <A> <B>") end
		return Table:AddRound({ a, b }, nil, "Custom")
	end
	if cmd == "close" then
		local t = Table.current
		if not Table:IsHosting() or not t.market then return end
		Bets.VoidAll(t)
		t.market = nil
		if t.practiceStake then t.stake, t.practiceStake = 0, nil end  -- back to For fun
		return Table:Push()
	end
	ns.UI.view = "bets"
	ns.UI:Show()
end)
