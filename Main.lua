local name, addon = ...

local REFRESH_DELAY = .25
local questEvents = {
    "QUEST_LOG_UPDATE", "QUEST_ACCEPTED", "QUEST_TURNED_IN", "QUEST_REMOVED", "PLAYER_LEVEL_UP",
}

local function say(message)
    DEFAULT_CHAT_FRAME:AddMessage("|cffd6a85eAeternum|r: " .. message)
end

-- Quest events arrive in bursts; one refresh covers each burst.
local refreshPending = false
local function scheduleRefresh()
    if refreshPending then
        return
    end
    local function refresh()
        refreshPending = false
        addon.RefreshQuestStates()
    end
    if C_Timer and C_Timer.After then
        refreshPending = true
        C_Timer.After(REFRESH_DELAY, refresh)
    else
        refresh()
    end
end

local events = CreateFrame("Frame")

-- Some clients lack an event; registering an unknown one raises an error.
local function register(event)
    pcall(events.RegisterEvent, events, event)
end

register("ADDON_LOADED")
register("PLAYER_LOGIN")
register("GET_ITEM_INFO_RECEIVED")
register("UI_SCALE_CHANGED")
register("DISPLAY_SIZE_CHANGED")
for _, event in ipairs(questEvents) do
    register(event)
end

events:SetScript("OnEvent", function(_, event, ...)
    if event == "ADDON_LOADED" then
        local loaded = ...
        if loaded == name then
            addon.LoadSettings()
            addon.AttachMap()
        elseif loaded == "Blizzard_WorldMap" then
            addon.AttachMap()
        end
    elseif event == "PLAYER_LOGIN" then
        addon.AttachMap()
    elseif event == "GET_ITEM_INFO_RECEIVED" then
        if addon.UI:IsOpen() then addon.UI:OnItemInfo((...)) end
    elseif event == "UI_SCALE_CHANGED" or event == "DISPLAY_SIZE_CHANGED" then
        if addon.UI:IsOpen() then addon.UI:Layer() end
    else
        addon.Quests:Invalidate(event == "PLAYER_LEVEL_UP" and (...) or nil)
        if addon.UI.map and addon.UI.map:IsShown() and (addon.UI:IsOpen() or addon.settings.showMapPins) then
            scheduleRefresh()
        end
    end
end)

local function openPanel(atlas)
    if not addon.AttachMap() and C_AddOns and C_AddOns.LoadAddOn then
        C_AddOns.LoadAddOn("Blizzard_WorldMap")
    end
    if not addon.AttachMap() then
        say("the world map is unavailable.")
        return
    end
    if not WorldMapFrame:IsShown() then
        if InCombatLockdown() then
            say("open the map after combat to browse the guide.")
            return
        end
        -- The map's own toggle keeps its windowed or maximised state.
        ToggleWorldMap()
    end
    addon.UI:Show(atlas == true)
end

local commands = {
    [""] = openPanel,
    show = openPanel,
    dungeons = function() openPanel(true) end,
    stop = function()
        addon.Navigation:Stop()
    end,
    pins = function()
        addon.settings.showMapPins = not addon.settings.showMapPins
        say(addon.settings.showMapPins and "map pins enabled." or "map pins disabled.")
        addon.RefreshMap()
    end,
    reset = function()
        addon.ResetSettings()
        if addon.UI:IsOpen() then addon.UI:Hide() else addon.RefreshMap() end
        say("settings reset.")
    end,
    help = function()
        say("/aeternum browses this map. /aeternum dungeons opens the dungeon guide.")
        say("/aeternum stop ends minimap guidance.")
        say("/aeternum pins toggles map pins.")
        say("/aeternum reset restores the default filters and options.")
    end,
}

SLASH_AETERNUM1 = "/aeternum"
SlashCmdList.AETERNUM = function(message)
    local command = commands[strtrim(message or ""):lower()]
    if command then
        command()
    else
        commands.help()
    end
end
