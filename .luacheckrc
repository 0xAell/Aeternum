std = "lua51"
max_line_length = 120
self = false
exclude_files = { "Data.lua", "ClassicTraining.lua", "FloorData.lua" }

-- Globals the addon defines.
globals = {
    "AeternumDB", "AeternumTrainerDB", "AeternumRouteDB", "AeternumMapPinMixin", "SLASH_AETERNUM1", "SlashCmdList",
}

-- Client API the addon reads.
read_globals = {
    "Menu", "MenuUtil", "C_SkillInfo", "C_Spell", "C_TooltipInfo", "Enum", "GetProfessions", "GetProfessionInfo",
    "GetTrainerServiceInfo", "GetTrainerServiceCost", "GetNumTrainerServices", "GetTrainerServiceSkillReq", "UnitGUID",
    "C_Trainer", "C_SpellBook", "C_RaidLocks", "C_SuperTrack", "UnitPosition", "TRAINING_POINTS_ABBREV",
    "GetCursorPosition", "GetInstanceInfo", "GetSubZoneText", "GetLocale", "GetMoneyString", "hooksecurefunc",
    "MAP_CANVAS_MOUSE_WHEEL_ZOOM_BEHAVIOR_FULL",
    "C_AddOns", "C_CVar", "C_Item", "C_Map", "C_Minimap", "C_QuestLog", "C_Timer",
    "CreateFrame", "CreateFromMixins", "CreateVector2D", "DEFAULT_CHAT_FRAME", "GameTooltip",
    "GetPlayerFacing", "HandleModifiedItemClick", "InCombatLockdown", "IsInInstance", "IsModifiedClick",
    "MapCanvasDataProviderMixin", "MapCanvasPinMixin", "Minimap", "Mixin", "SetItemRef",
    "ToggleWorldMap", "UIParent", "UnitClass", "UnitFactionGroup", "UnitLevel",
    "UnitQuestTrivialLevelRange", "UnitRace", "WorldMapFrame", "canaccesstable", "issecretvalue",
    "strtrim", "wipe",
}

files["tests/**"] = { std = "+luajit", globals = { "setfenv" } }
files["tools/**"] = { globals = { "NorgannonDB" } }
