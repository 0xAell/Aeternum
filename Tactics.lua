local _, addon = ...
local Tactics = {}
addon.Tactics = Tactics

local TACTICS_ICON = "|T133741:16:16:0:0:64:64:4:60:4:60|t"

local ROLE_ICON = {
    tank   = "|TInterface\\LFGFrame\\UI-LFG-ICON-PORTRAITROLES:14:14:0:0:64:64:0:19:22:41|t",
    healer = "|TInterface\\LFGFrame\\UI-LFG-ICON-PORTRAITROLES:14:14:0:0:64:64:20:39:1:20|t",
    dps    = "|TInterface\\LFGFrame\\UI-LFG-ICON-PORTRAITROLES:14:14:0:0:64:64:20:39:22:41|t",
}

-- Dispel and threat tags colored to match Blizzard's DebuffTypeColor conventions.
local DISPEL = {
    magic     = { label = "Magic",      hex = "3399ff" },
    magicBuff = { label = "Magic buff", hex = "66ccff" },
    curse     = { label = "Curse",      hex = "b566ff" },
    disease   = { label = "Disease",    hex = "c89646" },
    poison    = { label = "Poison",     hex = "00cc33" },
    enrage    = { label = "Enrage",     hex = "ff5555" },
    bleed     = { label = "Bleed",      hex = "e06666" },
}

local CLASS_INFO = {
    WARRIOR = { name = "Warrior", hex = "c69b6d" },
    PALADIN = { name = "Paladin", hex = "f48cba" },
    HUNTER  = { name = "Hunter",  hex = "aad372" },
    ROGUE   = { name = "Rogue",   hex = "fff468" },
    PRIEST  = { name = "Priest",  hex = "ffffff" },
    SHAMAN  = { name = "Shaman",  hex = "0070dd" },
    MAGE    = { name = "Mage",    hex = "3fc7eb" },
    WARLOCK = { name = "Warlock", hex = "8788ee" },
    DRUID   = { name = "Druid",   hex = "ff7c0a" },
}

