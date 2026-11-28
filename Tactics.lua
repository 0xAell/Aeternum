local _, addon = ...
local Tactics = {}
addon.Tactics = Tactics

local TACTICS_ICON = "|T133741:16:16:0:0:64:64:4:60:4:60|t"

local ROLE_ICON = {
    tank   = "|TInterface\\LFGFrame\\UI-LFG-ICON-PORTRAITROLES:16:16:0:0:64:64:0:19:22:41|t",
    healer = "|TInterface\\LFGFrame\\UI-LFG-ICON-PORTRAITROLES:16:16:0:0:64:64:20:39:1:20|t",
    dps    = "|TInterface\\LFGFrame\\UI-LFG-ICON-PORTRAITROLES:16:16:0:0:64:64:20:39:22:41|t",
}

local ROLES = {
    TANK = {"Tank", "t", ROLE_ICON.tank, "66b3ff"},
    HEALER = {"Healer", "h", ROLE_ICON.healer, "55ee66"},
    DAMAGER = {"DPS", "d", ROLE_ICON.dps, "ff6655"},
}
local ROLE_ORDER = {"TANK", "HEALER", "DAMAGER"}

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
    [5116]  = { 135860, "Concussive Shot" },
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
    if key ~= "enrage" and AuraUtil and AuraUtil.GetAuraBorderColor then
        local color = AuraUtil.GetAuraBorderColor(key == "magicBuff" and "Magic" or info.label)
        if color and color.WrapTextInColorCode then return color:WrapTextInColorCode(info.label) end
    end
    return ("|cff%s%s|r"):format(info.hex, info.label)
end

function Tactics:FormatText(text)
    if type(text) ~= "string" then return "" end
    return (text:gsub("{(%a+)}", formatTag))
end

function Tactics:ForBoss(bossID)
    return addon.tacticsData and bossID and addon.tacticsData[bossID] or nil
end

local function spellTexture(spellID)
    if C_Spell and C_Spell.GetSpellTexture then
        local texture = C_Spell.GetSpellTexture(spellID)
        if not (issecretvalue and issecretvalue(texture)) and (addon.IsReadableNumber(texture) and texture > 0
            or type(texture) == "string" and texture ~= "") then
            return texture
        end
    end
    if SPELLS[spellID] then return SPELLS[spellID][1] end
    local record = addon.castSpells[spellID]
    return record and record[2] > 0 and record[2] or nil
end

function Tactics:SpellIcon(spellID, size)
    local texture = spellTexture(spellID)
    if not texture then return "" end
    size = size or 14
    return ("|T%s:%d:%d:0:0:64:64:4:60:4:60|t"):format(tostring(texture), size, size)
end

local function hasText(value)
    return not (issecretvalue and issecretvalue(value)) and type(value) == "string" and value ~= ""
end

function Tactics:SpellName(spellID)
    local live = C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(spellID)
    if hasText(live) then return live end
    local info = SPELLS[spellID]
    local record = addon.castSpells[spellID]
    return info and info[2] or record and record[1] or ("Spell " .. tostring(spellID))
end

function Tactics:SpellTooltip(tooltip, spellID, name)
    tooltip:ClearLines()
    tooltip:SetSpellByID(spellID)
    local lines = tooltip:NumLines()

    local cast = addon.castSpells[spellID]
    local description = C_Spell and C_Spell.GetSpellDescription and C_Spell.GetSpellDescription(spellID)
    if hasText(description) then
        if lines > 1 then return end
    else
        -- Native tooltips may have a cast time without describing the spell's effect.
        description = cast and cast.description
        if lines > 1 and not description then return end
    end
    if lines == 0 then
        tooltip:SetText(self:SpellIcon(spellID, 18) .. " " .. (name or self:SpellName(spellID)))
    end
    if description then tooltip:AddLine(description, 1, .82, 0, true) end
    if cast and cast[3] then tooltip:AddLine("Effect: " .. formatTag(cast[3]), 1, 1, 1, true) end
