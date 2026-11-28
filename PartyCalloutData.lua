local _, addon = ...

-- Opt in encounters with an important action for a level-appropriate group.
-- NPC and cast IDs use the Forever observations in docs/boss-audit/mechanics.tsv.
-- Ability ranks and dispel types are cross-checked with the Forever 1.60.1 client data.
-- Recorded encounters: https://github.com/JIVESCORP/eg-link-output-wowf
-- Spell data: https://wago.tools/db2/SpellCategories?build=1.60.1.71139
-- Class training levels: https://maxdps.com/forever/mage/abilities and the other Forever class pages.
addon.partyCallouts = {
    -- The Deadmines and Blackfathom Deeps
    [639] = {text = "Control the Blackguards and be ready for more at half health."}, -- 5200
    [642] = { -- Terrify (7399) can send players into uncleared packs.
        text = "Clear the room and break Terrify fear quickly.",
        options = {
            {class = "SHAMAN", level = 18, spell = 8143,
                text = "Clear the room. Shaman, use Tremor Totem for Terrify."},
            {class = "PRIEST", level = 18, spell = 527, text = "Clear the room. Priest, dispel Terrify fear."},
        },
    },
    [646] = {text = "Kill the Blackguards first."}, -- 6432
    [4832] = { -- Sleep (8399) can take the healer out of the fight.
        text = "Interrupt Sleep and dispel it if it lands, especially on the healer.",
        options = {
            {class = "PRIEST", level = 18, spell = 527, text = "Interrupt Sleep. Priest, dispel it if it lands."},
        },
    },

    -- Ruins of Lordaeron and the Excavation Site
    [250483] = { -- Leech Poison (3358) heals Witherfang while the poison ticks.
        text = "Kill the adds first and clear Leech Poison from the tank if you can.",
        options = {
            {class = "PALADIN", level = 8, spell = 1152,
                text = "Kill the adds first. Paladin, clear the tank's Leech Poison."},
            {class = "DRUID", level = 14, spell = 8946,
                text = "Kill the adds first. Druid, clear the tank's Leech Poison."},
            {class = "SHAMAN", level = 16, spell = 526,
                text = "Kill the adds first. Shaman, clear the tank's Leech Poison."},
        },
    },
    [250631] = { -- Life Drain (1266011).
        text = "Leave Ghostly Citizens alone during the waves and interrupt Life Drain.",
    },
    [260325] = { -- Terrifying Roar (14100) and nearby raptor packs.
        text = "Clear the nearby grass and kill the Thicket Hunters before the fear.",
        options = {
            {class = "SHAMAN", level = 18, spell = 8143,
                text = "Clear nearby raptors first. Shaman, use Tremor Totem for Terrifying Roar."},
        },
    },

    -- Gnomeregan and Scarlet Monastery
    [7800] = {text = "Use the switches at active bomb chutes and kill any Walking Bombs that get through."},
    [6487] = {text = "Run out of range when Arcanist Doan bubbles. Detonation follows."}, -- 9438, 9435
    [3976] = {text = "After the resurrection, focus Whitemane and interrupt her heals."},

    -- City of Dalaran
    [246003] = { -- Entangle (1240688) and Fel Timbers (1240692).
        text = "Step out of Fel Timbers. Free anyone rooted inside.",
        options = {
            {class = "PRIEST", level = 18, spell = 527,
                text = "Leave the Fel Timbers clouds. Priest, dispel Entangle."},
            {class = "PALADIN", level = 42, spell = 4987,
                text = "Leave the Fel Timbers clouds. Paladin, cleanse Entangle."},
        },
    },
    [247032] = { -- Curse of Thorns (1304473) and Raise Dead (1303266).
        text = "Clear Curse of Thorns from melee if you can, and kill rising skeletons.",
        options = {
            {class = "MAGE", level = 18, spell = 475,
                text = "Mage, decurse Curse of Thorns from melee. Kill the skeletons."},
            {class = "DRUID", level = 24, spell = 2782,
                text = "Druid, decurse Curse of Thorns from melee. Kill the skeletons."},
        },
    },
    [247126] = { -- Unholy Frenzy (1303264) and Raise Dead (1303266).
        text = "Kill rising skeletons and strip Unholy Frenzy if you have an offensive dispel.",
        options = {
            {class = "SHAMAN", level = 12, spell = 370, text = "Shaman, Purge Unholy Frenzy. Kill rising skeletons."},
            {class = "PRIEST", level = 18, spell = 527,
                text = "Priest, dispel Unholy Frenzy off Atrexis. Kill rising skeletons."},
        },
    },
    [246020] = { -- 1303598; Mass Polymorph is Magic. No assumption that all casts can be kicked.
        text = "Dodge the mana orb and free allies from Mass Polymorph when you can.",
        options = {
            {class = "PRIEST", level = 18, spell = 527,
                text = "Dodge the mana orb. Priest, dispel Mass Polymorph when free."},
        },
    },

    -- The Drowned City. Blizzard hotfixes document the attackable Abyssal Bubble.
    -- https://news.blizzard.com/en-us/article/24315281/wow-forever-hotfixes-november-16-2026
    [258924] = { -- Harpoon (1282615, 1282746); Brinescale Priestess (260096) is a humanoid.
        text = "Control or kill both Brinescale Priestesses first. Interrupt their heals.",
        options = {
            {class = "MAGE", level = 8, spell = 118,
                text = "Mage, sheep one Brinescale Priestess. Interrupt and kill the other."},
        },
    },
    [260042] = { -- Embrine (1282842) and Waterbolt Volley (1282860).
        text = "Break Abyssal Bubbles first. Interrupt Waterbolt Volley.",
        options = {
            {class = "ROGUE", level = 12, spell = 1766,
                text = "Break Abyssal Bubbles first. Rogue, Kick Waterbolt Volley."},
            {class = "MAGE", level = 24, spell = 2139,
                text = "Break Abyssal Bubbles first. Mage, Counterspell Waterbolt Volley."},
            {class = "SHAMAN", level = 4, spell = 8042,
                text = "Break Abyssal Bubbles first. Shaman, Earth Shock Waterbolt Volley."},
        },
    },
    [260202] = {
        -- The client lists this fight as Deathless Guardians (3478).
        -- https://forever.wowcoach.gg/dungeons/the-drowned-city/
        encounter = 3478,
        text = "Kill Deathless Guardians first, then the other adds.",
    },
    [260243] = { -- The serpent phase uses Poison Bolt Volley (1283313) and Fear (1313471).
        aliases = {260274},
        text = "Save burst for serpent form. Clear Poison Bolt Volley if you can and be ready for Fear.",
        options = {
            {class = "SHAMAN", level = 22, spell = 8166,
                text = "Save burst for serpent form. Shaman, use Poison Cleansing Totem for Poison Bolt Volley."},
            {class = "DRUID", level = 26, spell = 2893,
                text = "Save burst for serpent form. Druid, clear Poison Bolt Volley with Abolish Poison."},
            {class = "PALADIN", level = 8, spell = 1152,
                text = "Save burst for serpent form. Paladin, clear Poison Bolt Volley."},
        },
    },

    -- Krol'dok Stronghold
    [258964] = { -- Convert (1280259). The charm breaks once the ally reaches half health.
        text = "Control the caster adds. Bring a Converted ally to half health to break the charm.",
    },
    [258966] = { -- Bloodlust (21049) is a beneficial Magic aura.
        text = "Control the summoned prisoners and remove Bloodlust if you have an offensive dispel.",
        options = {
            {class = "SHAMAN", level = 12, spell = 370, text = "Control the prisoners. Shaman, Purge Bloodlust."},
            {class = "PRIEST", level = 18, spell = 527,
                text = "Control the prisoners. Priest, dispel enemy Bloodlust."},
        },
    },
    [258972] = {text = "Melee, step out of Rending Whirl. Save tank defensives for Enrage."}, -- 1280011, 8599

    -- Maraudon, Razorfen Kraul, and Uldaman
    [13282] = { -- Toxic Volley (21687) and Summon Noxxion's Spawns (21707).
        text = "Kill Noxxion's Spawns when he splits and clear Toxic Volley if you can.",
        options = {
            {class = "SHAMAN", level = 22, spell = 8166,
                text = "Kill Noxxion's Spawns. Shaman, use Poison Cleansing Totem for Toxic Volley."},
            {class = "DRUID", level = 26, spell = 2893,
                text = "Kill Noxxion's Spawns. Druid, clear Toxic Volley with Abolish Poison."},
            {class = "PALADIN", level = 8, spell = 1152, text = "Kill Noxxion's Spawns. Paladin, clear Toxic Volley."},
        },
    },
    [4428] = { -- Dominate Mind (14515).
        text = "Interrupt Dominate Mind and free any charmed ally.",
        options = {
            {class = "PRIEST", level = 18, spell = 527,
                text = "Interrupt Dominate Mind. Priest, dispel it if it lands."},
        },
    },
    [2748] = {text = "Clear the small adds. When the large Vault Warders wake, finish Archaedas."}, -- 10252, 10258

    -- Alcaz Prison and Blackmaw Hold
    [255391] = {text = "Clear the neighboring rooms before pulling Wrex. If he calls more enemies, switch to them."},
    [255997] = {text = "Control or kill both Enchantresses first and interrupt Frostbolt Volley."}, -- 8398
    [257016] = { -- Grievous Garrote and the two Chaplains are corroborated in the Alcaz field guide.
        text = "Heal the Grievous Garrote target above 90%. Interrupt the Chaplains' heals.",
    },
    [247195] = { -- Intimidating Roar (1242884) is Fear, not a dispellable Magic aura.
        text = "Clear nearby patrols before Intimidating Roar and kill Flesh Maggots as they gather.",
        options = {
            {class = "SHAMAN", level = 18, spell = 8143,
                text = "Clear nearby patrols and kill Flesh Maggots. Shaman, use Tremor Totem for Intimidating Roar."},
        },
    },
    [247198] = {text = "Kill the four ritualists first to remove Bonesnout's Profane Bulwark."},
    [247206] = {
        -- Client encounter ID from https://forever.wowcoach.gg/dungeons/blackmaw-hold/
        encounter = 3316,
        text = "Switch to the summoned imps right away to remove Impaan's immunity.", -- 1243312
    },
    [247207] = {text = "Kill Clawbert before he can heal the Behemoth. Interrupt Thunder Roar."}, -- 1245154
    [247231] = {text = "Destroy the Profane Totems after they are purified to remove the Spirit's immunity."},
    [247234] = { -- Nightmare Detonation (1246362) and Crimson Wrest (1246456).
        text = "Give the Nightmare Detonation target room after Crimson Wrest pulls them in.",
    },

    -- The Shaper's Terrace, as described in the dungeon field guide and client spell data.
    [261813] = {
        text = "Clear Poison Bolt Volley before it stacks up on the party.",
        options = {
            {class = "SHAMAN", level = 22, spell = 8166,
                text = "Shaman, use Poison Cleansing Totem to clear Poison Bolt Volley."},
            {class = "DRUID", level = 26, spell = 2893,
                text = "Druid, clear Poison Bolt Volley with Abolish Poison."},
            {class = "PALADIN", level = 8, spell = 1152, text = "Paladin, clear Poison Bolt Volley."},
        },
    },
    [261809] = {text = "Spread for the yellow crystal, back away on red, and leave green or blue ground effects."},

    -- Scholomance, Shadowfang Keep, Lower Blackrock Spire, and Stratholme
    [10504] = { -- Veil of Shadow (17820) cuts healing taken by 75%.
        text = "Clear Veil of Shadow from the tank first if you can.",
        options = {
            {class = "MAGE", level = 18, spell = 475,
                text = "Mage, decurse Veil of Shadow quickly, especially off the tank."},
            {class = "DRUID", level = 24, spell = 2782,
                text = "Druid, decurse Veil of Shadow quickly, especially off the tank."},
        },
    },
    [4275] = { -- Arugal's Curse (7621) turns an ally hostile.
        text = "Interrupt Void Bolt and control any ally turned hostile by Arugal's Curse.",
    },
    [9236] = { -- Logs show Vosh'gajin's and the priests' Hex are dispellable Magic.
        text = "Control the Shadow Priests first and dispel Hex if you can, especially off the tank.",
        options = {
            {class = "PRIEST", level = 18, spell = 527,
                text = "Control the Shadow Priests. Priest, dispel Hex from the tank."},
            {class = "PALADIN", level = 42, spell = 4987,
                text = "Control the Shadow Priests. Paladin, cleanse Hex from the tank."},
        },
    },
    [10436] = { -- https://maxdps.com/forever/bosses/baroness-anastari
        text = "Bring a Possessed ally to half health. Stop when they're free.",
    },
    [5709] = { -- The live Forever review recounts the surviving dragons entering this fight.
        text = "Clear the remaining dragonkin before pulling. Switch to any dragons that join the fight.",
    },
}
