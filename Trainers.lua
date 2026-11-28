local _, addon = ...
local Trainers = {}
addon.Trainers = Trainers

-- SkillLineAbility.ClassMask from Forever build 1.60.1.71139, keyed by the
-- proficiency spell the weapon master teaches. See DATA_SOURCES.md.
local weaponClasses = {
    [196]=79, [197]=71, [198]=1115, [199]=1091, [200]=1031, [201]=399, [202]=7,
    [227]=1493, [264]=13, [266]=13, [1180]=1501, [2567]=13, [5011]=13, [15590]=1101,
}
local professionByName = {}
for id, name in pairs(addon.Data.professions or {}) do
    professionByName[name] = id
end

local function fitsClass(id)
    local classes = weaponClasses[id]
    if not classes then return true end
    local player = addon.Data.classMasks[select(2, UnitClass("player"))]
    return not player or classes % (2 * player) >= player
end

local function readable(value) return not issecretvalue or not issecretvalue(value) end
local professions
local function readProfessions()
    if not GetProfessions or not GetProfessionInfo then return end
    local known = {}
    local function collect(...)
        for i = 1, select("#", ...) do
            local index = select(i, ...)
            if addon.IsReadableNumber(index) and index > 0 then
                local _, _, rank, _, _, _, skillID = GetProfessionInfo(index)
                if addon.IsReadableNumber(skillID) then
                    known[skillID] = addon.IsReadableNumber(rank) and rank or true
                end
            end
        end
    end
    collect(GetProfessions())
    return known
end

function Trainers:Invalidate() professions = nil end

-- A zero means the character lacks this profession. Nil means the client
-- cannot give a reliable rank yet, so callers leave that requirement undecided.
function Trainers:SkillRank(id)
    if not id then return end
    professions = professions or readProfessions()
    if professions and professions[id] then
        if type(professions[id]) == "number" then return professions[id] end
        return
    end
    if C_SkillInfo and C_SkillInfo.GetSkillLineInfoByID then
        local skill = C_SkillInfo.GetSkillLineInfoByID(id)
        if readable(skill) and skill and (not canaccesstable or canaccesstable(skill))
            and addon.IsReadableNumber(skill.rank) then return skill.rank end
    end
    if professions then return 0 end
end

function Trainers:Relevant(npc)
    if npc.kind == "class" then return npc.classToken == select(2, UnitClass("player")) end
    if npc.kind == "weapon" then
        local forever = addon.foreverTraining and addon.foreverTraining.offers[npc.id]
        local data = addon.classicTraining
        local list = data.catalogues[data.trainers[npc.id]]
        if not forever and not list then return true end
        if forever then
            for id in forever:gmatch("(%d+):[^;]*") do
                if fitsClass(tonumber(id)) then return true end
            end
        end
        if list then
            for id in list:gmatch("(%d+):%d+:%d+:%d+:%d+") do
                if fitsClass(tonumber(id)) then return true end
            end
        end
        return next((AeternumTrainerDB and AeternumTrainerDB[npc.id]) or {}) ~= nil
    end
    if npc.kind == "profession" then
        local rank = self:SkillRank(npc.skillID)
        return rank == nil or rank > 0
    end
    return true
end

local function key(name, rank)
    return name .. "|" .. (rank or "")
end

