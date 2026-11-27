local name, addon = ...
local frame = CreateFrame("Frame")
local pending = false

local function refreshQuests()
    pending = false
    addon.RefreshQuestStates()
end

frame:SetScript("OnEvent", function(_, event, arg, second, _, _, success)
    if event == "ADDON_LOADED" then
        if arg == name then addon.LoadSettings() end
        if arg == name or arg == "Blizzard_WorldMap" then addon.AttachMap() end
    elseif event == "PLAYER_LOGIN" or event == "PLAYER_ENTERING_WORLD" then
        addon.Trainers:Invalidate()
        addon.Quests:Invalidate()
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
    elseif event == "ITEM_DATA_LOAD_RESULT" or event == "GET_ITEM_INFO_RECEIVED" then
        addon.UI:ItemLoaded(arg, second)
    elseif event == "TRAINER_SHOW" or event == "TRAINER_UPDATE" or event == "TRAINER_SERVICE_INFO_NAME_UPDATE" then
        addon.Trainers:Observe()
    elseif event == "ZONE_CHANGED_INDOORS" or event == "ZONE_CHANGED" then
        addon.DungeonMap:OpenInstance(true)
        addon.Navigation:Restore()
    elseif event == "SPELLS_CHANGED" then
        addon.UI:LootSkillsChanged()
    elseif event == "SKILL_LINES_CHANGED" or event == "LEARNED_SPELL_IN_SKILL_LINE" then
        addon.Trainers:Invalidate()
        addon.UI:LootSkillsChanged()
        addon.Quests:Invalidate()
        addon.RefreshMap()
    else
        if event == "CVAR_UPDATE" and arg ~= "questPOI" then return end
        if event == "PLAYER_LEVEL_UP" then addon.UI:LootSkillsChanged() end
        addon.Quests:Invalidate(event == "PLAYER_LEVEL_UP" and arg or nil)
        if addon.UI.map and addon.UI.map:IsShown() and not pending then
            pending = true
            C_Timer.After(.25, refreshQuests)
        end
    end
end)
for _, event in ipairs({"ADDON_LOADED", "PLAYER_LOGIN", "PLAYER_ENTERING_WORLD", "TRAINER_SHOW", "TRAINER_UPDATE",
    "SKILL_LINES_CHANGED", "LEARNED_SPELL_IN_SKILL_LINE", "SPELLS_CHANGED", "QUEST_LOG_UPDATE", "QUEST_ACCEPTED",
    "QUEST_TURNED_IN", "QUEST_REMOVED", "PLAYER_LEVEL_UP", "ZONE_CHANGED_INDOORS", "ZONE_CHANGED",
    "BOSS_KILL", "ENCOUNTER_END", "TRAINER_SERVICE_INFO_NAME_UPDATE", "QUEST_WATCH_LIST_CHANGED",
    "SUPER_TRACKING_CHANGED", "QUEST_POI_UPDATE", "CVAR_UPDATE", "ITEM_DATA_LOAD_RESULT",
    "GET_ITEM_INFO_RECEIVED"}) do
    pcall(frame.RegisterEvent, frame, event)
end

SLASH_AETERNUM1 = "/aeternum"
SlashCmdList.AETERNUM = function(message)
    local text = addon.Trim(message)
    local command, query = text:match("^(%S*)%s*(.-)$")
    command = command:lower()
    if command == "stop" then
        local active = addon.Navigation:IsActive()
        addon.Navigation:Stop()
        DEFAULT_CHAT_FRAME:AddMessage(active and "Directions stopped." or "Directions are not active.")
        return
    end
    if command == "reset" then
        addon.ResetSettings()
        addon.RefreshMap()
        DEFAULT_CHAT_FRAME:AddMessage("Aeternum map filters reset.")
        return
    end
    local help = "Use /aeternum to open the map, /aeternum <name> to search, or /aeternum stop to end directions."
    if command == "help" or command == "?" then
        DEFAULT_CHAT_FRAME:AddMessage(help)
        return
    end
    local results
    if command ~= "" and command ~= "show" and command ~= "dungeons" then
        results = addon.Entries(nil, true, text)
        if #results == 0 then DEFAULT_CHAT_FRAME:AddMessage(help); return end
        command, query = "dungeons", text
    end
    if not addon.settings then addon.LoadSettings() end
    if not addon.AttachMap() and C_AddOns and C_AddOns.LoadAddOn then C_AddOns.LoadAddOn("Blizzard_WorldMap") end
    if not addon.AttachMap() then return end
    if not WorldMapFrame:IsShown() then
        if InCombatLockdown() then DEFAULT_CHAT_FRAME:AddMessage("Open the map after combat."); return end
        ToggleWorldMap()
    end
    if command == "dungeons" then addon.UI:Search(query, results) end
end
