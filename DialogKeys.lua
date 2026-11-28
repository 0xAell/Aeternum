local name, addon = ...
local events = CreateFrame("Frame")
local owner, hooksReady
local slots, labels, watched = {}, {}, {}
local bindings, boundSlots = {}, {}
local numberKeys = { "1", "2", "3", "4", "5", "6", "7", "8", "9", "0" }
local advanceSlot, wheelUpSlot, wheelDownSlot = 11, 12, 13

-- Restrict the default popup list to normal interaction confirmations. Other
-- popups still take priority over any quest or gossip window behind them.
local confirmations = {
    CONFIRM_BINDER = true,
    CONFIRM_HIGH_COST_ITEM = true,
    CONFIRM_LOOT_ROLL = true,
    CONFIRM_PURCHASE_NONREFUNDABLE_ITEM = true,
    CONFIRM_PURCHASE_TOKEN_ITEM = true,
    LOOT_BIND = true,
    PARTY_INVITE = true,
    GOSSIP_CONFIRM = true,
    CONFIRM_ACCEPT_PVP_QUEST = true,
    CONFIRM_COMPLETE_EXPENSIVE_QUEST = true,
}

local function visible(frame)
    return type(frame) == "table" and frame.IsVisible and not (frame.IsForbidden and frame:IsForbidden())
        and frame:IsVisible()
end

local function clickable(button)
    return visible(button) and button.Click and button:IsEnabled()
end

local function topPopup()
    local top
    StaticPopup_ForEachShownDialog(function(dialog)
        if visible(dialog) then top = dialog end
    end)
    return top
end

local function confirmButton(popup)
    if addon.settings.dialogPopups and confirmations[popup.which] and popup.GetButton1 then
        return popup:GetButton1()
    end
end

local gossipActions = {
    [3] = function(info) C_GossipInfo.SelectOptionByIndex(info.orderIndex) end,
    [4] = function(info) C_GossipInfo.SelectActiveQuest(info.questID) end,
    [5] = function(info) C_GossipInfo.SelectAvailableQuest(info.questID) end,
}

local function gossipOptions(options, rows)
    local scrollBox = GossipFrame.GreetingPanel.ScrollBox
    local provider = scrollBox:GetView() and scrollBox:GetDataProvider()
    if not provider then return end
    for _, element in provider:Enumerate() do
        if element.index and gossipActions[element.buttonType] then
            options[element.index] = element
        end
    end
    if rows then
        for _, button in scrollBox:EnumerateFrames() do
            local element = button:GetElementData()
            if element and visible(button) and options[element.index] then rows[element.index] = button end
        end
    end
end

local function questOptions(options)
    local pool = QuestFrameGreetingPanel.titleButtonPool
    if not pool then return end
    local active = GetNumActiveQuests()
    for button in pool:EnumerateActive() do
        if clickable(button) then
            local index = button:GetID() + (button.isActive == 1 and 0 or active)
            options[index] = button
        end
    end
end

local function rewardOptions(options)
    for _, button in ipairs(QuestInfoRewardsFrame.RewardButtons) do
        if button.type == "choice" and clickable(button) then options[button:GetID()] = button end
    end
end

local function customButton(settings)
    for _, frameName in ipairs(settings.dialogButtons or {}) do
        local button = _G[frameName]
        if clickable(button) then
            return button
        end
    end
end

local function scrollQuest(frame, delta)
    if not visible(frame) then return end
    frame.ScrollBar:ScrollWheelInDirection(delta)
end

local function clearTooltip()
    if events.rewardTooltip and GameTooltip:IsOwned(events.rewardTooltip) then GameTooltip:Hide() end
    events.rewardTooltip = nil
end

-- A native secure click runs the same button script as a mouse click. The
-- only slots that run Lua actions are virtualized gossip entries and scrolling.
local function getSlot(index)
    if slots[index] then return slots[index] end
    local button = CreateFrame("Button", "AeternumDialogKey" .. index, UIParent, "SecureActionButtonTemplate")
    button:RegisterForClicks("AnyUp")
    button:SetAttribute("type", "click")
    button:SetAttribute("useOnKeyDown", false)
    local action, reward, scroll
    button:SetScript("PreClick", function(self)
        action, reward, scroll = nil, nil, nil
        if InCombatLockdown() then return end
        local popup = topPopup()
        local target = self:GetAttribute("clickbutton")
        if not boundSlots[index] or GetCurrentKeyBoardFocus() or InputUtil.IsGamepadUIEnabled()
            or (popup and (not target or target ~= confirmButton(popup))) or (target and not clickable(target)) then
            self:SetAttribute("clickbutton", nil)
            return
        end
        action, reward, scroll = events.gossip[index], events.rewards[index], events.scroll
    end)
    button:SetScript("PostClick", function()
        if InCombatLockdown() then return end
        if action and visible(GossipFrame) then
            -- Look up the current entry by index because the scroll box recycles
            -- row widgets and the first choice can be below the scroll range.
            local options = {}
            gossipOptions(options)
            local option = options[action]
            if option then gossipActions[option.buttonType](option.info) end
        elseif clickable(reward) and visible(QuestFrameRewardPanel)
            and QuestInfoFrame.itemChoice == index then
            GameTooltip:SetOwner(reward, "ANCHOR_RIGHT")
            GameTooltip:SetQuestItem("choice", index)
            GameTooltip_ShowCompareItem(GameTooltip)
            GameTooltip:Show()
            events.rewardTooltip = reward
        elseif index == wheelUpSlot or index == wheelDownSlot then
            scrollQuest(scroll, index == wheelUpSlot and -1 or 1)
        end
    end)
    slots[index] = button
    return button
