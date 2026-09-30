local _, ns = ...
local Bonfire = ns.Bonfire
local Rep = ns.Rep

-- The Honest Broker's legwork. Every minute your addon says a quiet hello to anyone within /say
-- range; when two Bonfire users meet (passing each other, or sitting at the same table) they
-- whisper each other a small digest of what they know about hosts, at most every half hour per
-- person. It also keeps the payout clock on gold a host still holds for you, and answers
-- /bf rep. The rules are in Reputation.lua.
local Broker = {
	HELLO_EVERY = 60,    -- seconds between hellos
	AGAIN_AFTER = 1800,  -- seconds before trading digests with the same player again
	GAP = 20,            -- seconds between any two digests we send, so a crowd can't flood the whisper limit
	sentTo = {},
}
ns.Broker = Broker

function Broker:Store()
	local db = Bonfire.db.global
	db.rep = db.rep or Rep.New()
	return db.rep
end

function Broker:Enable()
	ns.Comm.On("HI", function(_, sender, distribution)
		if distribution == "SAY" then self:Met(sender) end
	end)
	ns.Comm.On("RD", function(d, sender) self:OnDigest(d, sender) end)
	Bonfire:ScheduleRepeatingTimer(function() self:Tick() end, self.HELLO_EVERY)
	C_Timer.After(30, function() Rep.Prune(self:Store(), GetServerTime()) end)
end

function Broker:Tick()
	ns.Comm:Say("HI", {})
	if Rep.CheckOwed(self:Store(), ns.Me(), GetServerTime()) then ns.UI:Refresh() end
end

-- We met another Bonfire user: send them what we know, unless we did lately.
function Broker:Met(who)
	if not who or who == ns.Me() or ns.Table:IsBot(who) then return end
	local last = self.sentTo[who]
	if last and GetTime() - last < self.AGAIN_AFTER then return end
	local wait = self.GAP - (GetTime() - (self.lastSent or -self.GAP))
	if wait > 0 then
		if not self.later then
			self.later = true
			C_Timer.After(wait, function()
				self.later = false
				self:Met(who)
			end)
		end
		return
	end
	self.sentTo[who], self.lastSent = GetTime(), GetTime()
	-- An empty digest still goes: it tells them to answer with theirs.
	ns.Comm:Whisper(who, "RD", { d = Rep.Digest(self:Store(), ns.Me(), GetServerTime(), Rep.DIGEST) })
end

function Broker:OnDigest(d, sender)
	local recs = Rep.Unpack(d.d)
	if not recs then return end
	local store, me, now, changed = self:Store(), ns.Me(), GetServerTime(), false
	for _, rec in ipairs(recs) do
		if Rep.Merge(store, rec, sender, me, now) then changed = true end
	end
	if changed then ns.UI:Refresh() end
	self:Met(sender)  -- answer with ours
end

-- Your own word about a host, from the rating prompt.
function Broker:Rate(host, fields)
	Rep.Set(self:Store(), ns.Me(), host, fields, GetServerTime())
end

-- The host holds copper for you as you leave or cash out: the payout clock starts.
function Broker:Owed(host, copper)
	Rep.Owe(self:Store(), host, copper, GetServerTime())
end

-- A trade paid you: if it's a host that owed you, that's on record.
function Broker:Received(partner, copper)
	local host, paid = Rep.Received(self:Store(), ns.Me(), partner, copper, GetServerTime())
	-- At the table the trade message already says so; after you've left, say it was noted.
	if host and not ns.Table.current then
		Bonfire:Printf("%s paid you %s from their table. Noted for the Honest Broker.", ns.Short(host), ns.Coins(paid))
	end
end

function Broker:Summary(host)
	return Rep.Summary(self:Store(), host)
end

-- A host's badge in colour, e.g. "|cff66ff66Trusted, quick|r".
function Broker:Badge(host)
	local text, color = Rep.Label(self:Summary(host))
	return ("|cff%s%s|r"):format(color, text)
end

-- The badge plus how many players it rests on, for tooltips and /bf rep.
function Broker:Describe(host)
	local s = self:Summary(host)
	if s.raters == 0 then return self:Badge(host) .. " |cff999999(nobody's rated them yet)|r" end
	return ("%s |cff999999(%d player%s)|r"):format(self:Badge(host), s.raters, s.raters == 1 and "" or "s")
end

local function Details(s)
	local lines = {}
	lines[#lines + 1] = ("Paid out fair: %d yes, %d no.  Unpaid reports: %d%s."):format(s.fair, s.unfair, s.unpaid,
		s.overdue > 0 and (" (" .. ns.CoinString(s.overdue) .. " overdue)") or "")
	if s.paceVotes > 0 then
		lines[#lines + 1] = ("Pace: %d vote%s, %s."):format(s.paceVotes, s.paceVotes == 1 and "" or "s",
			Rep.Pace(s) or "not enough to say yet")
	end
	if s.paid > 0 then lines[#lines + 1] = ("Paid out on record: %s."):format(ns.CoinString(s.paid)) end
	return lines
end

ns.AddCommand("rep", "[name] | paid <name> - Honest Broker: what players say about a host (you, if no name)", function(arg)
	arg = strtrim(arg or "")
	local store = Broker:Store()
	local paidName = arg:match("^[Pp]aid%s+(.+)$")
	if paidName then
		local host = Rep.Find(store, paidName) or ns.FullName(paidName)
		Rep.Clear(store, ns.Me(), host, GetServerTime())
		return Bonfire:Printf("Noted: %s paid you. Nothing is owed any more.", ns.Short(host))
	end
	if arg == "practice" then return ns.UI:AskRating("Practice host (bot)") end  -- try the prompt alone
	local host = arg == "" and ns.Me() or Rep.Find(store, arg)
	if not host then
		for name in pairs(ns.Beacon.fires) do
			if ns.NameKey(name) == ns.NameKey(arg) then host = name end
		end
	end
	if not host then return Bonfire:Printf("Nobody has said anything about %s yet.", arg) end
	Bonfire:Printf("%s: %s", host == ns.Me() and "You as a host" or ns.Short(host), Broker:Describe(host))
	for _, line in ipairs(Details(Broker:Summary(host))) do Bonfire:Print("  " .. line) end
	local known = 0
	for _ in pairs(store.hosts) do known = known + 1 end
	if arg == "" then Bonfire:Printf("You know about %d host%s. It grows as you pass other Bonfire users.", known, known == 1 and "" or "s") end
end)