-- Only observe services the player actually sees. Never change a trainer filter
-- or buy anything, and never identify a trainer by the player's current target.
function Trainers:Observe()
    if not (GetNumTrainerServices and GetTrainerServiceInfo and GetTrainerServiceCost and UnitGUID) then return end
    if type(AeternumTrainerDB) ~= "table" then return end
    local guid = UnitGUID("npc")
    local npcID = readable(guid) and type(guid) == "string"
        and tonumber(guid:match("^Creature%-%d+%-%d+%-%d+%-%d+%-(%d+)%-"))
    if not npcID then return end
    local pet = C_Trainer and C_Trainer.GetTrainerType and Enum and Enum.TrainerType
        and C_Trainer.GetTrainerType() == Enum.TrainerType.Pet
    for i = 1, GetNumTrainerServices() or 0 do
        local name, state, _, level, rank = GetTrainerServiceInfo(i)
        if readable(name) and type(name) == "string" and name ~= "" and readable(state) and state ~= "header" then
            local data = C_TooltipInfo and C_TooltipInfo.GetTrainerService and C_TooltipInfo.GetTrainerService(i)
            local spell = data and readable(data) and (not canaccesstable or canaccesstable(data))
                and Enum and Enum.TooltipDataType and readable(data.type) and data.type == Enum.TooltipDataType.Spell
                and data.id
            if not readable(spell) or type(spell) ~= "number" then spell = nil end
            spell = addon.foreverTraining.serviceSpells[spell] or spell
            local cost = GetTrainerServiceCost(i)
            if state == "used" or not readable(cost) or type(cost) ~= "number" or cost < 0 then cost = nil end
            local skill, requirement
            if GetTrainerServiceSkillReq then skill, requirement = GetTrainerServiceSkillReq(i) end
            if not readable(rank) then rank = nil end
            if not readable(level) or type(level) ~= "number" then level = nil end
            if not readable(skill) or type(skill) ~= "string" then skill = nil end
            if not readable(requirement) or type(requirement) ~= "number" then requirement = nil end
            local id = key(name, rank)
            local known = AeternumTrainerDB[npcID] or {}
            AeternumTrainerDB[npcID] = known
            local previous = known[id] or {}
            known[id] = {name = name, rank = rank, id = spell or previous.id, cost = cost or previous.cost,
                petPoints = pet or nil, lastKnown = state == "used" or nil,
                level = (level and level > 0) and level or previous.level,
                skill = skill or previous.skill,
                requirement = (requirement and requirement > 0) and requirement or previous.requirement}
        end
    end
end

local function localized(id, fallback)
    local name = C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(id)
    if readable(name) and type(name) == "string" and name ~= "" then return name end
    return fallback
end

local function localizedRank(id, fallback)
    local rank = C_Spell and C_Spell.GetSpellSubtext and C_Spell.GetSpellSubtext(id)
    if readable(rank) and type(rank) == "string" and rank ~= "" then return rank end
    return fallback
end

