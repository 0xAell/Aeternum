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
