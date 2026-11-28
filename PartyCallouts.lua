local _, addon = ...
local Callouts = {}
addon.PartyCallouts = Callouts

local PREFIX = "AeternumPull1"
local CHAT_PREFIX = "[Aeternum] "
local DISCOVERY_DELAY, CHAT_COOLDOWN = 2, 12
local encounters, creatures = {}, {}
local peers, announced, unsynced = {}, {}, {}
local roster, player, channel, instance, leftAlive, pending, lastCallout
local discoveryQueued, helloNeeded, registered, discoverySent, settledAt, realmSuffix
local frame = CreateFrame("Frame")

-- Encounter IDs take precedence. Creature IDs provide a fallback for Forever
-- bosses whose encounter events or journal IDs are unavailable.
for _, dungeon in ipairs(addon.Data.dungeons) do
    local layout = addon.floorData[dungeon.id]
    local byNPC, byEncounter = {}, {}
    for _, boss in ipairs(dungeon.bosses) do
        local tip = addon.partyCallouts[boss.id]
        if tip then
            local entry = {id=boss.id, name=boss.name, text=tip.text, options=tip.options, levelMax=dungeon.levelMax}
            byNPC[boss.id] = entry
            for _, id in ipairs(tip.aliases or {}) do byNPC[id] = entry end
            if tip.encounter then byEncounter[tip.encounter] = entry end
        end
    end
    if next(byNPC) then
        for _, floor in ipairs(layout.floors) do
            for _, point in ipairs(floor.bosses) do
                local entry = byNPC[point[1]]
                if entry then
                    for _, id in ipairs(point.encounters or {}) do byEncounter[id] = entry end
                end
            end
        end
        creatures[layout.instance] = creatures[layout.instance] or {}
        encounters[layout.instance] = encounters[layout.instance] or {}
        for id, entry in pairs(byNPC) do creatures[layout.instance][id] = entry end
        for id, entry in pairs(byEncounter) do encounters[layout.instance][id] = entry end
    end
end

local function readable(value)
    return not (issecretvalue and issecretvalue(value))
end

local function dungeonInstance()
    if not IsInInstance() then return end
    local _, kind, _, _, _, _, _, id = GetInstanceInfo()
    if readable(kind) and kind == "party" and addon.IsReadableNumber(id) then return id end
end

local function partyChannel()
    local category = LE_PARTY_CATEGORY_INSTANCE
    if category and IsInGroup(category) then
        if not IsInRaid(category) then return "INSTANCE_CHAT" end
    elseif IsInGroup() and not IsInRaid() then
        return "PARTY"
    end
end

local function isTrue(value)
    return readable(value) and value == true
end

local function normalizeName(name)
    return (name:lower():gsub("%s+", "-"))
end

local function readMember(unit, localRealm)
    if not isTrue(UnitExists(unit)) or not isTrue(UnitIsConnected(unit)) then return end
    local first, last = UnitFullName(unit)
    if not readable(first) or not readable(last) or not first or first == "" or first == UNKNOWNOBJECT then return end
    local role = UnitGroupRolesAssigned(unit)
    local priority = readable(role) and role == "TANK" and 1 or (isTrue(UnitIsGroupLeader(unit)) and 2 or 3)
    local _, class = UnitClass(unit)
    local level = UnitLevel(unit)
    -- Forever returns first name and surname separately. A same-realm
    -- suffix on a chat sender is optional and is not part of the character's name.
    local key = normalizeName(first)
    if last and last ~= "" and normalizeName(last) ~= localRealm then
        key = key .. "-" .. normalizeName(last)
    end
    return {
        unit=unit, key=key, priority=priority,
        class=readable(class) and class or nil, level=addon.IsReadableNumber(level) and level or nil,
    }
end

