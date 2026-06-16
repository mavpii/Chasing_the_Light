-- ai_profiles.lua
-- Editable catalogue: how the AI uses EVERY castable spell and EVERY subskill.
--
-- One entry per *castable* id (for multi-skills like Summon/Bend/Polymorph that is
-- the SUBSKILL id — the engine expands an equipped parent to its subskills).
-- ADD a line to enable a spell, DELETE a line to disable it. The engine (ai.lua)
-- dispatches on `kind`. Each turn an AI caster scores every profiled, AFFORDABLE
-- (sub)spell it has equipped and casts the single highest-utility one.
--
-- Cast method follows the kind automatically:
--   * target kinds (damage / heal_target / summon) -> [cast_targeted_spell], i.e.
--     they fire "<id>_cast" on a hex — use these for TRSS spells.
--   * self kinds (aoe_self / heal_self_aura / buff_self / buff_team / debuff_aura)
--     -> [cast_spell], i.e. they fire "<id>" directly — use these for self/aura spells.
--
-- kinds & fields (see ai.lua for exact maths):
--   damage         enemy in `range`; `power` = nominal damage (kill/wounded bonus)
--   heal_target    most-wounded ally (incl self) in `range`
--   summon         empty adjacent hex toward the enemy; fires when foes within `threat`
--   aoe_self       enemies within `radius`; `power`/foe, `ally_penalty`/friendly, needs `min`
--   heal_self_aura allies within `radius`
--   buff_self      self; fires when >= `min` enemies within `threat`; `weight`/foe
--   buff_team      self+allies; fires when >= `min` allies within `radius`
--   debuff_aura    enemies within `radius`; `vs_casters=true` adds value vs casters
-- Common: `base` (flat priority). Costs come from table.lua; unaffordable = skipped.

return {
    --======================= TARGETED (TRSS) — fire <id>_cast =======================

    -- ranged single-target damage
    skill_disattack = { kind = "damage", range = 6, power = 27, base = 20 },

    -- ranged heal of a wounded ally
    skill_disheal   = { kind = "heal_target", range = 7, base = 15 },

    -- swap places with an enemy to displace it (caveat: ends adjacent — low priority)
    skill_swap      = { kind = "damage", range = 4, power = 0, base = 4 },

    -- summons — summon the strongest body it can afford toward the enemy
    skill_summon_mud   = { kind = "summon", threat = 4, base = 12 },
    skill_summon_water = { kind = "summon", threat = 4, base = 15 },
    skill_summon_air   = { kind = "summon", threat = 4, base = 15 },
    skill_summon_rock  = { kind = "summon", threat = 4, base = 16 },
    skill_summon_fire  = { kind = "summon", threat = 4, base = 17 },

    -- holy ward placed toward the enemy (caveat: only hurts undead)
    skill_ward      = { kind = "summon", threat = 3, base = 6 },

    -- bend nature (rose spells). CAVEAT: their push/lava-damage extras live in the
    -- interactive click handler, so an auto-cast only runs the per-hex _cast body.
    skill_bend_lava  = { kind = "damage", range = 4, power = 20, base = 8 },
    skill_bend_water = { kind = "damage", range = 4, power = 3,  base = 6 },
    skill_bend_air   = { kind = "damage", range = 4, power = 2,  base = 5 },
    skill_bend_earth = { kind = "damage", range = 4, power = 1,  base = 4 },

    --======================= SELF / AURA — fire <id> directly =======================

    -- single-target adjacent area damage
    skill_smite          = { kind = "aoe_self", radius = 1, power = 30, min = 1, base = 15 },
    skill_nature_revenge = { kind = "aoe_self", radius = 1, power = 30, min = 1, base = 15 },

    -- big radius — also catches allies (ally_penalty) so it needs an enemy majority
    skill_blizzard  = { kind = "aoe_self", radius = 3, power = 6,  min = 2, ally_penalty = 4,  base = 12 },
    skill_cataclysm = { kind = "aoe_self", radius = 4, power = 18, min = 3, ally_penalty = 20, base = 10 },

    -- heal every adjacent ally
    skill_massheal = { kind = "heal_self_aura", radius = 1, base = 10 },

    -- panacea: fully heals + buffs the weakest adjacent ally, but it DIES next turn
    -- (sacrificial) — kept at very low priority. CAVEAT.
    skill_panacea  = { kind = "heal_self_aura", radius = 1, base = 2 },

    -- self defensive buffs (fire only when enemies are close)
    skill_shield   = { kind = "buff_self", threat = 3, weight = 12, base = 20 },
    skill_levitate = { kind = "buff_self", threat = 2, weight = 10, base = 12 },
    skill_flight   = { kind = "buff_self", threat = 2, weight = 10, base = 12 },

    -- stasis: petrifies the CASTER and adjacent units — defensive last resort. CAVEAT.
    skill_stasis   = { kind = "buff_self", threat = 1, weight = 8, min = 2, base = 5 },

    -- polymorph forms — become a melee bruiser when threatened; affordability (and
    -- `base`) makes it pick the strongest form it can pay for. Lasts until cancelled.
    skill_polymorph_lizard = { kind = "buff_self", threat = 2, weight = 4,  base = 6 },
    skill_polymorph_bear   = { kind = "buff_self", threat = 2, weight = 6,  base = 10 },
    skill_polymorph_yeti   = { kind = "buff_self", threat = 2, weight = 8,  base = 14 },
    skill_polymorph_orc    = { kind = "buff_self", threat = 2, weight = 10, base = 18 },

    -- Faisim — conjure a melee weapon when an enemy is in reach (then wade in)
    skill_arms_blade   = { kind = "buff_self", threat = 1, weight = 4, base = 12 },
    skill_arms_spear   = { kind = "buff_self", threat = 1, weight = 4, base = 10 },
    skill_arms_mace    = { kind = "buff_self", threat = 1, weight = 4, base = 10 },
    skill_arms_daggers = { kind = "buff_self", threat = 1, weight = 4, base = 11 },
    skill_arms_astral  = { kind = "buff_self", threat = 1, weight = 4, base = 9 },

    -- auras / control
    skill_counterspell = { kind = "debuff_aura", radius = 3, weight = 8, vs_casters = true, base = 15 },
    skill_illusion     = { kind = "debuff_aura", radius = 2, weight = 8, base = 10 },

    -- team tempo
    skill_time_dilation = { kind = "buff_team", radius = 6, weight = 8, min = 2, base = 10 },

    -- ===== not auto-castable: skill_relocate (two interactive steps — pick a unit
    -- AND a destination). Drive it from a scripted event with [cast_targeted_spell]
    -- if you need it. =====
}
