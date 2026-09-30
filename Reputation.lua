local _, ns = ...

-- The Honest Broker's rules: what players say about the hosts they've sat with, and whether
-- those hosts paid out. Each player keeps one record per host they've been at the table of
-- ("my view of Ratty"), their newest word replacing older. Records travel from player to player
-- when they meet (see Broker.lua), so word spreads across the realm. A host's badge comes from
-- how many different players back it up; one player saying the same thing twice counts once.
--
-- store = { hosts = { [host] = { [rater] = rec } }, owed = { [host] = { c = copper, since = time } } }
-- rec = { t = trust (1 fair, -1 not), p = pace (1 quick, 2 steady, 3 slow), pd = copper the host
--         paid out, up = copper overdue, at = server time, d = true when it came from the rater
--         (ours, or told to us by the player who gave it) rather than passed along }
-- Names are "Name-Realm" as comms report them. Pure (no WoW API) so tests/run.lua can load it.
local Rep = {
	MIN_RATERS = 3,        -- different players who must have rated a host before it gets a badge
	GRACE = 600,           -- seconds a host has to pay out what it holds before that counts as unpaid
	EXPIRE = 30 * 86400,   -- records older than this are forgotten
	KEEP = 1500,           -- most records kept
	DIGEST = 12,           -- records passed on at each handshake
	PACE = { "quick", "steady", "slow" },
}
ns.Rep = Rep

-- Different APIs give different forms of the same name, so trades match on the first word.
local function Key(name)
	return type(name) == "string" and (name:match("^[^%s%-]+") or name):lower() or nil
end

-- Practice players never rate and are never rated.
local function IsBot(name)
	return name:find("(bot)", 1, true) ~= nil
end

function Rep.New()
	return { hosts = {}, owed = {} }
end

local function Own(store, me, host)
	local raters = store.hosts[host]
	if not raters then
		raters = {}
		store.hosts[host] = raters
	end
	local rec = raters[me]
	if not rec then
		rec = { at = 0 }
		raters[me] = rec
	end
	return rec
end

-- Our own word about a host: trust (t), pace (p) or overdue copper (up).
function Rep.Set(store, me, host, fields, now)
	if host == me then return end
	local rec = Own(store, me, host)
	for field, value in pairs(fields) do rec[field] = value end
	if rec.up == 0 then rec.up = nil end
	rec.at, rec.d = now, true
	return rec
end

local function Valid(rec)
	return (rec.t == nil or rec.t == 1 or rec.t == -1)
		and (rec.p == nil or rec.p == 1 or rec.p == 2 or rec.p == 3)
		and (rec.pd == nil or (type(rec.pd) == "number" and rec.pd >= 0))
		and (rec.up == nil or (type(rec.up) == "number" and rec.up >= 0))
end

-- A record heard from another player (sender). The rater's own word beats hearsay; otherwise
-- the newest wins. Nobody speaks for us, hosts don't rate themselves, and a record stamped in
-- the future or past its expiry is ignored. Returns true if it changed what we know.
function Rep.Merge(store, rec, sender, me, now)
	if type(rec) ~= "table" or type(rec.h) ~= "string" or type(rec.r) ~= "string" or type(rec.at) ~= "number" then return false end
	local host, rater = rec.h, rec.r
	if rater == me or host == rater or IsBot(host) or IsBot(rater) or not Valid(rec) then return false end
	if rec.at > now + 300 or now - rec.at > Rep.EXPIRE then return false end
	local direct = sender == rater
	local raters = store.hosts[host]
	local old = raters and raters[rater]
	if old then
		if old.d and not direct then return false end
		if rec.at <= old.at and (old.d or not direct) then return false end
	end
	if not raters then
		raters = {}
		store.hosts[host] = raters
	end
	raters[rater] = { t = rec.t, p = rec.p, pd = rec.pd, up = rec.up ~= 0 and rec.up or nil, at = rec.at, d = direct or nil }
	return true
