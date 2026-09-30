local _, ns = ...
local Bonfire = ns.Bonfire

-- Random lines and emotes for the table. Your own character says a line in /say and does an
-- emote, but only on one of your own clicks in Bonfire (Start, Roll, Bank, Pick, Cash out, Pay,
-- Join), which is when the game lets an addon speak for you. A moment that comes up between
-- clicks (a game ending, a streak, a roll) waits for your next click, but only for a short
-- while (EXPIRE), so a line is never said long after the moment it's about. A reaction to a
-- roll is never said on a Roll click: that click makes a new roll, and the line would sound
-- like it's about that one ("Big number, big smile" as a 1 lands). Practice players talk in the
-- Bonfire tab when something happens. All of it is switched off by /bf chat.
local Quips = {
	CHANCE = {
		start = 0.4,     -- the host pressed Start
		finish = 0.6,    -- a game ended (streaks always speak)
		rolled = 0.1,    -- your own Embers roll was high (5-6) or low (2)
		bust = 0.35,     -- your own Embers roll was a 1
		cashout = 0.6,   -- you pressed Cash out
		click = 0.08,    -- any other click in Bonfire, Roll and Pick included
		bot = 0.5,       -- a practice player reacts to an event
	},
	-- Seconds a waiting line stays good for; after that it's dropped unsaid.
	EXPIRE = { roll_high = 8, roll_low = 8, bust = 8, win = 30, lose = 30, streak_win = 30, streak_lose = 30 },
	ROLL_REACTION = { roll_high = true, roll_low = true, bust = true },  -- never said on a Roll click
	STREAK = 3,      -- wins or losses in a row that count as a streak
	MIN_GAP = 8,     -- seconds between your own quips
}
ns.Quips = Quips

Quips.lines = {
	start = { "Let's light this fire!", "Fortune favors the bold.", "May the dice be kind.", "Everyone ready? Here we go.", "Stoke the flames!" },
	win = { "That's how it's done!", "Sweet, sweet victory.", "The fire loves me.", "Better luck next time, friends.", "Beginner's luck? I think not." },
	lose = { "Well, that stung.", "The fire has other plans for me.", "Next round is mine.", "I'll get it back.", "Ouch. Just ouch." },
	streak_win = { "I can't stop winning!", "The flames are on my side today.", "Is this luck or skill?", "Hot streak, don't touch me!" },
	streak_lose = { "Is the fire mocking me?", "Three in a row. Really?", "I'm officially cursed.", "Somebody check the dice." },
	roll_high = { "Now THAT'S a roll!", "Feeling lucky!", "Big number, big smile." },
	roll_low = { "Oof, small one.", "The dice hate me.", "Could've been worse. Maybe." },
	bust = { "It sizzled out!", "Not the fire!", "And there goes the pot." },
	cashout = { "Pleasure doing business.", "Thank you kindly!", "Until next time, friends." },
	ambient = { "Nothing like a fire on a cold night.", "Anyone else smell marshmallows?", "This is the life.", "Who's up for another round?", "Watch the sparks!", "Don't stand too close to the fire." },
}

-- Emote tokens for DoEmote, by kind. A kind with none is words only.
Quips.emotes = {
	win = { "CHEER", "CLAP", "LAUGH" },
	lose = { "SIGH", "SHRUG", "LAUGH", "FACEPALM" },
	streak_win = { "CHEER", "FLEX", "CLAP" },
	streak_lose = { "CRY", "SIGH", "FACEPALM" },
	roll_high = { "CHEER" }, roll_low = { "SIGH" }, bust = { "CRY" },
	cashout = { "BOW" },
}

