-- Extract numeric spell and recipe facts from the pinned What's Training Forever catalogues.
local folder = assert(arg[1], "Supply the What's Training source directory")
local guide = {L={}}
local rows = {}
local function read(path, target)
    local chunk = assert(loadfile(folder .. "/" .. path .. ".lua"))
    setfenv(chunk, {})
    chunk(nil, target)
end

for _, name in ipairs({"Druid", "Hunter", "Mage", "Paladin", "Priest", "Rogue", "Shaman", "Warlock", "Warrior"}) do
    local class = {}
    read("Classes/Camelot/" .. name, {forClass=function() return class end})
    for level, spells in pairs(class.spellsByLevel) do
        for _, spell in ipairs(spells) do
            local required = {}
            for _, id in ipairs(spell.requiredIds or {}) do required[id] = true end
            if spell.requiredTalentId then required[spell.requiredTalentId] = true end
            local ids = {}
            for id in pairs(required) do ids[#ids+1] = id end
            table.sort(ids)
            local skill = spell.skills and spell.skills[1]
            rows[spell.id] = {spell.id, spell.cost, level, skill and skill.skill or "", skill and skill.level or "",
                spell.race or "", spell.faction or "", table.concat(ids, ",")}
        end
    end
end
for _, name in ipairs({"Alchemy", "Blacksmithing", "Cooking", "Enchanting", "Engineering", "FirstAid",
    "Fishing", "Herbalism", "Leatherworking", "Mining", "Skinning", "Tailoring"}) do
    read("Crafting/Recipes/Camelot/" .. name, guide)
end
for skill, list in pairs(guide.Recipes) do
    for _, recipe in ipairs(list) do
        for _, source in ipairs(recipe.source or {}) do
            if source == "trainer" and not rows[recipe.spell] then
                rows[recipe.spell] = {recipe.spell, recipe.cost or "", recipe.level or "", skill,
                    recipe.skill or "", "", "", ""}
            end
        end
    end
end
local ids = {}
for id in pairs(rows) do ids[#ids+1] = id end
table.sort(ids)
print("spell\tcost\tlevel\tskill\trank\trace\tfaction\trequires")
for _, id in ipairs(ids) do print(table.concat(rows[id], "\t")) end