end

-- Everything known about one host, from everyone but the host.
function Rep.Summary(store, host)
	local s = { raters = 0, fair = 0, unfair = 0, unpaid = 0, overdue = 0, paid = 0, good = 0, bad = 0, paceVotes = 0, paceSum = 0 }
	for rater, rec in pairs(store.hosts[host] or {}) do
		if rater ~= host and (rec.t or rec.p or rec.pd or rec.up) then
			s.raters = s.raters + 1
			if rec.t == 1 then s.fair = s.fair + 1 end
			if rec.t == -1 then s.unfair = s.unfair + 1 end
			if rec.up then s.unpaid, s.overdue = s.unpaid + 1, s.overdue + rec.up end
			s.paid = s.paid + (rec.pd or 0)
			local bad = rec.t == -1 or rec.up ~= nil
			if bad then
				s.bad = s.bad + 1
			elseif rec.t == 1 or (rec.pd or 0) > 0 then
				s.good = s.good + 1
			end
			if rec.p then s.paceVotes, s.paceSum = s.paceVotes + 1, s.paceSum + rec.p end
		end
	end
	return s
end

-- "new" until enough players have rated; "avoid" once several say unpaid or unfair and they
-- outnumber the good reports; "mixed" when more than a quarter are bad; otherwise "trusted".
function Rep.Badge(s)
	if s.raters < Rep.MIN_RATERS then return "new" end
	if s.bad >= Rep.MIN_RATERS and s.bad >= s.good then return "avoid" end
	if s.bad > 0 and s.bad * 4 > s.raters then return "mixed" end
	return "trusted"
end

-- "quick", "steady" or "slow", once enough players have said.
function Rep.Pace(s)
	if s.paceVotes < Rep.MIN_RATERS then return end
	local avg = s.paceSum / s.paceVotes
	return avg <= 1.6 and "quick" or avg >= 2.4 and "slow" or "steady"
end

local COLOR = { new = "999999", trusted = "66ff66", mixed = "ffcc33", avoid = "ff6666" }

-- A short label and its colour: "Trusted, quick", "Mixed", "Avoid: 3 unpaid", "New, 1 unpaid".
function Rep.Label(s)
	local badge, pace = Rep.Badge(s), Rep.Pace(s)
	local worst = s.unpaid >= s.unfair and ("%d unpaid"):format(s.unpaid) or ("%d say unfair"):format(s.unfair)
	if badge == "avoid" then return "Avoid: " .. worst, COLOR.avoid end
	if badge == "new" then
		if s.bad > 0 then return "New, " .. worst, COLOR.mixed end
		return "New", COLOR.new
	end
	local text = badge == "trusted" and "Trusted" or "Mixed"
	return pace and (text .. ", " .. pace) or text, COLOR[badge]
end

-- We left, or cashed out, with the host holding copper for us: the payout clock starts.
function Rep.Owe(store, host, copper, now)
	if copper <= 0 or IsBot(host) then return end
	local o = store.owed[host]
	store.owed[host] = { c = copper, since = o and o.since or now }
end

-- A trade paid us copper. If it came from a host that owes us, that's a payout on record.
-- Returns the host and how much counted.
function Rep.Received(store, me, partner, copper, now)
	local key = Key(partner)
	if not key or copper <= 0 then return end
	for host, o in pairs(store.owed) do
		if Key(host) == key then
			local paid = math.min(copper, o.c)
			o.c = o.c - paid
			if o.c <= 0 then store.owed[host] = nil end
			local rec = Own(store, me, host)
			rec.pd = (rec.pd or 0) + paid
			if rec.up then rec.up = rec.up > paid and rec.up - paid or nil end
			rec.at, rec.d = now, true
			return host, paid
		end
	end
end