end

local PET_SPELL = {[19505]=true, [19244]=true, [6358]=true}
function Tactics:KnownSpell(spellID)
    if not (C_SpellBook and C_SpellBook.IsSpellKnown) then return end
    local banks = Enum and Enum.SpellBookSpellBank
    if PET_SPELL[spellID] and not (banks and banks.Pet) then return end
    local bank = banks and (PET_SPELL[spellID] and banks.Pet or banks.Player)
    local function known(id)
        local result = C_SpellBook.IsSpellKnown(id, bank)
        return not (issecretvalue and issecretvalue(result)) and result == true
    end
    if known(spellID) then return spellID end
    -- A spellbook may retain only a higher rank or the active override.
    if C_Spell and C_Spell.GetSpellIDForSpellIdentifier then
        local ranked = C_Spell.GetSpellIDForSpellIdentifier(Tactics:SpellName(spellID))
        if addon.IsReadableNumber(ranked) and ranked ~= spellID and known(ranked) then return ranked end
    end
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
    return classFile, CLASS_INFO[classFile], raceFile == "Dwarf" or raceID == 3,
        raceFile == "Scourge" or raceID == 5
end

function Tactics:PlayerClass()
    local classFile, info = playerContext()
    return classFile, info
end

local function tagSet(entry, bossID)
    local has = {names={}}
    for _, tag in ipairs(entry.tags or {}) do has[tag] = true end
    for _, key in ipairs(entry.dispels or {}) do has[key] = true end
    local cast = addon.bossCasts[bossID]
    local function record(spells)
        for _, id in ipairs(spells or {}) do
            local spell = addon.castSpells[id] or {}
            for i = 3, 4 do
                local key = spell[i]
                if key then
                    has[key] = true
                    if not has.names[key] then has.names[key] = id end
                end
            end
        end
    end
    if cast then record(cast.live); record(cast.reference) end
    return has
end