-- Verified Forever 1.60.1.71139 SpellIconFileDataIDs and English spell names.
-- Used as fallbacks when C_Spell.GetSpellTexture is unavailable or uncached.
local SPELLS = {
    -- Shaman
    [8143]  = { 136108, "Tremor Totem" },
    [8177]  = { 136039, "Grounding Totem" },
    [8166]  = { 136070, "Poison Cleansing Totem" },
    [8170]  = { 136019, "Disease Cleansing Totem" },
    [8042]  = { 136026, "Earth Shock" },
    [370]   = { 136075, "Purge" },
    [526]   = { 136067, "Cure Poison" },
    [2870]  = { 136083, "Cure Disease" },
    [2484]  = { 136102, "Earthbind Totem" },
    [5730]  = { 136097, "Stoneclaw Totem" },
    [8184]  = { 135832, "Fire Resistance Totem" },
    [8181]  = { 135866, "Frost Resistance Totem" },
    [10595] = { 136061, "Nature Resistance Totem" },
    -- Paladin
    [4987]  = { 135953, "Cleanse" },
    [1152]  = { 135949, "Purify" },
    [1022]  = { 135964, "Blessing of Protection" },
    [1044]  = { 135968, "Blessing of Freedom" },
    [853]   = { 135963, "Hammer of Justice" },
    [2878]  = { 135983, "Turn Undead" },
    [642]   = { 135896, "Divine Shield" },
    [6940]  = { 135966, "Blessing of Sacrifice" },
    [19876] = { 136192, "Shadow Resistance Aura" },
    [19888] = { 135865, "Frost Resistance Aura" },
    [19891] = { 135824, "Fire Resistance Aura" },
    -- Priest
    [527]   = { 135894, "Dispel Magic" },
    [552]   = { 136066, "Abolish Disease" },
    [528]   = { 135935, "Cure Disease" },
    [6346]  = { 135902, "Fear Ward" },
    [9484]  = { 136091, "Shackle Undead" },
    [15487] = { 136164, "Silence" },
    [586]   = { 135994, "Fade" },
    [596]   = { 135943, "Prayer of Healing" },
    [17]    = { 135940, "Power Word: Shield" },
    [976]   = { 136121, "Shadow Protection" },
    -- Mage
    [475]   = { 136082, "Remove Lesser Curse" },
    [2139]  = { 135856, "Counterspell" },
    [118]   = { 136071, "Polymorph" },
    [11958] = { 135841, "Ice Block" },
    [122]   = { 135848, "Frost Nova" },
    [1953]  = { 135736, "Blink" },
    [6143]  = { 135850, "Frost Ward" },
    [543]   = { 135806, "Fire Ward" },
    -- Rogue
    [1766]  = { 132219, "Kick" },
    [408]   = { 132298, "Kidney Shot" },
    [1776]  = { 132155, "Gouge" },
    [2094]  = { 136175, "Blind" },
    [6770]  = { 132310, "Sap" },
    [5277]  = { 136205, "Evasion" },
    [1856]  = { 132331, "Vanish" },
    [1966]  = { 132294, "Feint" },
    -- Warrior
    [6552]  = { 132938, "Pummel" },
    [72]    = { 132357, "Shield Bash" },
    [18499] = { 136009, "Berserker Rage" },
    [676]   = { 132343, "Disarm" },
    [355]   = { 136080, "Taunt" },
    [694]   = { 132350, "Mocking Blow" },
    [1161]  = { 132091, "Challenging Shout" },
    [871]   = { 132362, "Shield Wall" },
    [1160]  = { 132366, "Demoralizing Shout" },
    -- Druid
    [2893]  = { 136068, "Abolish Poison" },
    [8946]  = { 136067, "Cure Poison" },
    [2782]  = { 135952, "Remove Curse" },
    [5211]  = { 132114, "Bash" },
    [16979] = { 132183, "Feral Charge" },
    [2637]  = { 136090, "Hibernate" },
    [339]   = { 136100, "Entangling Roots" },
    [740]   = { 136107, "Tranquility" },
    [22812] = { 136097, "Barkskin" },
    [6795]  = { 132270, "Growl" },
    [99]    = { 132121, "Demoralizing Roar" },
    -- Hunter
    [19801] = { 136020, "Tranquilizing Shot" },
    [1499]  = { 135834, "Freezing Trap" },
    [5384]  = { 132293, "Feign Death" },
    [19503] = { 132153, "Scatter Shot" },
    [20736] = { 135736, "Distracting Shot" },
    [3034]  = { 132157, "Viper Sting" },
    [1543]  = { 135815, "Flare" },
    [20043] = { 136074, "Aspect of the Wild" },
    [19577] = { 132111, "Intimidation" },
    -- Warlock
    [19505] = { 136075, "Devour Magic" },
    [19244] = { 136174, "Spell Lock" },
    [710]   = { 136135, "Banish" },
    [1714]  = { 136140, "Curse of Tongues" },
    [702]   = { 136138, "Curse of Weakness" },
    [5782]  = { 136183, "Fear" },
    [6358]  = { 136175, "Seduction" },
    [6229]  = { 136121, "Shadow Ward" },
    [20707] = { 136210, "Soulstone Resurrection" },
    -- Racials
    [20594] = { 136225, "Stoneform" },
    [7744]  = { 136187, "Will of the Forsaken" },
}

local function formatTag(key)
    local info = DISPEL[key]
    if not info then return "{" .. key .. "}" end
    return ("|cff%s%s|r"):format(info.hex, info.label)
end

function Tactics:FormatText(text)
    if type(text) ~= "string" then return "" end
    return (text:gsub("{(%a+)}", formatTag))
end

function Tactics:ForBoss(bossID)
    return addon.tacticsData and bossID and addon.tacticsData[bossID] or nil
end

