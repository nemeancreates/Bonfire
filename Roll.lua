local _, ns = ...

-- Public games trust only server /roll results. They arrive as CHAT_MSG_SYSTEM
-- text built from the localized RANDOM_ROLL_RESULT format ("%s rolls %d (%d-%d)"
-- on enUS), so the match pattern is built from that format to work on any locale.
function ns.RollPattern(fmt)
	fmt = fmt:gsub("%%%d+%$", "%%")                     -- "%1$s" -> "%s"
	fmt = fmt:gsub("[%(%)%.%+%-%*%?%[%]%^%$]", "%%%0")  -- escape pattern magic
	fmt = fmt:gsub("%%s", "(.+)"):gsub("%%d", "(%%d+)")
	return "^" .. fmt .. "$"
end

local defaultPattern

-- Returns who, roll, low, high for a roll line, or nil for any other text.
function ns.ParseRoll(msg, pattern)
	if type(msg) ~= "string" or (issecretvalue and issecretvalue(msg)) then return end
	if not pattern then
		defaultPattern = defaultPattern or ns.RollPattern(RANDOM_ROLL_RESULT)
		pattern = defaultPattern
	end
	local who, roll, low, high = msg:match(pattern)
	if who then return who, tonumber(roll), tonumber(low), tonumber(high) end
end
