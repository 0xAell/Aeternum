local name, addon = ...
local frame = CreateFrame("Frame")
local pending = false

local function refreshQuests()
    pending = false
    addon.RefreshQuestStates()
end

frame:SetScript("OnEvent", function(_, event, arg, _, _, _, success)
    if event == "ADDON_LOADED" then
        if arg == name then addon.LoadSettings() end
        if arg == name or arg == "Blizzard_WorldMap" then addon.AttachMap() end
    elseif event == "PLAYER_LOGIN" or event == "PLAYER_ENTERING_WORLD" then
        addon.Trainers:Invalidate()
        if event == "PLAYER_ENTERING_WORLD" then addon.DungeonMap:NewVisit() end
        if addon.AttachMap() then
            addon.DungeonMap:Close()
            addon.RefreshMap()
        end
        addon.DungeonMap:OpenInstance()
        addon.Navigation:Restore()
        if addon.Navigation:IsActive() then addon.Navigation:Update() end
    elseif event == "BOSS_KILL" or event == "ENCOUNTER_END" then
        if event == "BOSS_KILL" or (addon.IsReadableNumber(success) and success == 1) then
            addon.DungeonMap:RecordKill(arg)
        end
    elseif event == "TRAINER_SHOW" or event == "TRAINER_UPDATE" or event == "TRAINER_SERVICE_INFO_NAME_UPDATE" then
        addon.Trainers:Observe()
    elseif event == "ZONE_CHANGED_INDOORS" or event == "ZONE_CHANGED" then
        addon.DungeonMap:OpenInstance(true)
        addon.Navigation:Restore()
    elseif event == "SKILL_LINES_CHANGED" or event == "LEARNED_SPELL_IN_SKILL_LINE" then
        addon.Trainers:Invalidate()
        addon.Quests:Invalidate()
        addon.RefreshMap()
    else
        if event == "CVAR_UPDATE" and arg ~= "questPOI" then return end
        addon.Quests:Invalidate(event == "PLAYER_LEVEL_UP" and arg or nil)
        if addon.UI.map and addon.UI.map:IsShown() and not pending then
            pending = true
            C_Timer.After(.25, refreshQuests)
        end
    end
end)
for _, event in ipairs({"ADDON_LOADED", "PLAYER_LOGIN", "PLAYER_ENTERING_WORLD", "TRAINER_SHOW", "TRAINER_UPDATE",
    "SKILL_LINES_CHANGED", "LEARNED_SPELL_IN_SKILL_LINE", "QUEST_LOG_UPDATE", "QUEST_ACCEPTED",
    "QUEST_TURNED_IN", "QUEST_REMOVED", "PLAYER_LEVEL_UP", "ZONE_CHANGED_INDOORS", "ZONE_CHANGED",
    "BOSS_KILL", "ENCOUNTER_END", "TRAINER_SERVICE_INFO_NAME_UPDATE", "QUEST_WATCH_LIST_CHANGED",
    "SUPER_TRACKING_CHANGED", "QUEST_POI_UPDATE", "CVAR_UPDATE"}) do
    pcall(frame.RegisterEvent, frame, event)
end

SLASH_AETERNUM1 = "/aeternum"
SlashCmdList.AETERNUM = function(message)
    local command, query = strtrim(message or ""):match("^(%S*)%s*(.-)$")
    command = command:lower()
    if command == "stop" then addon.Navigation:Stop() return end
    if command == "reset" then addon.ResetSettings(); addon.RefreshMap(); return end
    if command ~= "" and command ~= "show" and command ~= "dungeons" then
        DEFAULT_CHAT_FRAME:AddMessage("Open the world map to see locations. /aeternum dungeons [name] searches it.")
        return
    end
    if not addon.AttachMap() and C_AddOns then C_AddOns.LoadAddOn("Blizzard_WorldMap") end
    if not addon.AttachMap() then return end
    if not WorldMapFrame:IsShown() then
        if InCombatLockdown() then return end
        ToggleWorldMap()
    end
    if command == "dungeons" then addon.UI:Search(query) end
end