-- Anything still owed after the grace period goes on record as unpaid (and comes off again
-- once it's paid). Returns true if a record changed.
function Rep.CheckOwed(store, me, now)
	local changed = false
	for host, o in pairs(store.owed) do
		if now - o.since >= Rep.GRACE then
			local rec = Own(store, me, host)
			if rec.up ~= o.c then
				Rep.Set(store, me, host, { up = o.c }, now)
				changed = true
			end
		end
	end
	return changed
end

-- We were paid some other way (gold handed over outside Bonfire): nothing is owed any more.
function Rep.Clear(store, me, host, now)
	store.owed[host] = nil
	local raters = store.hosts[host]
	if raters and raters[me] and raters[me].up then Rep.Set(store, me, host, { up = 0 }, now) end
end

-- The host we know by this name (any form of it), or nil.
function Rep.Find(store, name)
	if store.hosts[name] then return name end
	local key = Key(name)
	for host in pairs(store.hosts) do
		if Key(host) == key then return host end
	end
end

-- What we pass on at a handshake: our own records first, then the freshest we've heard, packed
-- as a list of names and rows of numbers so each name goes over the wire once.
function Rep.Digest(store, me, now, limit)
	local list = {}
	for host, raters in pairs(store.hosts) do
		for rater, rec in pairs(raters) do
			if now - rec.at <= Rep.EXPIRE and host ~= rater and not IsBot(host) and not IsBot(rater) then
				list[#list + 1] = { h = host, r = rater, rec = rec, own = rater == me }
			end
		end
	end
	table.sort(list, function(a, b)
		if a.own ~= b.own then return a.own end
		return a.rec.at > b.rec.at
	end)
	local names, index, rows = {}, {}, {}
	local function Ref(name)
		if not index[name] then
			names[#names + 1] = name
			index[name] = #names
		end
		return index[name]
	end
	for i = 1, math.min(limit, #list) do
		local e, rec = list[i], list[i].rec
		rows[i] = { Ref(e.h), Ref(e.r), rec.t or 0, rec.p or 0, rec.pd or 0, rec.up or 0, rec.at }
	end
	return { n = names, r = rows }
end

-- A digest back into records, or nil if it's malformed. Reads at most `max` rows.
function Rep.Unpack(d, max)
	if type(d) ~= "table" or type(d.n) ~= "table" or type(d.r) ~= "table" then return end
	local recs = {}
	for i = 1, math.min(#d.r, max or Rep.DIGEST * 2) do
		local row = d.r[i]
		if type(row) == "table" then
			local host, rater = d.n[row[1]], d.n[row[2]]
			local t, p, pd, up, at = tonumber(row[3]), tonumber(row[4]), tonumber(row[5]), tonumber(row[6]), tonumber(row[7])
			if type(host) == "string" and type(rater) == "string" and t and p and pd and up and at then
				recs[#recs + 1] = { h = host, r = rater, t = t ~= 0 and t or nil, p = p ~= 0 and p or nil,
					pd = pd ~= 0 and pd or nil, up = up ~= 0 and up or nil, at = at }
			end
		end
	end
	return recs
end

-- Forgets expired records, then the oldest passed-along ones if there are too many.
function Rep.Prune(store, now)
	local count, relayed = 0, {}
	for host, raters in pairs(store.hosts) do
		for rater, rec in pairs(raters) do
			if now - rec.at > Rep.EXPIRE then
				raters[rater] = nil
			else
				count = count + 1
				if not rec.d then relayed[#relayed + 1] = { host, rater, rec.at } end
			end
		end
		if next(raters) == nil then store.hosts[host] = nil end
	end
	table.sort(relayed, function(a, b) return a[3] < b[3] end)
	for i = 1, math.min(#relayed, count - Rep.KEEP) do
		local e = relayed[i]
		store.hosts[e[1]][e[2]] = nil
		if next(store.hosts[e[1]]) == nil then store.hosts[e[1]] = nil end
	end
end
