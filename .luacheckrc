std = "lua51"
max_line_length = 120
self = false
exclude_files = { "Data.lua", "ClassicTraining.lua", "ForeverTraining.lua", "FloorData.lua" }

-- Globals the addon defines.
globals = {
    "AeternumDB", "AeternumTrainerDB", "AeternumRouteDB", "AeternumMapPinMixin", "SLASH_AETERNUM1", "SlashCmdList",
    "Aeternum_OnAddonCompartmentClick", "Aeternum_OnAddonCompartmentEnter", "Aeternum_OnAddonCompartmentLeave",
}

-- Client API the addon reads. RegisterGameMenuEscHandler, UISpecialFrames, ToggleWorldMap and
-- the map canvas zoom constants are left out on purpose, so luacheck flags any use: calling
-- or writing them from add-on code taints Blizzard's Escape and map code.
read_globals = {
    "Menu", "MenuUtil", "C_SkillInfo", "C_Spell", "C_TooltipInfo", "Enum", "GetProfessions", "GetProfessionInfo",
    "GetTrainerServiceInfo", "GetTrainerServiceCost", "GetNumTrainerServices", "GetTrainerServiceSkillReq", "UnitGUID",
    "C_Trainer", "C_SpellBook", "C_RaidLocks", "C_SuperTrack", "UnitPosition", "TRAINING_POINTS_ABBREV",
    "GetCursorPosition", "GetInstanceInfo", "GetSubZoneText", "GetLocale", "GetMoneyString",
    "C_AddOns", "C_CVar", "C_Item", "C_Map", "C_MapExplorationInfo", "C_Minimap", "C_QuestLog", "C_Timer",
    "CreateFrame", "CreateFromMixins", "CreateVector2D", "DEFAULT_CHAT_FRAME", "GameTooltip",
    "GetPlayerFacing", "HandleModifiedItemClick", "InCombatLockdown", "IsInInstance", "IsModifiedClick",
    "MapCanvasDataProviderMixin", "MapCanvasPinMixin", "Minimap", "Mixin", "SetItemRef",
    "OpenWorldMap", "UIParent", "UnitClass", "UnitFactionGroup", "UnitIsDeadOrGhost", "UnitLevel",
    "UnitQuestTrivialLevelRange", "UnitRace", "WorldMapFrame", "canaccesstable", "issecretvalue",
    "hooksecurefunc", "strtrim", "wipe",
    "InputUtil", "LEVEL", "MAP_AREA_LABEL_TYPE", "QuestDifficultyColors", "GetQuestDifficultyColor",
    "GetRelativeDifficultyColor", "TooltipDataProcessor", "ItemRefTooltip",
    "AuraUtil", "UnitGroupRolesAssigned",
}

files["tests/**"] = { std = "+luajit", globals = { "setfenv" } }
files["tools/**"] = { globals = { "NorgannonDB" } }
