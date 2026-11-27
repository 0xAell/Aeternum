std = "lua51"
max_line_length = 120
self = false
exclude_files = { "Data.lua" }

-- Globals the addon defines.
globals = {
    "AeternumDB", "AeternumMapPinMixin", "SLASH_AETERNUM1", "SlashCmdList",
}

-- Client API the addon reads.
read_globals = {
    "C_AddOns", "C_CVar", "C_Item", "C_Map", "C_Minimap", "C_QuestLog", "C_Timer",
    "CreateFrame", "CreateFromMixins", "CreateVector2D", "DEFAULT_CHAT_FRAME", "GameMenuEscPriority", "GameTooltip",
    "GetPlayerFacing", "HandleModifiedItemClick", "InCombatLockdown", "IsInInstance", "IsModifiedClick",
    "MapCanvasDataProviderMixin", "MapCanvasPinMixin", "Minimap", "Mixin", "RegisterGameMenuEscHandler", "SetItemRef",
    "ToggleWorldMap", "UIParent", "UISpecialFrames", "UnitClass", "UnitFactionGroup", "UnitLevel",
    "UnitQuestTrivialLevelRange", "UnitRace", "WorldMapFrame", "canaccesstable", "issecretvalue",
    "strtrim", "wipe",
}

-- FileDataID tables for the legacy floor art.
files["DungeonMap.lua"] = { max_line_length = false }
files["tests/**"] = { std = "+luajit", globals = { "setfenv" } }
files["tools/**"] = { globals = { "NorgannonDB" } }