end

local function showNumber(index, row)
    local label = labels[index]
    if row then
        if not label then
            label = CreateFrame("Frame", nil, row)
            local text = label:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            label:SetAllPoints()
            text:SetPoint("RIGHT", label, "LEFT", -2, 0)
            text:SetText(numberKeys[index])
            labels[index] = label
        elseif label:GetParent() ~= row then
            label:SetParent(row)
            label:ClearAllPoints()
            label:SetAllPoints()
        end
        label:Show()
    elseif label then
        label:Hide()
    end
end

local function setBindings(keys, targets)
    -- Secure state changes clear the owner's overrides immediately on combat
    -- entry. All normal binding and attribute writes happen out of combat.
    if not owner then
        if not next(keys) then return end
        owner = CreateFrame("Frame", nil, nil, "SecureHandlerStateTemplate")
        owner:SetAttribute("_onstate-aeternumcombat", [[
            if newstate == "combat" then self:ClearBindings() end
        ]])
        RegisterStateDriver(owner, "aeternumcombat", "[combat] combat; safe")
    end
    boundSlots = {}
    for _, index in pairs(keys) do
        local slot = getSlot(index)
        boundSlots[index] = true
        if slot:GetAttribute("clickbutton") ~= targets[index] then
            slot:SetAttribute("clickbutton", targets[index])
        end
    end
    for key, index in pairs(bindings) do
        if keys[key] ~= index then
            ClearOverrideBindings(owner)
            bindings = {}
            break
        end
    end
    for key, index in pairs(keys) do
        if not bindings[key] then
            SetOverrideBindingClick(owner, false, key, slots[index]:GetName())
            bindings[key] = index
        end
    end
end

local function refresh()
    if InCombatLockdown() then
        bindings, boundSlots = {}, {}
        for index in pairs(labels) do showNumber(index) end
        clearTooltip()
        return false
    end
    local settings = addon.settings
    if not owner and not (settings and settings.dialogKeys) then return false end
    local primary, scroll, active
    local keys, targets, options, rows, gossip, rewards = {}, {}, {}, {}, {}, {}
    local gossipIndices = {}
    if settings and settings.dialogKeys then
        local popup = topPopup()
        local custom = customButton(settings)
        active = popup or visible(QuestFrame) or visible(GossipFrame) or custom
        if active and not GetCurrentKeyBoardFocus() and not InputUtil.IsGamepadUIEnabled() then
            if popup then
                primary = confirmButton(popup)
            elseif visible(QuestFrameRewardPanel) then
                primary, scroll = QuestFrameCompleteQuestButton, QuestRewardScrollFrame
                rewardOptions(options)
                rewards = options
            elseif visible(QuestFrameProgressPanel) then
                primary, scroll = QuestFrameCompleteButton, QuestProgressScrollFrame
            elseif visible(QuestFrameDetailPanel) then
                primary, scroll = QuestFrameAcceptButton, QuestDetailScrollFrame
            elseif visible(QuestFrameGreetingPanel) then
                questOptions(options)
                primary, scroll = options[1], QuestGreetingScrollFrame
            elseif visible(GossipFrame) then
                gossipOptions(gossip, rows)
            end
            if not clickable(primary) then primary = nil end
            if not popup and not primary and not gossip[1] and not visible(QuestFrame) then primary = custom end
        end
    end

    for index, key in ipairs(numberKeys) do
        if options[index] or gossip[index] then
            keys[key], targets[index] = index, options[index]
        end
        if gossip[index] then gossipIndices[index] = index end
        showNumber(index, options[index] or rows[index])
    end
    if primary or gossip[1] then
        if gossip[1] then gossipIndices[advanceSlot] = 1 end
        keys[settings.dialogPrimary], targets[advanceSlot] = advanceSlot, primary
        if settings.dialogSecondary ~= "" then keys[settings.dialogSecondary] = advanceSlot end
    end
    if settings and settings.dialogScroll and visible(scroll) and scroll:GetVerticalScrollRange() > 0 then
        keys.MOUSEWHEELUP, keys.MOUSEWHEELDOWN = wheelUpSlot, wheelDownSlot
    end
    events.gossip, events.rewards, events.scroll = gossipIndices, rewards, scroll
    if events.rewardTooltip and rewards[events.rewardTooltip:GetID()] ~= events.rewardTooltip then clearTooltip() end
    setBindings(keys, targets)
    return active