-- A random line of that kind, skipping any in `recent` (a set) unless that leaves nothing.
function Quips.Pick(kind, rand, recent)
	local list = Quips.lines[kind]
	if not list then return end
	local choices = {}
	for _, line in ipairs(list) do
		if not (recent and recent[line]) then choices[#choices + 1] = line end
	end
	if #choices == 0 then choices = list end
	return choices[rand(1, #choices)]
end

-- "streak_win" / "streak_lose" once you're STREAK or more in a row (streak is + for wins).
function Quips.StreakKind(streak)
	streak = streak or 0
	if streak >= Quips.STREAK then return "streak_win" end
	if streak <= -Quips.STREAK then return "streak_lose" end
end

-- A roll in the top fifth of the die is high, the bottom fifth low.
function Quips.RollKind(value, max)
	if not max or max < 5 then return end
	local fraction = (value - 1) / (max - 1)
	if fraction >= 0.8 then return "roll_high" end
	if fraction <= 0.2 then return "roll_low" end
end

function Quips:Enabled()
	return Bonfire.db.global.chatTab
end

function Quips:Remember(line)
	self.recent = self.recent or {}
	self.recentOrder = self.recentOrder or {}
	self.recent[line] = true
	table.insert(self.recentOrder, line)
	if #self.recentOrder > 6 then self.recent[table.remove(self.recentOrder, 1)] = nil end
end

function Quips:Ready()
	return GetTime() - (self.last or -100) >= self.MIN_GAP
end

-- Your character says a line in /say and does an emote. Only ever called from a click.
function Quips:Speak(kind)
	if not self:Enabled() then return end
	local line = self.Pick(kind, math.random, self.recent)
	if not line then return end
	local list = self.emotes[kind]
	self:Remember(line)
	self.last = GetTime()
	pcall(SendChatMessage, line, "SAY")
	if list then pcall(DoEmote, list[math.random(#list)]) end
end

-- Something worth saying happened: it's said on your next click, if that comes soon enough.
function Quips:Queue(kind)
	if not self:Enabled() or not self:Ready() then return end
	self.pending, self.pendingAt = kind, GetTime()
end

-- Called from every button click that can carry speech; context names the click ("roll",
-- "cashout", or nil). A waiting quip goes first unless it's gone stale, or it's a roll reaction
-- and this is a Roll click (it keeps for a following click instead). Otherwise this kind of
-- click may have a chance of its own, and any click a small one.
function Quips:Click(context)
	if not self:Enabled() then return end
	local kind = self.pending
	if kind and GetTime() - (self.pendingAt or 0) > (self.EXPIRE[kind] or 30) then
		kind, self.pending = nil, nil
	end
	if kind and not (context == "roll" and self.ROLL_REACTION[kind]) then
		self.pending = nil
		return self:Speak(kind)
	end
	if not self:Ready() then return end
	local chance = self.CHANCE[context or "click"] or self.CHANCE.click
	if math.random() < chance then self:Speak(self.lines[context or ""] and context or "ambient") end
end

function Quips:BotSay(name, kind)
	local line = self.Pick(kind, math.random, self.botRecent)
	if not line then return end
	Bonfire:Printf("|cffff9933%s:|r %s", ns.Short(name), line)
end

local function Bots(t)
	local list = {}
	for _, name in ipairs(t.seats) do
		if ns.Table:IsBot(name) then list[#list + 1] = name end
	end
	return list
end

-- The host pressed Start: maybe say something, and maybe a practice player does.
function Quips:OnStart(t)
	if not self:Enabled() then return end
	if self.pending then
		self:Click()
	elseif self:Ready() and math.random() < self.CHANCE.start then
		self:Speak("start")
	end
	local bots = Bots(t)
	if #bots > 0 and math.random() < self.CHANCE.bot then
		self:BotSay(bots[math.random(#bots)], "start")
	end
end

-- A game ended. A streak always gets a line and an emote (on your next click), otherwise
-- sometimes a win or loss line. Practice players react right away.
function Quips:OnFinish(t)
	if not self:Enabled() or not t.gs then return end
	local me = ns.Me()
	local played = false
	for _, p in ipairs(t.gs.p or {}) do
		if p[1] == me then played = true end
	end
	for _, name in ipairs(t.gs.order or {}) do
		if name == me then played = true end
	end
	if played then
		local won = tContains(t.winners or {}, me)
		local streak = self.StreakKind(t.tally and t.tally[me] and t.tally[me].streak)
		if streak then
			self:Queue(streak)
		elseif math.random() < self.CHANCE.finish then
			self:Queue(won and "win" or "lose")
		end
	end
	if ns.Table:IsHosting() then
		local spoke = 0
		for _, name in ipairs(Bots(t)) do
			if spoke < 2 and math.random() < self.CHANCE.bot then
				spoke = spoke + 1
				local r = t.tally and t.tally[name]
				local kind = (r and self.StreakKind(r.streak)) or (tContains(t.winners or {}, name) and "win" or "lose")
				self:BotSay(name, kind)
			end
		end
	end
end

-- Chat lines: your own Embers roll may earn a quip (a 1 is a "bust"), said on your next click
-- that isn't another Roll. Only Embers: there a big number is good for everyone still stoking,
-- while in The Odd Man Out the number itself is neither good nor bad.
function Quips:OnSystemMessage(msg)
	local t = ns.Table.current
	if not t or t.state ~= "playing" or t.game ~= "embers" or not self:Enabled() then return end
	local who, value, low, high = ns.ParseRoll(msg)
	if not who or low ~= 1 or ns.NameKey(who) ~= ns.NameKey(UnitName("player")) then return end
	if value == 1 then
		if math.random() < self.CHANCE.bust then self:Queue("bust") end
		return
	end
	local kind = self.RollKind(value, high)
	if kind and math.random() < self.CHANCE.rolled then self:Queue(kind) end
end

function Quips:Enable()
	ns.OnEvent("CHAT_MSG_SYSTEM", function(_, msg) self:OnSystemMessage(msg) end)
end

ns.AddCommand("quip", "[kind] - try a line and emote (start win lose streak_win streak_lose roll_high roll_low bust cashout ambient)", function(arg)
	arg = strtrim(arg or ""):lower()
	if arg == "" then arg = "start" end
	if not Quips.lines[arg] then return Bonfire:Print("No such kind of line.") end
	if not Quips:Enabled() then return Bonfire:Print("Quips are off. /bf chat turns them on.") end
	Quips:Speak(arg)  -- typing the command counts as a click
end)
