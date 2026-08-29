-- Magic System Rework 2.0 by amakri, original Magic System by Dalas
local _ = wesnoth.textdomain "wesnoth-ctl"

--###########################################################################################################################################################
--                                                                  DEFINE SKILLS
--###########################################################################################################################################################
-- Description style (kept in step with TDG's skill_set.lua):
--   * the "Attack:/Spell:/Passive:/Radius:" heading comes from a header_*()
--     helper, so its markup lives in ONE place and translators see the word
--     alone instead of a copy of the markup in all 49 descriptions;
--   * emphasis inside a <span> is written as attributes (style='italic'
--     weight='bold'), not as nested <i>/<b> tags -- the descriptions are drawn
--     by a rich_label, which maps a span's attributes onto the text it wraps
--     and does not recurse into tags nested inside it;
--   * game terms link into the help browser with <ref dst='...'>;
--   * costs are written "8 XP", uppercase and spaced.
function label(text)      return "<span size='1000'> \n</span><span size='large'>"..text.."</span><span size='8000'>\n </span>"  end
function header_attack()  return "<span color='#ad6a61' style='italic' weight='bold'>".._"Attack:" .." </span>"  end
function header_spell()   return "<span color='#6ca364' style='italic' weight='bold'>".._"Spell:"  .." </span>"  end
function header_passive() return "<span color='#a9a150' style='italic' weight='bold'>".._"Passive:".." </span>"  end
function header_radius()  return "<span color='#ad6a61' style='italic' weight='bold'>".._"Radius:" .." </span>"  end

local skill_set = {
	-------------------------
	-- MAGIC BLAST
	-------------------------
	[1] = {
		id          = "skill_magic_blast",
		label       = label(_"Magic Blast"),
		image       = "attacks/mud-missile.png",
		description_by_level = {
			[1] = header_attack().._"Ranged 9x2 impact, <i><ref dst='weaponspecial_magical'>magical</ref></i>.",
			[2] = header_attack().._"Ranged 12x3 impact, <i><ref dst='weaponspecial_magical'>magical</ref></i>.",
			[3] = header_attack().._"Ranged 12x3 impact, <i><ref dst='weaponspecial_magical'>magical</ref></i>.",
			[4] = header_attack().._"Ranged 12x3 impact, <i><ref dst='weaponspecial_magical'>magical</ref></i>.",
		},
	},
	-------------------------
	-- SUMMON
	-------------------------
	[2] = {
		id          = "skill_summon",
		label       = label(_"Summon"),
		image       = "icons/summon.png",
		-- #po: Закличте духа природи до себе на допомогу, навіть знаходячись за межами цитаделі.    Для цього закляття використовується <span color='#FFD700' style='italic'>золото</span> та <span color='#00bbe6' style='italic'>досвід</span>
		description = header_spell().._"Summon the spirit of nature to your aid, even when outside the keep.\n           This spell uses <span color='#FFD700' style='italic'>gold</span> and <span color='#00bbe6' style='italic'>experience</span>.",
		description_extra_separator = ", ",
		description_extra = {
			skill_summon_mud   = _"           <i><ref dst='unit_Mudcrawler'>Mudcrawler</ref></i>",
			skill_summon_rock  = _"           <i><ref dst='unit_Elemental Rock'>Rock Elemental</ref></i>",
			skill_summon_water = _"           <i><ref dst='unit_Elemental Water'>Water Elemental</ref></i>",
			skill_summon_air   = _"           <i><ref dst='unit_Elemental Air'>Air Elemental</ref></i>",
			skill_summon_fire  = _"           <i><ref dst='unit_Elemental Fire'>Fire Elemental</ref></i>",
		},
		subskills   = {
			[1]={ id="skill_summon_mud",     xp_cost=6,  gold_cost=8,  label="   <span>".._"Mud"  .." (<span color='#FFD700' style='italic'>".._"8G" .."</span> <span color='#00bbe6' style='italic'>".._"6 XP".."</span>)</span>   " },
			[2]={ id="skill_summon_rock",    xp_cost=8,  gold_cost=14, label="   <span>".._"Stone".." (<span color='#FFD700' style='italic'>".._"14G".."</span> <span color='#00bbe6' style='italic'>".._"8 XP".."</span>)</span>   " },
			[3]={ id="skill_summon_water",   xp_cost=8,  gold_cost=10, label="   <span>".._"Water".." (<span color='#FFD700' style='italic'>".._"10G".."</span> <span color='#00bbe6' style='italic'>".._"8 XP".."</span>)</span>   " },
			[4]={ id="skill_summon_air",     xp_cost=8,  gold_cost=10, label="   <span>".._"Air"  .." (<span color='#FFD700' style='italic'>".._"10G".."</span> <span color='#00bbe6' style='italic'>".._"8 XP".."</span>)</span>   " },
			[5]={ id="skill_summon_fire",    xp_cost=8,  gold_cost=12, label="   <span>".._"Fire" .." (<span color='#FFD700' style='italic'>".._"12G".."</span> <span color='#00bbe6' style='italic'>".._"8 XP".."</span>)</span>   " }, },
	},
	-------------------------
	-- SHIELD
	-------------------------
	[3] = {
		id          = "skill_shield",
		label       = label(_"Shield"),
		image       = "icons/shield.png",
		description = header_spell().._"Spend <span color='#00bbe6' style='italic'>8 XP</span> to gain <i>+20% dodge chance</i> until the start of your next turn or until cancelled.",
		xp_cost=8,
	},
 	-------------------------
 	-- STASIS
 	-------------------------
 	[4] = {
 		id          = "skill_stasis",
 		label       = label(_"Stasis"),
 		image       = "icons/stasis.png",
 		description = header_spell().._"Spend <span color='#00bbe6' style='italic'>12 XP</span> and <span color='#c06a61' style='italic'>your attack</span> to <i><ref dst='weaponspecial_petrifies'>petrify</ref></i> yourself and adjacent units until the start of your next turn.",
 		xp_cost=12,
 	},
	-------------------------
	-- PANACEA
	-------------------------
	[5] = {
		id          = "skill_panacea",
		label       = label(_"Panacea"),
		image       = "icons/potion_green_small.png",
		description = header_spell().._"Spend <span color='#00bbe6' style='italic'>12 XP</span> to fully heal the lowest-health adjacent ally, and increase\n           its attacks, strikes, and damage by its level. <span color='#bb0000' weight='bold'>Next turn, it dies.</span>",
		xp_cost=12,
	},
	-------------------------
	-- CHILL TOUCH
	-------------------------
	[6] = {
		id          = "skill_chill_touch",
		label       = label(_"Chill Touch"),
		image       = "icons/chill-touch.png",
		description = header_attack().._"Melee 6x3 cold, <i><ref dst='weaponspecial_slows'>slows</ref></i>.",
	},
	-------------------------
	-- LEVITATE
	-------------------------
	[7] = {
		id          = "skill_levitate",
		label_by_level = {
			[1] = label(_"Levitate"),
			[3] = label(_"Flight"),
		},
		image_by_level = {
			[1] = "icons/levitate.png",
			[3] = "icons/sandals.png",
		},
		description_by_level = {
			[1] = header_spell().._"Spend <span color='#00bbe6' style='italic'>8 XP</span> to gain the <i><ref dst='ability_skirmisher'>skirmisher</ref></i> ability and <i>50%</i> defense on all terrain.\n           Lasts until the start of your next turn or until cancelled.",
			[3] = header_spell().._"Spend <span color='#00bbe6' style='italic'>8 XP</span> to gain the <i><ref dst='ability_skirmisher'>skirmisher</ref></i> ability, <i>50%</i> defense on all terrain and <i>+2 MP</i>.\n           Lasts until the start of your next turn or until cancelled.",
		},
		xp_cost=8,
	},
	-------------------------
	-- MNEMONIC
	-------------------------
	[8] = {
		id          = "skill_mnemonic",
		label       = label(_"Mnemonic"),
		image       = "icons/mnemonic.png",
		description = header_passive().._"Whenever an adjacent ally gains XP, you gain the same amount of XP.",
	},
	-------------------------
	-- FIND FAMILIAR
	-------------------------
	[9] = {
		id          = "skill_find_familiar",
		label       = label(_"Find Familiar"),
		image       = "icons/find-familiar.png",
		description = header_passive().._"Begin each scenario with your trusty pet <i><ref dst='unit_Raven'>raven</ref></i>.\n               Your familiar’s level and XP persist across scenarios, but reset if it dies.",
	},
	-------------------------
	-- BEND NATURE
	-------------------------
	[10] = {
		id          = "skill_bend",
		label       = label(_"Bend Nature"),
		image       = "icons/landmass.png",
		-- #po: Змініть клітинки в обраному напрямку на <b>2 ходи</b>, після чого місцевість повертається.\n           Земля: непрохідна, <i>скам'яніння</i> · Вода: мілка вода, <i>сповільнення</i> · Лава: 50 вогняної шкоди.
		description = header_spell().._"Bend the hexes in a chosen direction for <b>2 turns</b>, after which the terrain returns.\n           Earth: impassable, <ref dst='weaponspecial_petrifies'>petrifies</ref> · Water: shallow water, <ref dst='weaponspecial_slows'>slows</ref> · Lava: 50 fire damage.",
		subskills   = {
			[1]={ id="skill_bend_earth",  xp_cost=12, label="   <span>".._"Earth".." (<span color='#00bbe6' style='italic'>".._"12 XP".."</span>)</span>   " },
			[2]={ id="skill_bend_water",  xp_cost=8,  label="   <span>".._"Water".." (<span color='#00bbe6' style='italic'>".._"8 XP" .."</span>)</span>   " },
			[3]={ id="skill_bend_lava",   xp_cost=32, label="   <span>".._"Lava" .." (<span color='#00bbe6' style='italic'>".._"32 XP".."</span>)</span>   " },	},
	},
	-------------------------
	-- FIREBALL2
	-------------------------
	[11] = {
		id          = "skill_fireball2",
		label       = label(_"Fireball"),
		image       = "attacks/fireball.png",
		description_by_level = {
			[1] = header_attack().._"Ranged 6x4 fire, <i><ref dst='weaponspecial_magical'>magical</ref></i>.",
			[2] = header_attack().._"Ranged 8x4 fire, <i><ref dst='weaponspecial_magical'>magical</ref></i>.",
			[3] = header_attack().._"Ranged 12x4 fire, <i><ref dst='weaponspecial_magical'>magical</ref></i>.",
			[4] = header_attack().._"Ranged 12x4 fire, <i><ref dst='weaponspecial_magical'>magical</ref></i>.",
		},
	},
	-------------------------
	-- GLAMOUR
	-------------------------
	[12] = {
		id          = "skill_glamour",
		label       = label(_"Glamour"),
		image       = "icons/glamour.png",
		description = header_passive().._"Gain the <i><ref dst='ability_leadership'>leadership</ref></i> ability.",
	},
	-------------------------
	-- ENERVATE
	-------------------------
	[13] = {
		id          = "skill_enervate",
		label       = label(_"Siphon"),
		image       = "icons/enervate.png", -- better than fireball2 vs orcs or undead, but sarians resist arcane and are vulnerable to fire. You also get this a few scenarios later than fireball2.
		description = header_attack().._"Ranged 8x4 arcane, <i><ref dst='weaponspecial_magical'>magical</ref></i>, <i><ref dst='weaponspecial_drains'>drains</ref></i>.",
	},
	-------------------------
	-- BLIZZARD
	-------------------------
	[14] = {
		id          = "skill_blizzard",
		label       = label(_"Blizzard"),
		image       = "icons/blizzard.png",
		description = header_spell().._"Spend <span color='#00bbe6' style='italic'>16 XP</span> and <span color='#c06a61' style='italic'>your attack</span> to <i><ref dst='weaponspecial_slows'>slow</ref></i> enemy units and freeze terrain in a 3-hex radius.",
		xp_cost=16, atk_cost=1,
	},
	-------------------------
	-- COUNTERSPELL
	-------------------------
	[15] = {
		id          = "skill_counterspell",
		label       = label(_"Counterspell"),
		image       = "icons/counterspell.png",
		description = header_spell().._"Spend <span color='#00bbe6' style='italic'>16 XP</span> to <i>disallow <ref dst='weaponspecial_magical'>magical</ref> attacks</i> in a 3-hex radius, until cancelled.\n           Prevents spellcasting, but not passive skills.",
		xp_cost=16,
	},
	-------------------------
	-- POLYMORPH
	-------------------------
	[16] = {
		id          = "skill_polymorph",
		label       = label(_"Polymorph"),
		image       = "icons/polymorph.png",
		description = header_spell().._"Take the shape of another creature. Lasts until cancelled.\n            Replaces $caster’s attacks, spells, and passives, but does not affect hitpoints.",
		description_extra_separator = ", ",
		description_extra = {
			skill_polymorph_lizard = _"           <i><ref dst='unit_Swamp Lizard Poly'>Swamp Lizard</ref></i>",
			skill_polymorph_bear   = _"           <i><ref dst='unit_Cave Bear Poly'>Cave Bear</ref></i>",
			skill_polymorph_yeti   = _"           <i><ref dst='unit_Yeti Poly'>Yeti</ref></i>",
			skill_polymorph_orc    = _"           <i><ref dst='unit_Orcish Warlord Poly'>Orcish Warlord</ref></i>",
		},
		subskills   = {
			[1]={ id="skill_polymorph_lizard", xp_cost=8,  label="   <span>".._"Swamp Lizard".." (<span color='#00bbe6' style='italic'>".._"8 XP" .."</span>)</span>   " },
			[2]={ id="skill_polymorph_bear",   xp_cost=12, label="   <span>".._"Bear"  .." (<span color='#00bbe6' style='italic'>".._"12 XP".."</span>)</span>   " },
			[3]={ id="skill_polymorph_yeti",   xp_cost=20, label="   <span>".._"Yeti"  .." (<span color='#00bbe6' style='italic'>".._"20 XP".."</span>)</span>   " },
			[4]={ id="skill_polymorph_orc",    xp_cost=32, label="   <span><span color='#a308b8'>".._"Orcish Warlord".."</span> (<span color='#00bbe6' style='italic'>".._"32 XP".."</span>)</span>   " }, },
	},
	-------------------------
	-- DANCING DAGGERS
	-------------------------
	[17] = {
		id          = "skill_dancing_daggers",
		label       = label(_"Dancing Daggers"),
		image       = "icons/dancing-daggers.png",
		description = header_attack().._"Ranged 5x8 blade, <i><ref dst='weaponspecial_backstab'>backstab</ref></i>.",
	},
	-------------------------
	-- CONTINGENCY
	-------------------------
	[19] = {
		id          = "skill_contingency",
		label       = label(_"Contingency"),
		image       = "icons/contingency.png",
		description = header_passive().._"Whenever one of your soldiers dies, they are instead safely returned to your recall list.",
	},
	-------------------------
	-- LIGHTNING
	-------------------------
	[20] = {
		id          = "skill_lightning",
		label       = label(_"Chain Lightning"),
		image       = "attacks/lightning.png",
		description_by_level = {
			[1] = header_attack().._"Ranged 5x4 fire, <i><ref dst='weaponspecial_magical'>magical</ref></i>. If this attack kills an enemy, you may attack again.",
			[3] = header_attack().._"Ranged 9x4 fire, <i><ref dst='weaponspecial_magical'>magical</ref></i>. If this attack kills an enemy, you may attack again.",
			[4] = header_attack().._"Ranged 14x4 fire, <i><ref dst='weaponspecial_magical'>magical</ref></i>. If this attack kills an enemy, you may attack again.",
		},
	},
	-------------------------
	-- TIME DILATION
	-------------------------
	[21] = {
		id          = "skill_time_dilation",
		label       = label(_"Time Dilation"),
		image       = "icons/time-dilation.png",
		description = header_spell().._"Spend <span color='#00bbe6' style='italic'>48 XP</span> to grant yourself and all allies double <ref dst='movement'>movement</ref> and a second attack this turn.\n           When this turn ends, affected units become <i><ref dst='weaponspecial_slows'>slowed</ref></i>.",
		xp_cost=48,
	},
	-------------------------
	-- CATACLYSM
	-------------------------
	[22] = {
		id          = "skill_cataclysm",
		label       = label(_"Cataclysm"),
		image       = "icons/cataclysm.png",
		description = header_spell().._"Spend <span color='#00bbe6' style='italic'>99 XP</span> and <span color='#c06a61' style='italic'>your attack</span> to injure everyone in a 4-hex radius for 40%-90%\n           of their current HP. Melts snow, burns forest, and levels castles/villages.",
		xp_cost=99, atk_cost=1,
	},
	-------------------------
	-- MAGIC MISSILE
	-------------------------
	[23] = {
		id          = "skill_magic_missile",
		label       = label(_"Magic Missile"),
		image       = "attacks/magic-missile.png",
		description_by_level = {
			[1] = header_attack().._"Ranged 7x3 fire, <i><ref dst='weaponspecial_magical'>magical</ref></i>.",
			[2] = header_attack().._"Ranged 10x3 fire, <i><ref dst='weaponspecial_magical'>magical</ref></i>.",
			[3] = header_attack().._"Ranged 10x3 fire, <i><ref dst='weaponspecial_magical'>magical</ref></i>.",
			[4] = header_attack().._"Ranged 10x3 fire, <i><ref dst='weaponspecial_magical'>magical</ref></i>.",
		},
	},
	-------------------------
	-- DISTANT ATTACK
	-------------------------
	[24] = {
		id          = "skill_disattack",
		label       = label(_"Ray of Light"),
		image       = "attacks/beam-eye.png",
		-- #po: Використайте <span color='#00bbe6' style='italic'>6 XP</span>, щоб атакувати ворога дальньою містичною атакою <b>9x3</b>. \n<i>6 клітинок.</i>
		description = header_spell().._"Spend <span color='#00bbe6' style='italic'>6 XP</span> to attack the enemy with a <b>9x3</b> ranged arcane attack. \n"..header_radius().._"<i>6 hexes.</i>",
		xp_cost=6,
	},
	-------------------------
	-- SWAP
	-------------------------
	[25] = {
		id          = "skill_swap",
		label       = label(_"Swap"),
		image       = "icons/swap.png",
		-- #po: Використайте <span color='#00bbe6' style='italic'>8 XP</span>, щоб миттєво обмінятися місцями з будь-яким юнітом. \n<i>4 клітинки.</i>
		description = header_spell().._"Spend <span color='#00bbe6' style='italic'>8 XP</span> to instantly swap places with any unit. \n"..header_radius().._"<i>4 hexes.</i>",
		xp_cost=8,
	},
	-------------------------
	-- DISTANT HEAL
	-------------------------
	[26] = {
		id          = "skill_disheal",
		label       = label(_"Distant Heal"),
		image       = "icons/disheal.png",
		-- #po: Використайте <span color='#00bbe6' style='italic'>6 XP</span>, щоб вилікувати себе або дружнього юніта на +8 ОЗ. \n<i>7 клітинок.</i>
		description = header_spell().._"Spend <span color='#00bbe6' style='italic'>6 XP</span> to <ref dst='ability_cures'>cure</ref> yourself or a friendly unit and heal for +8 HP. \n"..header_radius().._"<i>7 hexes.</i>",
		xp_cost=6,
	},
	-------------------------
	-- WARD
	-------------------------
	[27] = {
		id          = "skill_ward",
		label       = label(_"Holy Ward"),
		image       = "icons/ward.png",
		-- #po: Використайте <span color='#00bbe6' style='italic'>10 XP</span>, щоб на кілька ходів розмістити на мапі <i><ref dst='unit_Brazier'>Оберіг</ref></i>.\n           Кожного ходу він завдаватиме навколишнім мерцям <b>20</b> містичної шкоди. \n<i>2 клітинки.</i>
		description = header_spell().._"Spend <span color='#00bbe6' style='italic'>10 XP</span> to place a <i><ref dst='unit_Brazier'>Ward</ref></i> on the map for a few turns.\n           Each turn, it will deal <b>20</b> arcane damage to the surrounding undead. \n"..header_radius().._"<i>2 hexes.</i>",
		xp_cost=10,
	},
	-------------------------
	-- RELOCATE
	-------------------------
	[28] = {
		id          = "skill_relocate",
		label       = label(_"Relocate"),
		image       = "icons/relocate.png",
		description = header_spell().._"Spend <span color='#00bbe6' style='italic'>10 XP</span> to instantly teleport any friendly unit. \n"..header_radius().._"<i>3 hexes.</i>",
		xp_cost=10,
	},
	-------------------------
	-- ILLUMINATE
	-------------------------
	[29] = {
		id          = "skill_illuminate",
		label       = label(_"Illuminate"),
		image       = "icons/illuminate.png",
		description = header_passive().._"Gain the <i><ref dst='ability_illumination'>illuminates</ref></i> ability.",
	},
	-------------------------
	-- LIGHTBEAM
	-------------------------
	[30] = {
		id          = "skill_lightbeam",
		label       = label(_"Lightbeam"),
		image       = "attacks/lightbeam.png",
		description = header_attack().._"Ranged 12x3 arcane, <i><ref dst='weaponspecial_magical'>magical</ref></i>.",
	},
	-------------------------
	-- MASSHEAL
	-------------------------
	[32] = {
		id          = "skill_massheal",
		label       = label(_"Massive Heal"),
		image       = "icons/massheal.png",
		description = header_spell().._"Spend <span color='#00bbe6' style='italic'>12 XP</span> to heal every adjacent friendly unit for +10 HP.",
		xp_cost=12,
	},
	-------------------------
	-- SMITE
	-------------------------
	[33] = {
		id          = "skill_smite",
		label       = label(_"Smite"),
		image       = "attacks/banishment.png",
		description = header_spell().._"Spend <span color='#00bbe6' style='italic'>16 XP</span> to deal 30 arcane damage to every adjacent enemy unit.",
		xp_cost=16,
	},
	-------------------------
	-- NATURE'S REVENGE
	-------------------------
	[34] = {
		id          = "skill_nature_revenge",
		label       = label(_"Nature's Revenge"),
		image       = "attacks/entangle.png",
		description = header_spell().._"Spend <span color='#00bbe6' style='italic'>16 XP</span> to deal 30 impact damage to every adjacent enemy unit.",
		xp_cost=16,
	},
	-------------------------
	-- RAGE
	-------------------------
	[35] = {
		id          = "skill_fury",
		label       = label(_"Magic Rage"),
		image       = "attacks/frenzy.png",
		description_by_level = {
			[1] = header_attack().._"Melee 7x3 fire, <i><ref dst='weaponspecial_berserk'>berserk</ref></i>, <i><ref dst='weaponspecial_magical'>magical</ref></i>.",
			[3] = header_attack().._"Melee 10x3 fire, <i><ref dst='weaponspecial_berserk'>berserk</ref></i>, <i><ref dst='weaponspecial_magical'>magical</ref></i>.",
			[4] = header_attack().._"Melee 13x3 fire, <i><ref dst='weaponspecial_berserk'>berserk</ref></i>, <i><ref dst='weaponspecial_magical'>magical</ref></i>.",
		},
	},
	-------------------------
	-- ASTRAL ARMS
	-------------------------
	[36] = {
		id          = "skill_astral_arms",
		label       = label(_"Weapon"),
		image       = "icons/sword-astral.png",
		description = header_spell().._"Summon a spectral weapon. Each of them has similar damage, but a different type and specials.\nLasts until you change it.",
		subskills   = {
			[1]={ id="skill_arms_astral",  castable = true, label="   <span>".._"Astral" .."</span>   "},
			[2]={ id="skill_arms_blade",   castable = true, label="   <span>".._"Blade"  .."</span>   "},
			[3]={ id="skill_arms_spear",   castable = true, label="   <span>".._"Spear"  .."</span>   "},
			[4]={ id="skill_arms_mace",    castable = true, label="   <span>".._"Mace"   .."</span>   "},
			[5]={ id="skill_arms_daggers", castable = true, label="   <span>".._"Daggers".."</span>   "},
		},
	},
	-------------------------
	-- SHADOWSTEP
	-------------------------
	[37] = {
		id          = "skill_shadowstep",
		label       = label(_"Shadowstep"),
		image       = "icons/relocate.png", --TODO
		description = header_spell().._"Spend <span color='#00bbe6' style='italic'>8 XP</span> to teleport next to a selected unit.\n"..header_radius().._"<i>6 hexes.</i>",
		xp_cost     = 8,
	},
	-------------------------
	-- PHANTOM FLURRY
	-------------------------
	[38] = {
		id          = "skill_phantom_flurry",
		label       = label(_"Flurry"), --TODO
		image       = "icons/dancing-daggers.png", --TODO
		description = header_spell().._"Spend <span color='#00bbe6' style='italic'>12 XP</span> to gain <b>+2 attacks</b> this turn.",
		xp_cost     = 12,
	},
	-------------------------
	-- ASTRAL CHAINS
	-------------------------
	[39] = {
		id          = "skill_astral_chains",
		label       = label(_"Chains"),
		image       = "icons/swap.png",
		description = header_spell().._"Spend <span color='#00bbe6' style='italic'>10 XP</span> to pull a selected unit next to you.\n"..header_radius().._"<i>4 hexes.</i>",
		xp_cost     = 10,
	},
	-------------------------
	-- HASTE
	-------------------------
	[40] = {
		id          = "skill_haste",
		label       = label(_"Haste"),
		image       = "icons/sandals.png", --TODO
		description = header_spell().._"Spend <span color='#00bbe6' style='italic'>12 XP</span> to gain the <i><ref dst='ability_skirmisher'>skirmisher</ref></i> ability, <i>50%</i> defense on all terrain and <i>+3 MP</i>.\n           Lasts until the start of your next turn or until cancelled.",
		xp_cost     = 12,
	},
	-------------------------
	-- VEIL
	-------------------------
	[41] = {
		id          = "skill_veil_ward",
		label       = label(_"Veil"),
		image       = "icons/shield.png",
		description = header_passive().._"<i>+25% defense</i> on all terrain.",
	},
	-------------------------
	-- VIGOR
	-------------------------
	[42] = {
		id          = "skill_bloodbound_vigor",
		label       = label(_"Vigor"), --TODO
		image       = "icons/potion_green_small.png",
		description = header_passive().._"<b>+15 max HP</b>.",
	},
	-------------------------
	-- KNIT
	-------------------------
	[43] = {
		id          = "skill_soul_knit",
		label       = label(_"Knit"), --TODO
		image       = "icons/disheal.png",
		description = header_passive().._"<i><ref dst='ability_regenerates_8'>Regenerate</ref> +8 HP</i> each turn.",
	},
	-------------------------
	-- GUARD
	-------------------------
	[44] = {
		id          = "skill_phantom_guard",
		label       = label(_"Guard"), --TODO
		-- Was icons/illusion.png, which only ever existed in TDG: the file is not
		-- in magic/images/icons/, so the game logged "could not open image" every
		-- time this row was drawn. Enthrall is gone, so nothing brings it in now.
		image       = "icons/shield.png", --TODO
		description = header_passive().._"Double resistances when defending up to 50% (<i><ref dst='ability_steadfast'>steadfast</ref></i>).",
	},

	-------------------------
	-- DRAIN
	-------------------------
	[45] = {
		id          = "skill_soul_siphon",
		label       = label(_"Drain"),
		image       = "icons/enervate.png", --TODO
		description = header_spell().._"Spend <span color='#00bbe6' style='italic'>28 XP</span> to deal 30 arcane damage to a selected enemy, healing yourself for the amount of damage dealt.\n"..header_radius().._"<i>6 hexes.</i>",
		xp_cost     = 28,
	},
	-------------------------
	-- OBLIVION
	-------------------------
	[46] = {
		id          = "skill_oblivion",
		label       = label(_"Curse"), --TODO
		image       = "attacks/beam-eye.png",
		description = header_spell().._"Spend <span color='#00bbe6' style='italic'>40 XP</span> to deal 50 arcane damage to a selected enemy.\n"..header_radius().._"<i>5 hexes.</i>",
		xp_cost     = 40,
	},
	-------------------------
	-- RIFT
	-------------------------
	[47] = {
		id          = "skill_void_rift",
		label       = label(_"Rift"),
		image       = "icons/cataclysm.png", --TODO
		description = header_spell().._"Spend <span color='#00bbe6' style='italic'>32 XP</span> to tear open a rift, dealing 25 arcane damage to all enemies within 2 hexes of the target location.\n"..header_radius().._"<i>5 hexes.</i>",
		xp_cost     = 32,
	},
	-------------------------
	-- PHYLACTERY
	-------------------------
	[48] = {
		id          = "skill_phylactery",
		label       = label(_"Backup"),
		image       = "icons/contingency.png", --TODO
		description = header_spell().._"Spend <span color='#00bbe6' style='italic'>48 XP</span> to TODO",
		xp_cost     = 48,
	},
	-------------------------
	-- EMPATHY
	-------------------------
	[49] = {
		id          = "skill_empathy",
		label       = label(_"Empathy"),
		image       = "icons/potion_red_small.png",
		description = header_passive().._"Whenever an adjacent ally regains hitpoints, you gain <span color='#00bbe6' style='italic'>XP equal to half that amount</span>.",
	},
	-------------------------
	-- DISPEL
	-------------------------
	[50] = {
		id          = "skill_dispel",
		label       = label(_"Purge"),
		image       = "attacks/eyeofstorm.png",
		description = header_spell().._"Spend <span color='#00bbe6' style='italic'>14 XP</span> to deal an <b>adjacent</b> <ref dst='..race_undead'>undead</ref> or <ref dst='..race_monster'>monster</ref> half the damage it has already taken.",
		xp_cost=14,
	},
	-------------------------
	-- BLINDING FLASH
	-------------------------
	[51] = {
		id          = "skill_blindflash",
		label       = label(_"Flash"),
		image       = "icons/contingency.png",
		description = header_spell().._"Spend <span color='#00bbe6' style='italic'>12 XP</span> and <span color='#c06a61' style='italic'>your attack</span> to blind every adjacent unit.\n           Blinded units have their attacks disabled and cannot enforce a <ref dst='movement'>ZoC</ref>.",
		xp_cost=12, atk_cost=1,
	},
	-------------------------
	-- GLYPH
	-------------------------
	[52] = {
		id          = "skill_glyph",
		label       = label(_"Glyph"),
		image       = "attacks/rune.png",
		description = header_spell().._"Spend <span color='#00bbe6' style='italic'>6 XP</span> to set a trap on an empty adjacent hex.\n           The first unit to step on it stops there and takes <i>12 arcane</i> damage.",
		xp_cost=6,
	},
	-------------------------
	-- ALIEN BONES
	-------------------------
	[53] = {
		id          = "skill_alien_bones",
		label       = label(_"Alien Bones"),
		image       = "icons/locked.png",
		description = header_passive().._"Your skeleton is stitched together from beasts, not from a man.\n           Whenever an allied undead dies within <i>3</i> hexes of you, you scavenge its bones and heal <i>8 HP per its level</i>.",
	},
	-------------------------
	-- MATTER EXCHANGE
	-------------------------
	[54] = {
		id          = "skill_matter_exchange",
		label       = label(_"Matter Exchange"),
		image       = "icons/locked.png",
		description = header_spell().._"Spend <span color='#00bbe6' style='italic'>28 XP</span> to trade your current hitpoints with a unit up to <i>5</i> hexes away.\n           Neither side may exceed its own maximum.",
		xp_cost=28,
	},
	-------------------------
	-- DECAY
	-------------------------
	[55] = {
		id          = "skill_decay",
		label       = label(_"Decay"),
		image       = "icons/locked.png",
		description = header_spell().._"Spend <span color='#00bbe6' style='italic'>22 XP</span> to rot everything within <i>2</i> hexes: enemies take <i>24 impact</i>,\n           and the ground beneath them crumbles to bare dirt, losing all terrain defence.",
		xp_cost=22,
	},
	-------------------------
	-- REFORGE
	-------------------------
	[56] = {
		id          = "skill_reforge",
		label       = label(_"Reforge"),
		image       = "icons/locked.png",
		description = header_spell().._"Spend <span color='#00bbe6' style='italic'>20 XP</span> to remake an adjacent ally into the next stage of its kind.\n           It does not summon anything new -- it perfects what already stands beside you.",
		xp_cost=20,
	},
	-------------------------
	-- EFFIGY
	-------------------------
	[57] = {
		id          = "skill_effigy",
		label       = label(_"Effigy"),
		image       = "icons/locked.png",
		description = header_spell().._"Spend <span color='#00bbe6' style='italic'>26 XP</span> to remake an adjacent undead of <i>level 2 or lower</i>\n           into a lesser copy of yourself.",
		xp_cost=26,
	},
	-------------------------
	-- BONEMAIL
	-------------------------
	[58] = {
		id          = "skill_bonemail",
		label       = label(_"Bonemail"),
		image       = "icons/cuirass_muscled.png",
		description = header_spell().._"Spend <span color='#00bbe6' style='italic'>12 XP</span> to take on a skeleton's resistances: <i>40% blade</i>, <i>60% pierce</i>, <i>60% cold</i>.\n           But <i>-20% impact</i>, <i>-20% fire</i> and <i>-40% arcane</i>. Lasts until cancelled.",
		xp_cost=12,
	},
	-------------------------
	-- REDEMPTION
	-------------------------
	[59] = {
		id          = "skill_redemption",
		label       = label(_"Redemption"),
		image       = "icons/sap.png",
		description = header_attack().._"Melee 7x3 arcane, <i><ref dst='weaponspecial_magical'>magical</ref></i>, <i><ref dst='weaponspecial_redemption'>redemption</ref></i>.",
	},
	-------------------------
	-- HEALING
	-------------------------
	[60] = {
		id          = "skill_healing",
		label       = label(_"Healing"),
		image       = "attacks/entangle.png",
		description = header_passive().._"Gain <i><ref dst='ability_heals_8'>heals +8</ref></i> and <i><ref dst='ability_cures'>cures</ref> abilities</i>.",
	},
	-------------------------
	-- INTERDICT
	-------------------------
	[61] = {
		id          = "skill_interdict",
		label       = label(_"Interdict"),
		image       = "attacks/kelp.png",
		description = header_spell().._"Spend <span color='#00bbe6' style='italic'>16 XP</span> to interdict one adjacent, empty hex.\n           No unit can enter or cross it. Lasts until cancelled.",
		xp_cost=16,
	},
	-------------------------
	-- DAZZLE
	-------------------------
	[62] = {
		id          = "skill_dazzle",
		label       = label(_"Dazzle"),
		image       = "attacks/fire-blast.png",
		description = header_attack().._"Ranged 3x3 fire. A unit it hits is blinded until the end of the turn.\n           Blinded units have their attacks disabled and cannot enforce a <ref dst='movement'>ZoC</ref>.",
	},
	-------------------------
	-- SPEAR
	-------------------------
	[63] = {
		id          = "skill_spear",
		label       = label(_"Spear"),
		image       = "attacks/spear-magic.png",
		description = header_attack().._"Melee 14x2 pierce, <i><ref dst='weaponspecial_impale'>impale</ref></i>.\n           An adjacent enemy that moves out of reach takes <i>14 pierce</i> damage.",
	},
}

--###############################
-- LOCKED INDICATOR
--###############################
local locked = {
	id          = "skill_locked",
	label       = label("<span color='grey'>Locked</span>"),
	image       = "icons/locked.png",
	description = "<span color='grey'>This option is not available yet.</span>",
}

return {
	--###############################
    -- LOCKED INDICATOR
    --###############################
	locked = {
	id          = "skill_locked",
	label       = label("<span color='grey'>Locked</span>"),
	image       = "icons/locked.png",
	description = "<span color='grey'>This option is not available yet.</span>",
    },
	skill_set = skill_set,
}