local spellDetails = {}
local function details(id)
    if spellDetails[id] then return spellDetails[id] end
    local packed = addon.foreverTraining.spells[id]
    if not packed then return end
    local name, rank, race, faction, required = packed:match("^(.-)|(.-)|(.-)|(.-)|(.*)$")
    local spell = {name=name, rank=rank, race=tonumber(race), faction=faction ~= "" and faction or nil}
    if required ~= "" then
        spell.requires = {}
        for prior in required:gmatch("%d+") do spell.requires[#spell.requires + 1] = tonumber(prior) end
    end
    spellDetails[id] = spell
    return spell
end

local visitSources = {"EG Link trainer visit", "Zephras trainer visit", "EG Link and Zephras trainer visits",
    "EG Link beta trainer visit", "Zephras trainer visit (build unreported)", "Zephras beta trainer visit",
    "EG Link and Zephras beta trainer visits"}
local betaSources = {[4]=true, [6]=true, [7]=true}
local function addRecorded(npcID, byID)
    local list = addon.foreverTraining.offers[npcID] or ""
    for raw, level, skill, need, cost, basis, source in
        list:gmatch("(%d+):(%d*):(%d*):(%d*):(%d*):(%d*):(%d+)") do
        local id, skillID = tonumber(raw), tonumber(skill)
        local spell, previous = details(id), byID[id]
        local price, priceBasis = tonumber(cost), tonumber(basis)
        if price == nil and previous then
            price, priceBasis = previous.cost, previous.source
        end
        local skillName = addon.Data.professions[skillID] or (skillID == 40 and "Poisons")
        byID[id] = {id=id, name=localized(id, spell.name), rank=localizedRank(id, spell.rank),
            level=tonumber(level), skillID=skillID, skill=skillName,
            requirement=tonumber(need), cost=price, priceBasis=priceBasis, requires=spell.requires,
            source=visitSources[tonumber(source)], beta=betaSources[tonumber(source)]}
    end
end

function Trainers:Lessons(npcID)
    local data, classic = addon.Data, addon.classicTraining
    local byID, byName, result, blocked = {}, {}, {}, {}
    local showOther = addon.settings and addon.settings.otherTrainers
    local faction = UnitFactionGroup("player")
    local hasFaction = readable(faction) and (faction == "Alliance" or faction == "Horde")
    local race = select(3, UnitRace("player"))
    local hasRace = addon.IsReadableNumber(race) and race > 0
    local catalogue = classic.catalogues[classic.trainers[npcID]] or ""
    for id, cost, level, skill, need in catalogue:gmatch("(%d+):(%d+):(%d+):(%d+):(%d+)") do
        id = tonumber(id)
        local rawSpell = classic.spells[id]
        if rawSpell and (not C_Spell or not C_Spell.DoesSpellExist or C_Spell.DoesSpellExist(id)) then
            local name, rank = rawSpell:match("^(.-)|(.*)$")
            byID[id] = {id=id, name=localized(id, name), rank=rank, cost=tonumber(cost), level=tonumber(level),
                skillID=tonumber(skill), skill=data.professions[tonumber(skill)], requirement=tonumber(need),
                source="Classic reference"}
        end
    end
    for raw, cost in (data.offers[npcID] or ""):gmatch("(%d+):(%d*)") do
        local id = tonumber(raw)
        local rawLesson = data.lessons[id]
        if rawLesson then
            local name, rank, level, skill, need, side = rawLesson:match("^(.-)|(.-)|(.-)|(.-)|(.-)|(.*)$")
            if side == "" or not hasFaction or side == faction then
                byID[id] = {id=id, name=localized(id, name), rank=rank ~= "" and ("Rank " .. rank) or "",
                    cost=tonumber(cost), level=tonumber(level), skillID=tonumber(skill),
                    skill=data.professions[tonumber(skill)], requirement=tonumber(need),
                    source="Bundled trainer record"}
            else
                blocked[id] = true
            end
        end
    end
    addRecorded(npcID, byID)
    for id, row in pairs(byID) do byName[key(row.name, row.rank)] = id end
    for _, seen in pairs((AeternumTrainerDB and AeternumTrainerDB[npcID]) or {}) do
        local id = addon.foreverTraining.serviceSpells[seen.id] or seen.id
            or byName[key(seen.name, seen.rank)] or key(seen.name, seen.rank)
        local row = byID[id] or {}
        local level, requirement, rank = row.level, row.requirement, row.rank
        if row.cost ~= nil then row.priceBasis = row.priceBasis or row.source end
        for field, value in pairs(seen) do row[field] = value end
        if type(id) == "number" then row.id = id end
        if row.level == 0 then row.level = level end
        if row.requirement == 0 then row.requirement = requirement end
        if row.rank == "" then row.rank = rank end
        if not row.skillID and row.skill then row.skillID = professionByName[row.skill] end
        if seen.cost ~= nil then row.priceBasis = nil end
        row.source, row.beta = "Last visit", nil
        byID[id] = row
    end
    for id, row in pairs(byID) do
        local spell = details(id)
        if not blocked[id] and (showOther or fitsClass(id))
            and (not hasRace or not spell or not spell.race or spell.race == race)
            and (not hasFaction or not spell or not spell.faction or spell.faction == faction) then
            result[#result + 1] = row
        end
    end
    table.sort(result, function(a, b)
        local x, y = a.level or 0, b.level or 0
        if x ~= y then return x < y end
        x, y = a.requirement or 0, b.requirement or 0
        if x ~= y then return x < y end
        if a.name ~= b.name then return a.name < b.name end
        local rankA = tonumber((a.rank or ""):match("%d+")) or 0
        local rankB = tonumber((b.rank or ""):match("%d+")) or 0
        if rankA ~= rankB then return rankA < rankB end
        return (a.id or 0) < (b.id or 0)
    end)
    return result
end

function Trainers:LessonState(lesson)
    if lesson.id and C_SpellBook and C_SpellBook.IsSpellKnown then
        local known = C_SpellBook.IsSpellKnown(lesson.id)
        if readable(known) and known then return "learned", "Already learned" end
    end
    if lesson.lastKnown then return "learned", "Learned at last visit" end
    local level = UnitLevel("player")
    if lesson.level and addon.IsReadableNumber(level) and level < lesson.level then
        return "later", "Requires level " .. lesson.level
    end
    if lesson.skill and lesson.requirement and lesson.requirement > 0 then
        local rank = self:SkillRank(lesson.skillID or professionByName[lesson.skill])
        if rank and rank < lesson.requirement then
            return "later", ("%s %d / %d"):format(lesson.skill, rank, lesson.requirement)
        end
    end
    if lesson.requires and C_SpellBook and C_SpellBook.IsSpellKnown then
        for _, id in ipairs(lesson.requires) do
            local known = C_SpellBook.IsSpellKnown(id)
            if readable(known) and known == false then
                local prior = details(id)
                local name = localized(id, prior and prior.name or ("spell " .. id))
                local rank = localizedRank(id, prior and prior.rank)
                return "later", "Requires " .. name .. (rank and rank ~= "" and (" (" .. rank .. ")") or "")
            end
        end
    end
end