end

local elapsed = 0
local function update(_, delta)
    elapsed = elapsed + delta
    if elapsed < .05 then return end
    elapsed = 0
    if not refresh() then events:SetScript("OnUpdate", nil) end
end

local function updateBindings()
    local active = refresh()
    events:SetScript("OnUpdate", active and update or nil)
end

local function watch(frame)
    if type(frame) == "table" and frame.HookScript and not watched[frame] then
        watched[frame] = true
        frame:HookScript("OnShow", updateBindings)
        frame:HookScript("OnHide", updateBindings)
    end
end

local function hookDialogs()
    if not hooksReady then
        hooksReady = true
        PopupEventManager:RegisterCallback("PopupOpened", updateBindings, events)
        PopupEventManager:RegisterCallback("PopupClosed", updateBindings, events)
        EventRegistry:RegisterCallback("ChatFrame.OnEditBoxFocusGained", updateBindings, events)
        EventRegistry:RegisterCallback("ChatFrame.OnEditBoxFocusLost", updateBindings, events)
    end
    watch(GossipFrame)
    watch(QuestFrame)
    watch(QuestFrameDetailPanel)
    watch(QuestFrameProgressPanel)
    watch(QuestFrameRewardPanel)
    watch(QuestFrameGreetingPanel)
    for _, frameName in ipairs(addon.settings.dialogButtons or {}) do watch(_G[frameName]) end
end

events:SetScript("OnEvent", function(_, event, arg)
    if event == "ADDON_LOADED" and arg == name then return end
    if addon.settings and addon.settings.dialogKeys then hookDialogs() end
    updateBindings()
end)
for _, event in ipairs({
    "ADDON_LOADED", "PLAYER_LOGIN", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "GAME_PAD_ACTIVE_CHANGED",
    "GOSSIP_SHOW", "GOSSIP_CLOSED", "QUEST_DETAIL", "QUEST_GREETING", "QUEST_PROGRESS", "QUEST_COMPLETE",
    "QUEST_FINISHED",
}) do
    events:RegisterEvent(event)
end

local function printStatus(settings)
    local secondary = settings.dialogSecondary ~= "" and " / " .. settings.dialogSecondary or ""
    DEFAULT_CHAT_FRAME:AddMessage(("Aeternum dialog keys %s. Advance: %s%s. Popups: %s. Quest scrolling: %s."):format(
        settings.dialogKeys and "on" or "off", settings.dialogPrimary, secondary,
        settings.dialogPopups and "on" or "off", settings.dialogScroll and "on" or "off"))
end

function addon.DialogKeyCommand(message)
    local settings = addon.settings
    local command, value = message:match("^(%S*)%s*(.-)$")
    command = command:lower()
    if command == "on" or command == "off" then
        settings.dialogKeys = command == "on"
    elseif (command == "popup" or command == "scroll") and (value == "on" or value == "off") then
        settings[command == "popup" and "dialogPopups" or "dialogScroll"] = value == "on"
    elseif command == "key" or command == "second" then
        local key = value:upper()
        if command == "second" and key == "NONE" then
            settings.dialogSecondary = ""
        elseif key:match("^[%w%-]+$") and not key:match("^%d$")
            and key ~= "ESCAPE" and key ~= "UNKNOWN" and key ~= "NONE" then
            settings[command == "key" and "dialogPrimary" or "dialogSecondary"] = key
        else
            DEFAULT_CHAT_FRAME:AddMessage("Use a key name such as SPACE or CTRL-SPACE. Use second none to clear it.")
            return
        end
    elseif command == "add" or command == "remove" then
        local frameName = value
        if value == "" then
            for _, frame in ipairs(GetMouseFoci()) do
                if clickable(frame) and frame:GetName() then
                    frameName = frame:GetName()
                    break
                end
            end
        end
        if not frameName:match("^[%a_][%w_]*$") then
            DEFAULT_CHAT_FRAME:AddMessage("Hover a named button or enter its exact Blizzard frame name.")
            return
        end
        local buttons = settings.dialogButtons or {}
        settings.dialogButtons = buttons
        for index, existing in ipairs(buttons) do
            if existing == frameName then table.remove(buttons, index); break end
        end
        if command == "add" then buttons[#buttons + 1] = frameName end
    else
        printStatus(settings)
        DEFAULT_CHAT_FRAME:AddMessage("/aeternum dialog on|off, key <key>, second <key|none>, popup on|off, "
            .. "scroll on|off, add|remove [FrameName]")
        return
    end
    if settings.dialogKeys then hookDialogs() end
    updateBindings()
    printStatus(settings)
end
