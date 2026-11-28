local _, addon = ...

-- A skill line carries the player's trained rank. The passive spell also covers
-- proficiencies that the client omits from the Skills tab, including armor.
local proficiencySpells = {
    [43]=201, [44]=196, [45]=264, [46]=266, [54]=198, [55]=202, [118]=674, [136]=227,
    [160]=199, [172]=197, [173]=1180, [176]=2567, [226]=5011, [228]=5009, [229]=200,
    [293]=750, [413]=8737, [414]=9077, [433]=9116, [473]=15590,
}

local function knows(spell)
    if not C_SpellBook or not C_SpellBook.IsSpellKnown then return end
    local known = C_SpellBook.IsSpellKnown(spell)
    if not issecretvalue or not issecretvalue(known) then return known end
end

local function trained(id)
    local info = C_SkillInfo and C_SkillInfo.GetSkillLineInfoByID and C_SkillInfo.GetSkillLineInfoByID(id)
    if (not issecretvalue or not issecretvalue(info)) and info and (not canaccesstable or canaccesstable(info)) then
        if addon.IsReadableNumber(info.rank) and info.rank > 0 then return true end
    end
    return knows(proficiencySpells[id]) == true
end

local function hasRank(skill, rank)
    return (addon.Trainers:SkillRank(skill) or 0) >= rank
end

-- Scope the cache to one menu or search. Two characters can share the item
-- data without sharing eligibility, and skill changes take effect on the next read.
function addon.LootFilter()
    local _, token = UnitClass("player")
    local player = (not issecretvalue or not issecretvalue(token)) and token and addon.Data.classMasks[token]
    local answers = {}
    local function fits(mask)
        return not mask or (player and mask % (2 * player) >= player)
    end
    local function eligible(rule)
        if not fits(rule.classes) then return false end
        if rule.proficiency and not trained(rule.proficiency) then return false end
        if rule.dualWield and not trained(118) then return false end
        if rule.arrows and not (trained(45) or trained(226)) then return false end
        if rule.skill and not hasRank(rule.skill, rule.rank) then return false end
        if rule.ability and not knows(rule.ability) then return false end
        if rule.teaches and knows(rule.teaches) ~= false then return false end
        local quest = rule.startsQuest and addon.Quest(rule.startsQuest)
        if quest and not fits(quest.classes) then return false end
        local skill = quest and quest.requiredSkill
        return not skill or hasRank(skill[1], math.max(1, skill[2]))
    end
    return function(id)
        local rule = addon.lootRules[id]
        if not rule then return false end
        if answers[rule] == nil then answers[rule] = eligible(rule) end
        return answers[rule]
    end
end

-- Item tooltips name the bosses that drop the item, wherever the item is shown: bags, chat
-- links, the auction house, quest rewards. Only verified sources count: a boss's own recorded
-- drops and its encounter rolls. Other recorded drops may come from anywhere, and guide-listed
-- items are unconfirmed.
local MAX_SOURCES = 3
local sources

local function addSource(itemID, boss, dungeon)
    local list = sources[itemID]
    if not list then
        list = {}
        sources[itemID] = list
    end
    for _, known in ipairs(list) do
        if known.boss == boss.name and known.dungeon == dungeon.name then return end
    end
    list[#list + 1] = {boss = boss.name, dungeon = dungeon.name}
end

function addon.ItemSources(itemID)
    if not sources then
        sources = {}
        for _, dungeon in ipairs(addon.Data.dungeons) do
            for _, boss in ipairs(dungeon.bosses) do
                local sections = boss.lootSections or {}
                local unverified = {}
                for _, name in ipairs({"other", "guide"}) do
                    local start = sections[name]
                    if start then
                        -- A section runs until the next section starts.
                        local stop = #boss.loot + 1
                        for _, other in pairs(sections) do
                            if other > start and other < stop then stop = other end
                        end
                        for index = start, stop - 1 do unverified[index] = true end
                    end
                end
                for index, id in ipairs(boss.loot) do
                    if not unverified[index] then addSource(id, boss, dungeon) end
                end
            end
        end
    end
    return sources[itemID]
end

local function addDropLines(tooltip, data)
    if tooltip ~= GameTooltip and tooltip ~= ItemRefTooltip then return end
    if not data or (canaccesstable and not canaccesstable(data)) then return end
    local id = data.id
    if not addon.IsReadableNumber(id) then return end
    local list = addon.ItemSources(id)
    if not list then return end
    for index = 1, math.min(#list, MAX_SOURCES) do
        local source = list[index]
        local label = index == 1 and "|cffffd100Drops from|r " or "|cffffd100      or|r "
        tooltip:AddLine(label .. source.boss .. " · " .. source.dungeon, 1, 1, 1)
    end
    if #list > MAX_SOURCES then
        tooltip:AddLine(("|cffffd100      and %d more bosses|r"):format(#list - MAX_SOURCES))
    end
end

if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, addDropLines)
end