function Tactics:DispelText(entry, bossID)
    if not entry then return end
    local has = tagSet(entry, bossID)
    local parts = {}
    for _, key in ipairs({"magic", "magicBuff", "curse", "disease", "poison", "bleed", "enrage"}) do
        if has[key] then parts[#parts + 1] = formatTag(key) end
    end
    return #parts > 0 and table.concat(parts, " · ") or nil
end

local function joinWords(words, sep)
    if #words == 0 then return "" end
    if #words == 1 then return words[1] end
    if #words == 2 then return words[1] .. sep .. words[2] end
    return table.concat(words, ", ", 1, #words - 1) .. sep .. words[#words]
end

local function ccTypes(has)
    local list = {}
    for _, key in ipairs({"fear", "sleep", "charm"}) do
        if has[key] then
            list[#list + 1] = has.names[key] and Tactics:SpellName(has.names[key]) or key
        end
    end
    return joinWords(list, "/")
end

local function playerRole()
    local role = UnitGroupRolesAssigned and UnitGroupRolesAssigned("player")
    if not (issecretvalue and issecretvalue(role)) then return ROLES[role] end
end

local TANK_ACTION = {[355]=true, [1161]=true, [6795]=true, [99]=true}

local function pushTip(tips, seen, spellID, text)
    if #tips >= 4 or seen[spellID] or TANK_ACTION[spellID] and seen.role and seen.role ~= ROLES.TANK then return end
    local rank = Tactics:KnownSpell(spellID)
    if not rank then return end
    seen[spellID] = true
    -- When the encounter data identifies the aura, show what to remove on this boss.
    local named = text:gsub("{(%a+)}", function(key)
        local id = seen.targets[key]
        local label = formatTag(key)
        if not id then return label end
        local name = Tactics:SpellName(id)
        return name == DISPEL[key].label and label or (label .. " (" .. name .. ")")
    end)
    tips[#tips + 1] = {
        spellID = rank,
        baseID = spellID,
        name = Tactics:SpellName(spellID),
        icon = Tactics:SpellIcon(spellID, 14),
        text = named,
    }
end

local function buildClassTips(classFile, entry, has, tips, seen)
    local kick = entry.kick or "priority casts"
    local purge = not has.names.magicBuff and entry.purge and (" (" .. entry.purge .. ")") or ""

    if classFile == "SHAMAN" then
        if has.fear or has.sleep or has.charm then
            pushTip(tips, seen, 8143, "Place Tremor Totem before " .. ccTypes(has) .. ". Keep your party in range.")
        end
        if has.poison then
            pushTip(tips, seen, 8166, "Drop Poison Cleansing Totem to clear {poison}.")
            if not seen[8166] then pushTip(tips, seen, 526, "Clear {poison} from the affected ally.") end
        end
        if has.disease then
            pushTip(tips, seen, 8170, "Drop Disease Cleansing Totem to clear {disease}.")
            if not seen[8170] then pushTip(tips, seen, 2870, "Clear {disease} from the affected ally.") end
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
        if has.adds then
            pushTip(tips, seen, 2484, "Keep loose adds in Earthbind Totem's slow while the tank collects them.")
        end

    elseif classFile == "PALADIN" then
        if has.magic or has.poison or has.disease then
            local types = {}
            local cleanse = Tactics:KnownSpell(4987)
            if cleanse and has.magic then types[#types + 1] = "{magic}" end
            if has.poison then types[#types + 1] = "{poison}" end
            if has.disease then types[#types + 1] = "{disease}" end
            if #types > 0 then
                pushTip(tips, seen, cleanse and 4987 or 1152, "Remove " .. joinWords(types, " and ") .. " from allies.")
            end
        end
        if has.bleed or has.physicalBurst then
            pushTip(tips, seen, 1022, "Use Blessing of Protection on a non-tank ally threatened by physical damage.")
        end
        if has.root or has.snare then
            pushTip(tips, seen, 1044, "Blessing of Freedom frees rooted or snared party members.")
        end
        if has.interrupt and has.adds then
            pushTip(tips, seen, 853, "Use Hammer of Justice on a stunnable caster add.")
        end
        if has.undead and has.adds then
            pushTip(tips, seen, 2878, "Turn Undead can temporarily control an extra undead add.")
        end
        if has.fire then pushTip(tips, seen, 19891, "Run Fire Resistance Aura to reduce party Fire damage.") end
        if has.frost then pushTip(tips, seen, 19888, "Run Frost Resistance Aura to reduce party Frost damage.") end
        if has.shadow then pushTip(tips, seen, 19876, "Run Shadow Resistance Aura to reduce party Shadow damage.") end

    elseif classFile == "PRIEST" then
        if has.fear then
            pushTip(tips, seen, 6346, "Protect the party's designated fear-break target before " .. ccTypes(has) .. ".")
        end
        if has.magic and has.magicBuff then
            pushTip(tips, seen, 527, "Dispel {magic} on party and strip enemy {magicBuff}" .. purge .. ".")
        elseif has.magic then
            pushTip(tips, seen, 527, "Dispel {magic} debuffs from tank and party promptly.")
        elseif has.magicBuff then
            pushTip(tips, seen, 527, "Offensive Dispel Magic strips enemy {magicBuff}" .. purge .. ".")
        end
        if has.disease then
            local useCure = not Tactics:KnownSpell(552)
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
            pushTip(tips, seen, 596, "Use Prayer of Healing after the party takes area damage.")
        end

    elseif classFile == "MAGE" then
        if has.curse then
            pushTip(tips, seen, 475, "Decurse {curse} immediately with Remove Lesser Curse.")
        end
        if has.interrupt then
            pushTip(tips, seen, 2139, "Save Counterspell for " .. kick .. ".")
        end
        if has.adds and (has.humanoid or has.beast) then
            pushTip(tips, seen, 118, "Polymorph an extra humanoid/beast add to simplify the pull.")
        end
        if has.frost then pushTip(tips, seen, 6143, "Keep Frost Ward up to absorb incoming Frost bursts.") end
        if has.fire then pushTip(tips, seen, 543, "Keep Fire Ward up to absorb incoming Fire bursts.") end
        if has.root or has.snare or has.knockback then
            pushTip(tips, seen, 1953, "Use Blink to get clear if movement effects leave you in danger.")
        end
        if has.adds then
            pushTip(tips, seen, 122, "Frost Nova loose melee adds away from the healer.")
        end

    elseif classFile == "ROGUE" then
        if has.interrupt then
            pushTip(tips, seen, 1766, "Save Kick for " .. kick .. ".")
        end
        if has.adds and has.humanoid then
            pushTip(tips, seen, 6770, "Sap a susceptible humanoid before the pull and leave it out of cleave range.")
        elseif has.adds then
            pushTip(tips, seen, 408, "Stun a loose add with Kidney Shot if it is susceptible.")
        end
        if has.threatDrop or has.cleave or has.physicalBurst then
            pushTip(tips, seen, 1966, "Stay behind the boss and Feint to avoid pulling aggro.")
        end
        if has.root or has.snare then
            pushTip(tips, seen, 1856, "Vanish can break roots/snares or drop aggro in emergencies.")
        end

    elseif classFile == "WARRIOR" then
        if has.fear then
            pushTip(tips, seen, 18499, "Pop Berserker Rage before or during Fear to stay on the boss.")
        end
        if has.interrupt then
            pushTip(tips, seen, 6552, "Interrupt " .. kick .. " with Pummel.")
            if not seen[6552] then pushTip(tips, seen, 72, "Equip a shield to interrupt " .. kick .. ".") end
        end
        if has.disarmable then
            pushTip(tips, seen, 676, "Disarm the boss to slash heavy weapon and cleave damage.")
        end
        if has.physicalBurst or has.enrage then
            pushTip(tips, seen, 871, "Save Shield Wall for the hardest incoming hits.")
        end
        if has.adds then
            pushTip(tips, seen, 1161, "Pick up adds quickly; use Challenging Shout if mobs scatter.")
        end
        if has.threatDrop then
            pushTip(tips, seen, 355, "Save Taunt to regain the boss after a threat loss.")
        end

    elseif classFile == "DRUID" then
        if has.poison then
            local useCure = not Tactics:KnownSpell(2893)
            local spellID = useCure and 8946 or 2893
            local verb = useCure and "Cure Poison" or "Abolish Poison"
            pushTip(tips, seen, spellID, "Keep " .. verb .. " rolling to clear {poison}.")
        end
        if has.curse then
            pushTip(tips, seen, 2782, "Decurse {curse} promptly with Remove Curse.")
        end
        if has.interrupt then
            pushTip(tips, seen, 16979, "Use Feral Charge in Bear Form to interrupt " .. kick .. ".")
        end
        if has.adds and (has.beast or has.dragonkin) then
            pushTip(tips, seen, 2637, "Hibernate an extra beast or dragonkin add.")
        end
        if has.aoe then
            pushTip(tips, seen, 740, "Channel Tranquility from a safe spot during heavy party damage.")
        end
        if has.physicalBurst or has.cleave or has.enrage then
            pushTip(tips, seen, 99, "Keep Demoralizing Roar up while tanking the boss in Bear Form.")
        end
        if has.threatDrop then
            pushTip(tips, seen, 6795, "Bear tanks hold Growl ready after threat drops.")
        end

    elseif classFile == "HUNTER" then
        if has.names.enrage then
            pushTip(tips, seen, 19801, "Remove " .. Tactics:SpellName(has.names.enrage) .. " with Tranquilizing Shot.")
        end
        if has.stealth then
            pushTip(tips, seen, 1543, "Drop Flare to reveal stealthed ambushes early.")
        end
        if has.adds then
            pushTip(tips, seen, 1499, "Place Freezing Trap in the path of an add that your party wants to control.")
        end
        if has.nature then
            pushTip(tips, seen, 20043, "Swap to Aspect of the Wild to cut party Nature damage.")
        end
        if has.interrupt and has.adds then
            pushTip(tips, seen, 19503, "Use Scatter Shot to stop a susceptible caster add.")
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
        if has.shadow then
            pushTip(tips, seen, 6229, "Keep Shadow Ward up to absorb incoming Shadow bursts.")
        end
        if has.adds and has.humanoid then
            pushTip(tips, seen, 6358, "Succubus Seduction can CC an extra humanoid add.")
        end
        if has.physicalBurst or has.cleave or has.enrage then
            pushTip(tips, seen, 702, "Curse of Weakness helps soften heavy physical hits.")
        end
    end
end

function Tactics:ClassTips(bossID)
    local entry = self:ForBoss(bossID)
    local classFile, classInfo, isDwarf, isUndead = playerContext()
    if not entry or not classFile then return {}, classFile, classInfo end
    local has = tagSet(entry, bossID)
    local tips, seen = {}, {targets=has.names, role=playerRole()}

    if entry.c and entry.c[classFile] then
        for _, override in ipairs(entry.c[classFile]) do
            pushTip(tips, seen, override[1], override[2])
        end
    end

    buildClassTips(classFile, entry, has, tips, seen)

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

local function roleLine(tooltip, role, entry, classInfo)
    local class = classInfo and ("|cff" .. classInfo.hex .. classInfo.name .. "|r · ") or ""
    local label = role[3] .. " " .. class .. "|cff" .. role[4] .. role[1] .. ":|r "
    tooltip:AddLine(label .. Tactics:FormatText(entry[role[2]]), 1, 1, 1, true)
end

function Tactics:AddGuide(tooltip, boss, full, addSpell, iconSize)
    local entry = boss and self:ForBoss(boss.id)
    if not entry then return end
    local dispels = self:DispelText(entry, boss.id)
    local tips, _, classInfo = self:ClassTips(boss.id)
    local assigned = playerRole()

    if full then
        if dispels then
            tooltip:AddLine("Effects: " .. dispels, 1, 1, 1, true)
        end
        if classInfo and #tips > 0 then
            tooltip:AddLine(" ")
            tooltip:AddLine(("|cff%s%s TLDR:|r"):format(classInfo.hex, classInfo.name))
            for _, tip in ipairs(tips) do
                if addSpell then
                    addSpell(self:SpellIcon(tip.baseID, iconSize) .. " " .. tip.text, tip.spellID, tip.name)
                else
                    tooltip:AddLine(tip.icon .. " " .. tip.text, 1, 1, 1, true)
                end
            end
        end
        tooltip:AddLine(" ")
        if assigned then roleLine(tooltip, assigned, entry, classInfo) end
        for _, token in ipairs(ROLE_ORDER) do
            if ROLES[token] ~= assigned then roleLine(tooltip, ROLES[token], entry) end
        end
        local casts = addon.bossCasts[boss.id]
        if not (casts and casts.live) then
            tooltip:AddLine("Guide-based tactics · awaiting a recorded Forever cast", .65, .65, .65, true)
        end
        return
    end

    -- Compact boss skull hover preview on the dungeon map.
    if dispels then
        tooltip:AddLine("Effects: " .. dispels, 1, 1, 1, true)
    end
    if assigned then
        roleLine(tooltip, assigned, entry, classInfo)
    elseif #tips == 0 then
        for _, token in ipairs(ROLE_ORDER) do roleLine(tooltip, ROLES[token], entry) end
    end
    if classInfo and #tips > 0 then
        if not assigned then tooltip:AddLine(("|cff%s%s:|r"):format(classInfo.hex, classInfo.name)) end
        local limit = math.min(#tips, 2)
        for i = 1, limit do
            tooltip:AddLine(tips[i].icon .. " " .. tips[i].text, .95, .95, .95, true)
        end
    end
end

function Tactics:AddTooltip(tooltip, boss, full)
    if full then tooltip:SetText(boss.name .. " — Tactics") end
    self:AddGuide(tooltip, boss, full)
end

local function castLabel(id, iconSize)
    local spell = addon.castSpells[id]
    local label = Tactics:SpellIcon(id, iconSize) .. " " .. Tactics:SpellName(id)
    return spell and spell[3] and (label .. " · " .. formatTag(spell[3])) or label
end

function Tactics:AddCasts(tooltip, boss, addSpell, iconSize)
    local casts = addon.bossCasts[boss.id]
    if not casts then return end
    for _, group in ipairs({{"live", "Recorded Forever casts"}, {"reference", "Reference spells"}}) do
        local ids = casts[group[1]]
        if ids and #ids > 0 then
            tooltip:AddLine(group[2], 1, .82, 0)
            if addSpell then
                for _, id in ipairs(ids) do addSpell(castLabel(id, iconSize), id) end
            else
                local names = {}
                for i, id in ipairs(ids) do names[i] = castLabel(id, 13) end
                tooltip:AddLine(table.concat(names, "  ·  "), .88, .88, .88, true)
            end
        end
    end
end

local function roleRow(menu, boss, role, entry, dispels)
    local row = menu:CreateButton(("%s |cff%s%s TLDR|r"):format(role[3], role[4], role[1]))
    row:SetTooltip(function(tooltip)
        tooltip:SetText(boss.name .. " — " .. role[1])
        if dispels then tooltip:AddLine("Effects: " .. dispels, 1, 1, 1, true) end
        tooltip:AddLine(Tactics:FormatText(entry[role[2]]), 1, 1, 1, true)
    end)
    return row
end

local function castMenu(parent, heading, ids)
    if not ids then return end
    local menu = parent:CreateButton(heading)
    for _, id in ipairs(ids) do
        local row = menu:CreateButton(castLabel(id, 16))
        row:SetTooltip(function(tooltip) Tactics:SpellTooltip(tooltip, id) end)
    end
end

function Tactics:AddMenu(menu, boss, linkSpell)
    local entry = boss and self:ForBoss(boss.id)
    if not entry then return nil end
    local dispels = self:DispelText(entry, boss.id)
    local label = TACTICS_ICON .. " Tactics" .. (dispels and (" · " .. dispels) or "")
    local sub = menu:CreateButton(label)
    if dispels then
        sub:CreateTitle("Effects: " .. dispels)
    end

    local tips, _, classInfo = self:ClassTips(boss.id)
    if classInfo and #tips > 0 then
        sub:CreateTitle(("|cff%s%s Checklist|r"):format(classInfo.hex, classInfo.name))
        for _, tip in ipairs(tips) do
            local tipLabel = self:SpellIcon(tip.baseID, 16) .. " " .. tip.name
            local row = sub:CreateButton(tipLabel, function()
                if linkSpell then linkSpell("spell", tip.spellID, tip.name) end
            end)
            row:SetTooltip(function(tooltip)
                self:SpellTooltip(tooltip, tip.spellID, tip.name)
                tooltip:AddLine(" ")
                tooltip:AddLine(tip.text, 1, .82, 0, true)
            end)
        end
    end

    sub:CreateDivider()
    local assigned = playerRole()
    if assigned then roleRow(sub, boss, assigned, entry, dispels) end
    for _, token in ipairs(ROLE_ORDER) do
        if ROLES[token] ~= assigned then roleRow(sub, boss, ROLES[token], entry, dispels) end
    end
    local casts = addon.bossCasts[boss.id]
    if casts then
        castMenu(sub, "Recorded Forever casts", casts.live)
        castMenu(sub, "Reference spells", casts.reference)
    end
    return sub
end