local function refreshRoster()
    local nextChannel = creatures[instance] and partyChannel()
    if channel ~= nextChannel then
        wipe(peers)
        discoverySent = nil
    end
    channel = nextChannel
    roster, player = {}, nil
    if not channel then return end
    local localRealm = normalizeName(GetNormalizedRealmName() or "")
    realmSuffix = localRealm ~= "" and ("-" .. localRealm) or nil
    player = readMember("player", localRealm)
    if not player then return end
    roster[1] = player
    for index = 1, 4 do
        local member = readMember("party" .. index, localRealm)
        if member then roster[#roster + 1] = member end
    end
    for key in pairs(peers) do
        local present
        for _, member in ipairs(roster) do
            if member.key == key then present = true; break end
        end
        if not present then peers[key] = nil end
    end
end

local function senderInRoster(sender)
    if not readable(sender) or type(sender) ~= "string" then return end
    sender = normalizeName(sender)
    for _, member in ipairs(roster or {}) do
        if member.key == sender then return member end
    end
    if realmSuffix and sender:sub(-#realmSuffix) == realmSuffix then
        local bareName = sender:sub(1, -#realmSuffix - 1)
        for _, member in ipairs(roster or {}) do
            if member.key == bareName then return member end
        end
    end
end

local function hasParty()
    return registered and channel and player and #roster > 1 and dungeonInstance() == instance
        and partyChannel() == channel
end

local function chatRestricted()
    return C_ChatInfo and C_ChatInfo.InChatMessagingLockdown and C_ChatInfo.InChatMessagingLockdown()
end

local function sendAddon(message)
    if not hasParty() or chatRestricted() then return end
    local ok, result = pcall(C_ChatInfo.SendAddonMessage, PREFIX, message, channel)
    return ok and readable(result) and (result == 0 or result == true)
end

local function discovery(requestReply)
    if requestReply then
        helloNeeded = true
        settledAt = GetTime() + DISCOVERY_DELAY
    end
    if discoveryQueued or not hasParty() or chatRestricted() then return end
    discoveryQueued = true
    C_Timer.After(.2, function()
        discoveryQueued = nil
        local asking = helloNeeded
        local message = (asking and "H:" or "S:") .. (addon.settings.partyCallouts and "1" or "0")
        -- A different sender can take over when someone joins or reloads. Share
        -- the visit's completed reminders as part of normal roster discovery.
        if next(announced) then
            local ids = {}
            for id in pairs(announced) do ids[#ids + 1] = id end
            table.sort(ids)
            message = message .. ":" .. table.concat(ids, ",")
        end
        if sendAddon(message) then
            if asking then discoverySent = true end
            helloNeeded = nil
        end
    end)
end

local function remember(id, recent)
    if recent and not announced[id] then lastCallout = GetTime() end
    announced[id] = true
    if pending and pending.entry.id == id then pending = nil end
end

local function receive(prefix, message, distribution, sender)
    if not hasParty() or not readable(prefix) or not readable(distribution) or prefix ~= PREFIX
        or distribution ~= channel or not readable(message) or type(message) ~= "string" then return end
    local member = senderInRoster(sender)
    if not member or member.key == player.key then return end
    local kind, payload, history = message:match("^([HS]):([01])([:%d,]*)$")
    if kind then
        peers[member.key] = payload == "1"
        for previous in history:gmatch("%d+") do
            local entry = creatures[instance][tonumber(previous)]
            if entry then remember(entry.id, false) end
        end
        if kind == "H" then discovery(false) end
        return
    end
    local id = tonumber(message:match("^D:(%d+)$"))
    local entry = id and creatures[instance][id]
    if peers[member.key] ~= nil and entry then remember(entry.id, true) end
end

local function higherPriority(member, other)
    return member.priority < other.priority or (member.priority == other.priority and member.key < other.key)
end

local function messageFor(entry)
    for _, option in ipairs(entry.options or {}) do
        for _, member in ipairs(roster) do
            if member.class == option.class and member.level and member.level >= option.level
                and (member ~= player or not option.spell or addon.Tactics:KnownSpell(option.spell)) then
                return option.text
            end
        end
    end
    return entry.text
end

local function groupOutlevels(entry)
    if not entry.levelMax then return false end
    for _, member in ipairs(roster) do
        if not member.level or member.level <= entry.levelMax + 10 then return false end
    end
    return true
end

local function readyToCall(entry)
    if not addon.settings.partyCallouts or not discoverySent or GetTime() < settledAt or not hasParty()
        or chatRestricted() or announced[entry.id] or (lastCallout and GetTime() - lastCallout < CHAT_COOLDOWN) then
        return false
    end
    -- Peer status is negotiated before combat. A boss fight may block all addon
    -- traffic, so every client keeps the same sender until the roster changes.
    for _, member in ipairs(roster) do
        if peers[member.key] and higherPriority(member, player) then return false end
    end
    return not groupOutlevels(entry)
end

local function announce(entry)
    if not entry or not readyToCall(entry) then return end
    remember(entry.id, true)
    local ok = pcall(C_ChatInfo.SendChatMessage, CHAT_PREFIX .. entry.name .. " - " .. messageFor(entry), channel)
    if ok and not sendAddon("D:" .. entry.id) then
        unsynced[entry.id] = true
    end
end

local function bossUnit(unit)
    if not isTrue(UnitCanAttack("player", unit)) or isTrue(UnitIsDeadOrGhost(unit))
        or (UnitIsTrivial and isTrue(UnitIsTrivial(unit))) then return end
    local ok, guid = pcall(UnitGUID, unit)
    if not ok or not readable(guid) or type(guid) ~= "string" then return end
    local id = tonumber(guid:match("^Creature%-%d+%-%d+%-%d+%-%d+%-(%d+)%-"))
    local lookup = creatures[instance]
    return id and lookup and lookup[id]
end

local function combatBoss(unit)
    if isTrue(UnitAffectingCombat(unit)) then return bossUnit(unit) end
end

local function checkCombat()
    if not addon.settings.partyCallouts or not hasParty() or chatRestricted() then return end
    for index = 1, 5 do
        local boss = combatBoss("boss" .. index)
        if boss then announce(boss); return end
    end
    for _, member in ipairs(roster) do
        if isTrue(UnitAffectingCombat(member.unit)) then
            local boss = combatBoss(member.unit .. "target")
            if boss then announce(boss); return end
        end
    end
end

local function checkNearbyTarget()
    if pending or InCombatLockdown() or not hasParty() or not UnitIsInInteractRange
        or isTrue(UnitAffectingCombat("target")) or not isTrue(UnitIsInInteractRange("target")) then return end
    local entry = bossUnit("target")
    if not entry or not readyToCall(entry) then return end
    -- Demand a stable, live boss target in actual interact range. Several map
    -- pins are approximate and cannot safely stand in for boss-room boundaries.
    local target = {entry=entry}
    pending = target
    C_Timer.After(.35, function()
        if pending ~= target then return end
        pending = nil
        if not InCombatLockdown() and not isTrue(UnitAffectingCombat("target"))
            and isTrue(UnitIsInInteractRange("target")) and bossUnit("target") == entry then
            announce(entry)
        end
    end)
end

local function updateVisit()
    local current = dungeonInstance()
    if not current then
        if not isTrue(UnitIsDeadOrGhost("player")) then leftAlive = true end
    elseif current ~= instance or leftAlive then
        wipe(announced)
        wipe(peers)
        wipe(unsynced)
        discoverySent = nil
        instance, leftAlive, lastCallout = current, nil, nil
    end
    pending = nil
end

local function encounterEntry(id)
    local lookup = encounters[instance]
    return lookup and addon.IsReadableNumber(id) and lookup[id] or nil
end

local function observedChat(message, sender, distribution)
    if not hasParty() or channel ~= distribution or not senderInRoster(sender) or not readable(message)
        or type(message) ~= "string" or message:sub(1, #CHAT_PREFIX) ~= CHAT_PREFIX then return end
    for _, entry in pairs(creatures[instance]) do
        local prefix = CHAT_PREFIX .. entry.name .. " - "
        if message:sub(1, #prefix) == prefix then
            local text = message:sub(#prefix + 1)
            if text == entry.text then remember(entry.id, true); return end
            for _, option in ipairs(entry.options or {}) do
                if text == option.text then remember(entry.id, true); return end
            end
        end
    end
end

function Callouts:Command(argument)
    local mode = argument:lower()
    if mode == "on" or mode == "off" then
        addon.settings.partyCallouts = mode == "on"
        if mode == "off" then pending = nil end
        if registered then
            if not chatRestricted() then refreshRoster() end
            discovery(true)
        end
    elseif mode ~= "" then
        DEFAULT_CHAT_FRAME:AddMessage("Use /aeternum callouts on or /aeternum callouts off.")
        return
    end
    DEFAULT_CHAT_FRAME:AddMessage("Aeternum party callouts " .. (addon.settings.partyCallouts and "on." or "off."))
end

frame:SetScript("OnEvent", function(_, event, arg, second, third, fourth)
    if event == "PLAYER_LOGIN" then
        if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix and C_ChatInfo.SendAddonMessage
            and C_ChatInfo.SendChatMessage then
            local ok, result = pcall(C_ChatInfo.RegisterAddonMessagePrefix, PREFIX)
            registered = ok and readable(result) and (result == 0 or result == 1 or result == true)
        end
    elseif not registered then
        return
    elseif event == "PLAYER_ENTERING_WORLD" or event == "GROUP_ROSTER_UPDATE" then
        if event == "PLAYER_ENTERING_WORLD" then updateVisit() end
        -- A changed group must rediscover the sender. When the roster is
        -- restricted, defer the refresh until combat ends.
        discoverySent = nil
        if chatRestricted() then helloNeeded = true; return end
        refreshRoster()
        discovery(true)
    elseif event == "PLAYER_ROLES_ASSIGNED" then
        if not chatRestricted() then refreshRoster() end
    elseif event == "CHAT_MSG_ADDON" then
        receive(arg, second, third, fourth)
    elseif event:find("^CHAT_MSG_") then
        observedChat(arg, second, event:find("^CHAT_MSG_INSTANCE_CHAT") and "INSTANCE_CHAT" or "PARTY")
    elseif event == "ENCOUNTER_START" then
        pending = nil
        announce(encounterEntry(arg))
    elseif event == "PLAYER_REGEN_ENABLED" then
        pending = nil
        refreshRoster()
        if helloNeeded or not discoverySent then discovery(true) end
        for id in pairs(unsynced) do
            if not sendAddon("D:" .. id) then break end
            unsynced[id] = nil
        end
        checkNearbyTarget()
    elseif event == "ENCOUNTER_END" then
        pending = nil
    elseif event == "PLAYER_TARGET_CHANGED" then
        pending = nil
        if InCombatLockdown() then checkCombat() else checkNearbyTarget() end
    elseif event == "PLAYER_STOPPED_MOVING" then
        checkNearbyTarget()
    elseif event == "UNIT_FLAGS" or event == "UNIT_TARGET" then
        if readable(arg) and type(arg) == "string" and
            (arg == "player" or arg == "target" or arg:match("^party[1-4]$") or arg:match("^boss[1-5]$")) then
            checkCombat()
        end
    else
        checkCombat()
    end
end)
for _, event in ipairs({
    "PLAYER_LOGIN", "PLAYER_ENTERING_WORLD", "GROUP_ROSTER_UPDATE", "PLAYER_ROLES_ASSIGNED",
    "CHAT_MSG_ADDON", "CHAT_MSG_PARTY", "CHAT_MSG_PARTY_LEADER",
    "CHAT_MSG_INSTANCE_CHAT", "CHAT_MSG_INSTANCE_CHAT_LEADER",
    "ENCOUNTER_START", "ENCOUNTER_END", "INSTANCE_ENCOUNTER_ENGAGE_UNIT", "PLAYER_REGEN_DISABLED",
    "PLAYER_REGEN_ENABLED", "PLAYER_TARGET_CHANGED", "PLAYER_STOPPED_MOVING", "UNIT_FLAGS", "UNIT_TARGET",
}) do
    pcall(frame.RegisterEvent, frame, event)
end
