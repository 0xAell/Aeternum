local _, addon = ...
local Trainers = {}
addon.Trainers = Trainers

-- SkillLineAbility.ClassMask from Forever build 1.60.1.71139, keyed by the
-- proficiency spell the weapon master teaches. See DATA_SOURCES.md.
local weaponClasses = {
    [196]=79, [197]=71, [198]=1115, [199]=1091, [200]=1031, [201]=399, [202]=7,
    [227]=1493, [264]=13, [266]=13, [1180]=1501, [2567]=13, [5011]=13, [15590]=1101,
}
local function fitsClass(id)
    local classes = weaponClasses[id]
    local player = addon.Data.classMasks[select(2, UnitClass("player"))]
    return not classes or not player or classes % (2 * player) >= player
end

local professions
local function readProfessions()
    if not GetProfessions or not GetProfessionInfo then return end
    local known = {}
    local function collect(...)
        for i = 1, select("#", ...) do
            local index = select(i, ...)
            if type(index) == "number" and index > 0 then
                local _, _, _, _, _, _, skillID = GetProfessionInfo(index)
                if skillID then known[skillID] = true end
            end
        end
    end
    collect(GetProfessions())
    return known
end

function Trainers:Invalidate() professions = nil end

function Trainers:Relevant(npc)
    if npc.kind == "class" then return npc.classToken == select(2, UnitClass("player")) end
    if npc.kind == "weapon" then
        local data = addon.classicTraining
        local list = data.catalogues[data.trainers[npc.id]]
        if not list then return true end
        for id in list:gmatch("(%d+):%d+:%d+:%d+:%d+") do
            if fitsClass(tonumber(id)) then return true end
        end
        return next(AeternumTrainerDB[npc.id] or {}) ~= nil
    end
    if npc.kind == "profession" then
        professions = professions or readProfessions()
        if professions then return professions[npc.skillID] end
        if C_SkillInfo and C_SkillInfo.GetSkillLineInfoByID and npc.skillID then
            local skill = C_SkillInfo.GetSkillLineInfoByID(npc.skillID)
            return skill and skill.rank > 0
        end
    end
    return true
end

local function readable(value) return not issecretvalue or not issecretvalue(value) end
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
                petPoints = pet or nil,
                level = level, skill = skill, requirement = requirement}
        end
    end
end

local function localized(id, fallback)
    return C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(id) or fallback
end

function Trainers:Lessons(npcID)
    local data, classic = addon.Data, addon.classicTraining
    local byID, byName, result = {}, {}, {}
    local catalogue = classic.catalogues[classic.trainers[npcID]] or ""
    for id, cost, level, skill, need in catalogue:gmatch("(%d+):(%d+):(%d+):(%d+):(%d+)") do
        id = tonumber(id)
        local name, rank = classic.spells[id]:match("^(.-)|(.*)$")
        if (addon.settings.otherTrainers or fitsClass(id))
            and (not C_Spell or not C_Spell.DoesSpellExist or C_Spell.DoesSpellExist(id)) then
            byID[id] = {id=id, name=localized(id, name), rank=rank, cost=tonumber(cost), level=tonumber(level),
                skill=data.professions[tonumber(skill)], requirement=tonumber(need), source="Classic reference"}
        end
    end
    for raw, cost in (data.offers[npcID] or ""):gmatch("(%d+):(%d*)") do
        local id = tonumber(raw)
        local name, rank, level, skill, need, faction = data.lessons[id]:match("^(.-)|(.-)|(.-)|(.-)|(.-)|(.*)$")
        if faction == "" or faction == UnitFactionGroup("player") then
            byID[id] = {id=id, name=localized(id, name), rank=rank ~= "" and ("Rank " .. rank) or "",
                cost=tonumber(cost), level=tonumber(level), skill=data.professions[tonumber(skill)],
                requirement=tonumber(need), source="Bundled trainer record"}
        else
            byID[id] = nil
        end
    end
    for id, row in pairs(byID) do byName[key(row.name, row.rank)] = id end
    for _, seen in pairs(AeternumTrainerDB[npcID] or {}) do
        local id = seen.id or byName[key(seen.name, seen.rank)] or key(seen.name, seen.rank)
        local row = byID[id] or {}
        for field, value in pairs(seen) do row[field] = value end
        if seen.cost ~= nil then row.source = "Last visit" end
        row.source = row.source or "Last visit"
        byID[id] = row
    end
    for _, row in pairs(byID) do result[#result + 1] = row end
    table.sort(result, function(a, b)
        local x, y = a.level or 0, b.level or 0
        if x ~= y then return x < y end
        x, y = a.requirement or 0, b.requirement or 0
        if x ~= y then return x < y end
        if a.name ~= b.name then return a.name < b.name end
        return tostring(a.rank or "") < tostring(b.rank or "")
    end)
    return result
end