function Tactics:DispelText(entry)
    if not entry or not entry.dispels or #entry.dispels == 0 then return nil end
    local parts = {}
    for _, key in ipairs(entry.dispels) do
        if DISPEL[key] then parts[#parts + 1] = formatTag(key) end
    end
    return #parts > 0 and table.concat(parts, " · ") or nil
end

local function spellTexture(spellID)
    if C_Spell and C_Spell.GetSpellTexture then
        local texture = C_Spell.GetSpellTexture(spellID)
        if addon.IsReadableNumber(texture) or (type(texture) == "string" and texture ~= "") then
            return texture
        end
    end
    local info = SPELLS[spellID]
    return info and info[1] or nil
end

function Tactics:SpellIcon(spellID, size)
    local texture = spellTexture(spellID)
    if not texture then return "" end
    size = size or 14
    return ("|T%s:%d:%d:0:0:64:64:4:60:4:60|t"):format(tostring(texture), size, size)
end

function Tactics:SpellName(spellID)
    local info = SPELLS[spellID]
    return info and info[2] or ("Spell " .. tostring(spellID))
end

local function spellKnown(spellID)
    if not (C_SpellBook and C_SpellBook.IsSpellKnown) then return false end
    local known = C_SpellBook.IsSpellKnown(spellID)
    if issecretvalue and issecretvalue(known) then return false end
    return known == true
end

local function playerContext()
    local classFile
    if UnitClass then
        local _, token = UnitClass("player")
        if not (issecretvalue and issecretvalue(token)) and CLASS_INFO[token] then
            classFile = token
        end
    end
    local raceFile, raceID
    if UnitRace then
        local _, token, id = UnitRace("player")
        if not (issecretvalue and issecretvalue(token)) and type(token) == "string" then raceFile = token end
        if addon.IsReadableNumber(id) then raceID = id end
    end
    local level = 60
    if UnitLevel then
        local raw = UnitLevel("player")
        if addon.IsReadableNumber(raw) and raw > 0 then level = raw end
    end
    return classFile, CLASS_INFO[classFile], raceFile == "Dwarf" or raceID == 3,
        raceFile == "Scourge" or raceID == 5, level
end

function Tactics:PlayerClass()
    local classFile, info = playerContext()
    return classFile, info
end

local function tagSet(entry)
    local has = {}
    for _, tag in ipairs(entry.tags or {}) do has[tag] = true end
    for _, key in ipairs(entry.dispels or {}) do has[key] = true end
    return has
end

local function joinWords(words, sep)
    if #words == 0 then return "" end
    if #words == 1 then return words[1] end
    if #words == 2 then return words[1] .. sep .. words[2] end
    return table.concat(words, ", ", 1, #words - 1) .. sep .. words[#words]
end

local function ccTypes(has)
    local list = {}
    if has.fear then list[#list + 1] = "Fear" end
    if has.sleep then list[#list + 1] = "Sleep" end
    if has.charm then list[#list + 1] = "Charm" end
    return joinWords(list, "/")
end

local function pushTip(tips, seen, spellID, text)
    if #tips >= 4 or seen[spellID] then return end
    seen[spellID] = true
    tips[#tips + 1] = {
        spellID = spellID,
        name = Tactics:SpellName(spellID),
        icon = Tactics:SpellIcon(spellID, 14),
        text = Tactics:FormatText(text),
    }
end

local function buildClassTips(classFile, entry, has, isDwarf, level, tips, seen)
    local kick = entry.kick or "priority casts"
    local purge = entry.purge and (" (" .. entry.purge .. ")") or ""

    if classFile == "SHAMAN" then
        if has.fear or has.sleep or has.charm then
            pushTip(tips, seen, 8143, "Drop Tremor Totem to break " .. ccTypes(has) .. ".")
        end
        if has.poison then
            pushTip(tips, seen, 8166, "Drop Poison Cleansing Totem to clear {poison}.")
        end
        if has.disease then
            pushTip(tips, seen, 8170, "Drop Disease Cleansing Totem to clear {disease}.")
        end
        if has.magicBuff then
            pushTip(tips, seen, 370, "Purge enemy {magicBuff}" .. purge .. ".")
        end
        if has.interrupt then
            pushTip(tips, seen, 8042, "Interrupt " .. kick .. " with Earth Shock.")
        end
        if has.fire then pushTip(tips, seen, 8184, "Drop Fire Resistance Totem to soften Fire damage.") end
        if has.frost then pushTip(tips, seen, 8181, "Drop Frost Resistance Totem to soften Frost damage.") end
        if has.nature then pushTip(tips, seen, 10595, "Drop Nature Resistance Totem for party Nature damage.") end
        if has.caster or has.magic then
            pushTip(tips, seen, 8177, "Drop Grounding Totem to soak single-target spells.")
        end
        if #tips == 0 then
            if has.adds or has.root or has.snare then
                pushTip(tips, seen, 2484, "Use Earthbind Totem to slow adds or runners.")
            else
                pushTip(tips, seen, 8177, "Keep totems positioned safely; drop Stoneclaw/Grounding if needed.")
            end
        end

    elseif classFile == "PALADIN" then
        if has.magic or has.poison or has.disease then
            local types = {}
            if has.magic then types[#types + 1] = "{magic}" end
            if has.poison then types[#types + 1] = "{poison}" end
            if has.disease then types[#types + 1] = "{disease}" end
            local usePurify = not has.magic and level < 42 and not spellKnown(4987)
            local spellID = usePurify and 1152 or 4987
            local verb = usePurify and "Purify " or "Cleanse "
            pushTip(tips, seen, spellID, verb .. joinWords(types, " and ") .. " debuffs promptly.")
        end
        if has.bleed or has.physicalBurst then
            pushTip(tips, seen, 1022, "Blessing of Protection clears {bleed} or saves a focused ally.")
        end
        if has.root or has.snare then
            pushTip(tips, seen, 1044, "Blessing of Freedom frees rooted or snared party members.")
        end
        if has.interrupt then
            pushTip(tips, seen, 853, "Stun " .. kick .. " (or priority adds) with Hammer of Justice.")
        end
        if has.undead and has.adds then
            pushTip(tips, seen, 2878, "Turn Undead can temporarily control an extra undead add.")
        end
        if has.fire then pushTip(tips, seen, 19891, "Run Fire Resistance Aura to reduce party Fire damage.") end
        if has.frost then pushTip(tips, seen, 19888, "Run Frost Resistance Aura to reduce party Frost damage.") end
        if has.shadow then pushTip(tips, seen, 19876, "Run Shadow Resistance Aura to reduce party Shadow damage.") end
        if #tips == 0 then
            pushTip(tips, seen, 6940, "Use Blessing of Sacrifice on tank spikes; save Divine Shield for emergencies.")
        end

    elseif classFile == "PRIEST" then
        if has.fear and isDwarf then
            pushTip(tips, seen, 6346, "Keep Fear Ward on the tank before Fear casts.")
        end
        if has.magic and has.magicBuff then
            pushTip(tips, seen, 527, "Dispel {magic} on party and strip enemy {magicBuff}" .. purge .. ".")
        elseif has.magic then
            pushTip(tips, seen, 527, "Dispel {magic} debuffs from tank and party promptly.")
        elseif has.magicBuff then
            pushTip(tips, seen, 527, "Offensive Dispel Magic strips enemy {magicBuff}" .. purge .. ".")
        end
        if has.disease then
            local useCure = level < 32 and not spellKnown(552)
            local spellID = useCure and 528 or 552
            local verb = useCure and "Cure Disease" or "Abolish Disease"
            pushTip(tips, seen, spellID, "Use " .. verb .. " to clear {disease} debuffs.")
        end
        if has.undead and has.adds then
            pushTip(tips, seen, 9484, "Shackle Undead locks down an extra undead add.")
        end
        if has.shadow then
            pushTip(tips, seen, 976, "Buff Shadow Protection on the party before pulling.")
        end
        if has.interrupt then
            pushTip(tips, seen, 15487, "Shadow Priests can Silence " .. kick .. ".")
        end
        if has.aoe then
            pushTip(tips, seen, 596, "Pre-shield fragile targets and use Prayer of Healing after AoE.")
        end
        if #tips == 0 then
            pushTip(tips, seen, 586, "Use Fade on add spawns or threat resets; shield focused targets.")
        end

    elseif classFile == "MAGE" then
        if has.curse then
            pushTip(tips, seen, 475, "Decurse {curse} immediately with Remove Lesser Curse.")
        end
        if has.interrupt then
            pushTip(tips, seen, 2139, "Counterspell " .. kick .. " on cooldown.")
        end
        if has.adds and (has.humanoid or has.beast) then
            pushTip(tips, seen, 118, "Polymorph an extra humanoid/beast add to simplify the pull.")
        end
        if has.frost then pushTip(tips, seen, 6143, "Keep Frost Ward up to absorb incoming Frost bursts.") end
        if has.fire then pushTip(tips, seen, 543, "Keep Fire Ward up to absorb incoming Fire bursts.") end
        if has.root or has.snare or has.knockback then
            pushTip(tips, seen, 1953, "Blink out of roots, snares, or dangerous ground effects.")
        end
        if has.adds then
            pushTip(tips, seen, 122, "Frost Nova loose melee adds away from the healer.")
        end
        if #tips == 0 then
            pushTip(tips, seen, 11958, "Save Ice Block to drop aggro, clear debuffs, or survive bursts.")
        end

    elseif classFile == "ROGUE" then
        if has.interrupt then
            pushTip(tips, seen, 1766, "Kick " .. kick .. " reliably on cooldown.")
        end
        if has.adds and has.humanoid then
            pushTip(tips, seen, 6770, "Sap an extra humanoid add pre-pull; Blind loose adds if needed.")
        elseif has.adds or has.caster then
            pushTip(tips, seen, 408, "Use Kidney Shot / Gouge to lock down priority adds or casts.")
        end
        if has.threatDrop or has.cleave or has.physicalBurst then
            pushTip(tips, seen, 1966, "Stay behind the boss and Feint to avoid pulling aggro.")
        end
        if has.root or has.snare then
            pushTip(tips, seen, 1856, "Vanish can break roots/snares or drop aggro in emergencies.")
        end
        if #tips == 0 then
            pushTip(tips, seen, 5277, "Stay behind the boss; pop Evasion or Vanish if you pull threat.")
        end

    elseif classFile == "WARRIOR" then
        if has.fear then
            pushTip(tips, seen, 18499, "Pop Berserker Rage before or during Fear to stay on the boss.")
        end
        if has.interrupt then
            pushTip(tips, seen, 6552, "Interrupt " .. kick .. " with Pummel or Shield Bash.")
        end
        if has.disarmable then
            pushTip(tips, seen, 676, "Disarm the boss to slash heavy weapon and cleave damage.")
        end
        if has.physicalBurst or has.enrage then
            pushTip(tips, seen, 871, "Save Shield Wall for heavy physical bursts or {enrage}.")
        end
        if has.adds then
            pushTip(tips, seen, 1161, "Pick up adds quickly; use Challenging Shout if mobs scatter.")
        end
        if has.threatDrop or has.knockback then
            pushTip(tips, seen, 355, "Hold Taunt / Mocking Blow ready after threat drops or knockbacks.")
        end
        if #tips == 0 then
            pushTip(tips, seen, 1160, "Keep Demoralizing Shout up; face boss away if tanking, behind if DPS.")
        end

    elseif classFile == "DRUID" then
        if has.poison then
            local useCure = level < 26 and not spellKnown(2893)
            local spellID = useCure and 8946 or 2893
            local verb = useCure and "Cure Poison" or "Abolish Poison"
            pushTip(tips, seen, spellID, "Keep " .. verb .. " rolling to clear {poison}.")
        end
        if has.curse then
            pushTip(tips, seen, 2782, "Decurse {curse} promptly with Remove Curse.")
        end
        if has.interrupt then
            pushTip(tips, seen, 16979, "Interrupt " .. kick .. " with Feral Charge or Bash.")
        end
        if has.adds and (has.beast or has.dragonkin) then
            pushTip(tips, seen, 2637, "Hibernate an extra beast or dragonkin add.")
        end
        if has.aoe then
            pushTip(tips, seen, 740, "Save Barkskin + Tranquility for heavy group AoE phases.")
        end
        if has.physicalBurst or has.cleave or has.enrage then
            pushTip(tips, seen, 99, "Keep Demoralizing Roar up as bear; use Barkskin on spikes.")
        end
        if has.threatDrop then
            pushTip(tips, seen, 6795, "Bear tanks hold Growl ready after threat drops.")
        end
        if #tips == 0 then
            pushTip(tips, seen, 22812, "Use Barkskin for incoming bursts; Bash priority adds if loose.")
        end

    elseif classFile == "HUNTER" then
        if has.enrage then
            pushTip(tips, seen, 19801, "Strip {enrage} with Tranquilizing Shot (once learned at 60).")
        end
        if has.stealth then
            pushTip(tips, seen, 1543, "Drop Flare to reveal stealthed ambushes early.")
        end
        if has.adds then
            pushTip(tips, seen, 1499, "Freezing Trap an add on pull; Distracting Shot loose mobs off healer.")
        end
        if has.nature then
            pushTip(tips, seen, 20043, "Swap to Aspect of the Wild to cut party Nature damage.")
        end
        if has.interrupt then
            pushTip(tips, seen, 19503, "Disrupt " .. kick .. " with Scatter Shot or Intimidation.")
        end
        if has.caster then
            pushTip(tips, seen, 3034, "Apply Viper Sting on long caster fights to drain boss mana.")
        end
        if #tips == 0 then
            pushTip(tips, seen, 5384, "Feign Death to shed threat safely; keep pet out of cleaves and AoE.")
        end

    elseif classFile == "WARLOCK" then
        if has.magic and has.magicBuff then
            pushTip(tips, seen, 19505, "Felhunter Devour Magic clears {magic} and strips {magicBuff}" .. purge .. ".")
        elseif has.magic then
            pushTip(tips, seen, 19505, "Felhunter Devour Magic can dispel {magic} debuffs.")
        elseif has.magicBuff then
            pushTip(tips, seen, 19505, "Felhunter Devour Magic strips enemy {magicBuff}" .. purge .. ".")
        end
        if has.interrupt then
            pushTip(tips, seen, 19244, "Use Felhunter Spell Lock to interrupt " .. kick .. ".")
        end
        if has.adds and (has.demon or has.elemental) then
            pushTip(tips, seen, 710, "Banish an extra demon or elemental add.")
        end
        if has.caster then
            pushTip(tips, seen, 1714, "Apply Curse of Tongues to slow boss spellcasts.")
        end
        if has.shadow then
            pushTip(tips, seen, 6229, "Keep Shadow Ward up to absorb incoming Shadow bursts.")
        end
        if has.adds and has.humanoid then
            pushTip(tips, seen, 6358, "Succubus Seduction can CC an extra humanoid add.")
        end
        if has.physicalBurst or has.cleave or has.enrage then
            pushTip(tips, seen, 702, "Curse of Weakness helps soften heavy physical hits.")
        end
        if #tips == 0 then
            pushTip(tips, seen, 20707, "Keep Soulstone on the healer and watch threat on burst pulls.")
        end
    end
end

function Tactics:ClassTips(bossID)
    local entry = self:ForBoss(bossID)
    local classFile, classInfo, isDwarf, isUndead, level = playerContext()
    if not entry or not classFile then return {}, classFile, classInfo end
    local has = tagSet(entry)
    local tips, seen = {}, {}

    if entry.c and entry.c[classFile] then
        for _, override in ipairs(entry.c[classFile]) do
            pushTip(tips, seen, override[1], override[2])
        end
    end

    buildClassTips(classFile, entry, has, isDwarf, level, tips, seen)

    -- High-impact racial counters when applicable and room permits.
    if isDwarf and (has.poison or has.disease or has.bleed) then
        local types = {}
        if has.poison then types[#types + 1] = "{poison}" end
        if has.disease then types[#types + 1] = "{disease}" end
        if has.bleed then types[#types + 1] = "{bleed}" end
        pushTip(tips, seen, 20594, "Stoneform clears " .. joinWords(types, "/") .. " and boosts armor.")
    elseif isUndead and (has.fear or has.sleep or has.charm) then
        pushTip(tips, seen, 7744, "Will of the Forsaken breaks " .. ccTypes(has) .. ".")
    end

    return tips, classFile, classInfo
end

function Tactics:AddTooltip(tooltip, boss, full)
    local entry = boss and self:ForBoss(boss.id)
    if not entry then return end
    local dispels = self:DispelText(entry)
    local tips, _, classInfo = self:ClassTips(boss.id)

    if full then
        tooltip:SetText(boss.name .. " — Tactics")
        if dispels then
            tooltip:AddLine("Dispels: " .. dispels, 1, 1, 1, true)
        end
        if classInfo and #tips > 0 then
            tooltip:AddLine(" ")
            tooltip:AddLine(("|cff%s%s TLDR:|r"):format(classInfo.hex, classInfo.name))
            for _, tip in ipairs(tips) do
                tooltip:AddLine(tip.icon .. " " .. tip.text, 1, 1, 1, true)
            end
        end
        tooltip:AddLine(" ")
        tooltip:AddLine(ROLE_ICON.tank .. " |cff66b3ffTank:|r " .. self:FormatText(entry.t), 1, 1, 1, true)
        tooltip:AddLine(ROLE_ICON.healer .. " |cff55ee66Healer:|r " .. self:FormatText(entry.h), 1, 1, 1, true)
        tooltip:AddLine(ROLE_ICON.dps .. " |cffff6655DPS:|r " .. self:FormatText(entry.d), 1, 1, 1, true)
        return
    end

    -- Compact boss skull hover preview on the dungeon map.
    if dispels then
        tooltip:AddLine("Dispels: " .. dispels, 1, 1, 1, true)
    end
    if classInfo and #tips > 0 then
        tooltip:AddLine(("|cff%s%s:|r"):format(classInfo.hex, classInfo.name))
        local limit = math.min(#tips, 2)
        for i = 1, limit do
            tooltip:AddLine(tips[i].icon .. " " .. tips[i].text, .95, .95, .95, true)
        end
    end
end

local function roleRow(menu, boss, icon, colorHex, roleLabel, text, dispels)
    local row = menu:CreateButton(("%s |cff%s%s TLDR|r"):format(icon, colorHex, roleLabel))
    row:SetTooltip(function(tooltip)
        tooltip:SetText(boss.name .. " — " .. roleLabel)
        if dispels then tooltip:AddLine("Dispels: " .. dispels, 1, 1, 1, true) end
        tooltip:AddLine(text, 1, 1, 1, true)
    end)
    return row
end

function Tactics:AddMenu(menu, boss, linkSpell)
    local entry = boss and self:ForBoss(boss.id)
    if not entry then return nil end
    local dispels = self:DispelText(entry)
    local label = TACTICS_ICON .. " Tactics" .. (dispels and (" · " .. dispels) or "")
    local sub = menu:CreateButton(label)
    sub:SetTooltip(function(tooltip)
        self:AddTooltip(tooltip, boss, true)
    end)

    if dispels then
        sub:CreateTitle("Dispels: " .. dispels)
    end

    local tips, _, classInfo = self:ClassTips(boss.id)
    if classInfo and #tips > 0 then
        sub:CreateTitle(("|cff%s%s Checklist|r"):format(classInfo.hex, classInfo.name))
        for _, tip in ipairs(tips) do
            local tipLabel = self:SpellIcon(tip.spellID, 16) .. " " .. tip.name
            local row = sub:CreateButton(tipLabel, function()
                if linkSpell then linkSpell("spell", tip.spellID, tip.name) end
            end)
            row:SetTooltip(function(tooltip)
                tooltip:SetSpellByID(tip.spellID)
                tooltip:AddLine(" ")
                tooltip:AddLine(tip.text, 1, .82, 0, true)
            end)
        end
    end

    sub:CreateDivider()
    roleRow(sub, boss, ROLE_ICON.tank, "66b3ff", "Tank", self:FormatText(entry.t), dispels)
    roleRow(sub, boss, ROLE_ICON.healer, "55ee66", "Healer", self:FormatText(entry.h), dispels)
    roleRow(sub, boss, ROLE_ICON.dps, "ff6655", "DPS", self:FormatText(entry.d), dispels)
    return sub
end
