std = "lua51"
max_line_length = false
codes = true
exclude_files = { ".tools/", "Libs/", ".release/", "dist/" }
ignore = {
	"212/self", -- unused self in method-style callbacks
}
globals = {
	"BonfireDB",
}
read_globals = {
	-- libraries
	"LibStub", "HBD_PINS_WORLDMAP_SHOW_PARENT",
	-- WoW API
	"Ambiguate", "C_AddOns", "C_ChatInfo", "C_Container", "C_Item", "C_Spell", "C_Timer", "C_UnitAuras",
	"ChatFrame_RemoveChannel", "InCombatLockdown",
	"CreateFrame", "GameTooltip", "GameTooltip_Hide", "GetBuildInfo", "GetChannelName",
	"GetMoney", "GetNormalizedRealmName", "GetNumGroupMembers",
	"GetPlayerTradeMoney", "GetServerTime", "GetTargetTradeMoney", "GetTime", "InitiateTrade",
	"IsInRaid", "IsShiftKeyDown", "JoinTemporaryChannel", "PlayMusic", "PlaySound", "PlaySoundFile",
	"RandomRoll", "StopMusic", "UnitGUID", "UnitName", "issecretvalue",
	-- FrameXML globals and constants
	"C_TradeInfo", "MoneyInputFrame_SetCopper", "TradePlayerInputMoneyFrame",
	"DEFAULT_CHAT_FRAME", "geterrorhandler", "FCF_OpenNewWindow", "FCF_StartAlertFlash", "GetChatWindowInfo", "ChatFrame_AddChannel",
	"LeaveChannelByName", "SELECTED_CHAT_FRAME",
	"ERR_TRADE_COMPLETE", "NUM_BAG_SLOTS", "NUM_CHAT_WINDOWS", "RANDOM_ROLL_RESULT", "SOUNDKIT", "UIParent", "UISpecialFrames",
	"floor", "strtrim", "tContains", "tinsert",
}
files["tests/"] = { read_globals = { "os" } }
