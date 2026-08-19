--! Примусове вербування сторони поза її ходом, з оцінкою типів так, як це
--! робить справжній ШІ.
--!
--! Штатний CA вербування (data/ai/lua/ca_recruit_rushers.lua) використати
--! напряму не можна з двох причин:
--!   * він увесь зав'язаний на wesnoth.current.side, тож поза ходом сторони
--!     рахував би геть іншу сторону (ту, яка ходить зараз);
--!   * виконання йде через ai.recruit(), доступний лише в контексті ШІ.
--! Тому вся оцінка (модель шкоди, рейтинги, вибір гекса) портована звідти й
--! переписана так, щоб працювати для довільної сторони в будь-який момент.
--!
--! Відмінності від оригіналу, свідомі:
--!   * замість math.random (несинхронізований — у [event] на всіх клієнтах це
--!     був би десинк) тип обирається зваженим жеребом по mathx.random;
--!   * high_level_fraction за замовчуванням 0.5, а не 0: у портованій формулі
--!     hp_efficiency ділиться на cost^2, тож із нулем вибір намертво тягне в
--!     найдешевший 1-й рівень і 2-й не вербується взагалі;
--!   * прибрано полювання на села: вербування задумане як оборонне, і навколо
--!     другої лінії села вже свої.
--!
--! Використання у [event]:
--!     [force_recruit_full]
--!         side=3
--!         id=S10_Shadow_Lord
--!         animate=yes
--!         high_level_fraction=0.5  # приблизна частка юнітів 2 рівня й вище
--!         selectivity=4            # 0 = завжди найкращий тип, більше = жорсткіше
--!     [/force_recruit_full]

local T = wml.tag
local M = wesnoth.map

local CASTLE = "C*^*,K*^*,*^C*,*^K*"
local TERRAIN_ARCHETYPES = { "Wo", "Ww", "Wwr", "Ss", "Gt", "Ds", "Ft", "Hh", "Mm", "Vi", "Ch", "Uu", "At", "Qt", "Xt", "Tt", "Rt" }

-- кеші на один виклик [force_recruit_full]
local test_units, analyses

local function test_unit(unit_type)
	local unit = test_units[unit_type]
	if not unit then
		unit = wesnoth.units.create {
			type = unit_type,
			random_traits = false,
			name = "X",
			random_gender = false
		}
		test_units[unit_type] = unit
	end
	return unit
end

local function poisonable(unit) return not unit.status.unpoisonable end
local function drainable(unit) return not unit.status.undrainable end

local function get_best_defense(unit)
	local best_defense = 100
	for _,terrain in ipairs(TERRAIN_ARCHETYPES) do
		local defense = 100 - unit:defense_on(terrain)
		if defense < best_defense then
			best_defense = defense
		end
	end
	return best_defense
end

-- Порт get_best_attack() з ca_recruit_rushers.lua: середня шкода найкращої
-- атаки. Не через wesnoth.simulate_combat, бо той вимагає обох юнітів на мапі,
-- а нам треба гіпотетичні пари "тип проти типу".
local function get_best_attack(attacker, defender, defender_defense, attacker_defense, can_poison)
	local best_damage = 0
	local best_attack
	local best_poison_damage = 0

	for attack in wml.child_range(wesnoth.unit_types[attacker.type].__cfg, "attack") do
		local defense = defender_defense
		local poison = false
		local damage_multiplier = 1
		local damage_bonus = 0
		local weapon_damage = attack.damage

		for special in wml.child_range(attack, 'specials') do
			local mod
			if wml.get_child(special, 'poison') and can_poison then
				poison = true
			end

			-- влучність: marksman, magical тощо
			mod = wml.get_child(special, 'chance_to_hit')
			if mod then
				if tonumber(mod.value) then
					if mod.cumulative then
						if tonumber(mod.value) > defense then
							defense = tonumber(mod.value) or 0
						end
					else
						defense = tonumber(mod.value) or 0
					end
				elseif mod.add then
					defense = defense + (tonumber(mod.add) or 0)
				elseif mod.sub then
					defense = defense - (tonumber(mod.sub) or 0)
				elseif mod.multiply then
					defense = defense * (tonumber(mod.multiply) or 0)
				elseif mod.divide then
					defense = defense / (tonumber(mod.divide) or 1)
				end
			end

			-- решта модифікаторів шкоди (вважаємо всі кумулятивними)
			mod = wml.get_child(special, 'damage')
			if mod and mod.active_on ~= "defense" then
				local special_multiplier = 1
				local special_bonus = 0

				if tonumber(mod.multiply) then
					special_multiplier = special_multiplier * tonumber(mod.multiply)
				end
				if tonumber(mod.divide) and tonumber(mod.divide) ~= 0 then
					special_multiplier = special_multiplier / tonumber(mod.divide)
				end
				if tonumber(mod.add) then
					special_bonus = special_bonus + tonumber(mod.add)
				end
				if tonumber(mod.subtract) then
					special_bonus = special_bonus - tonumber(mod.subtract)
				end

				if mod.backstab then
					-- вважаємо, що удар у спину виходить у половині випадків
					damage_multiplier = damage_multiplier * (special_multiplier * 0.5 + 0.5)
					damage_bonus = damage_bonus + (special_bonus * 0.5)
					if mod.value then
						weapon_damage = (weapon_damage + (tonumber(mod.value) or 0)) / 2
					end
				else
					damage_multiplier = damage_multiplier * special_multiplier
					damage_bonus = damage_bonus + special_bonus
					if mod.value then
						weapon_damage = tonumber(mod.value) or 0
					end
				end
			end
		end

		-- висмоктування здоров'я у того, хто відбивається
		local drain_recovery = 0
		local defender_attacks = defender.attacks
		for i_d = 1,#defender_attacks do
			local defender_attack = defender_attacks[i_d]
			if (defender_attack.range == attack.range) then
				for _,sp in ipairs(defender_attack.specials) do
					if (sp[1] == 'drains') and drainable(attacker) then
						local attacker_resistance = attacker:resistance_against(defender_attack.type)
						drain_recovery = (defender_attack.damage * defender_attack.number * (100 - attacker_resistance) * attacker_defense / 2) / 10000
					end
				end
			end
		end

		defense = defense / 100.0
		local resistance = defender:resistance_against(attack.type)
		local base_damage = (weapon_damage + damage_bonus) * (100 - resistance) * damage_multiplier
		if (resistance < 0) then
			base_damage = base_damage - 1
		end
		base_damage = math.floor(base_damage / 100 + 0.5)
		if (base_damage < 1) and (attack.damage > 0) then
			base_damage = 1
		end
		local attack_damage = base_damage * attack.number * defense - drain_recovery

		local poison_damage = 0
		if poison then
			poison_damage = wesnoth.game_config.poison_amount * (1 - ((1 - defense) ^ attack.number))
		end

		if (not best_attack) or (attack_damage + poison_damage > best_damage + best_poison_damage) then
			best_damage = attack_damage
			best_poison_damage = poison_damage
			best_attack = attack
		end
	end

	return best_attack, best_damage, best_poison_damage
end

local function analyze(enemy_type, ally_type)
	analyses[enemy_type] = analyses[enemy_type] or {}
	if analyses[enemy_type][ally_type] then
		return analyses[enemy_type][ally_type]
	end

	local unit = test_unit(enemy_type)
	local can_poison = poisonable(unit) and (not unit:ability('regenerate'))
	local flat_defense = 100 - unit:defense_on("Gt")
	local best_defense = get_best_defense(unit)

	local recruit = test_unit(ally_type)
	local recruit_flat_defense = 100 - recruit:defense_on("Gt")
	local recruit_best_defense = get_best_defense(recruit)
	local can_poison_retaliation = poisonable(recruit) and (not recruit:ability('regenerate'))

	local off_attack, off_damage, off_poison = get_best_attack(recruit, unit, flat_defense, recruit_best_defense, can_poison)
	local def_attack, def_damage, def_poison = get_best_attack(recruit, unit, best_defense, recruit_flat_defense, can_poison)
	local ret_attack, ret_damage, ret_poison = get_best_attack(unit, recruit, recruit_flat_defense, best_defense, can_poison_retaliation)

	analyses[enemy_type][ally_type] = {
		offense     = { attack = off_attack, damage = off_damage, poison_damage = off_poison },
		defense     = { attack = def_attack, damage = def_damage, poison_damage = def_poison },
		retaliation = { attack = ret_attack, damage = ret_damage, poison_damage = ret_poison }
	}
	return analyses[enemy_type][ally_type]
end

local function hp_efficiency(unit_type)
	local effective_hp = wesnoth.unit_types[unit_type].max_hitpoints

	local abilities = wml.get_child(test_unit(unit_type).__cfg, "abilities")
	local regen_amount = 0
	if abilities then
		for regen in wml.child_range(abilities, "regenerate") do
			local value = tonumber(regen.value)
			if value and value > regen_amount then
				regen_amount = value
			end
		end
		effective_hp = effective_hp + (regen_amount * effective_hp / 30)
	end

	local hp_score = math.max(math.log(effective_hp / 20), 0.01)
	return hp_score / (wesnoth.unit_types[unit_type].cost ^ 2)
end

local function can_slow(unit)
	local attacks = unit.attacks
	for i_a = 1,#attacks do
		for _,sp in ipairs(attacks[i_a].specials) do
			if (sp[1] == 'slow') then return true end
		end
	end
	return false
end

local function time_of_day_bonus(alignment, lawful_bonus)
	local multiplier = 1
	if (lawful_bonus ~= 0) then
		if (alignment == 'lawful') then
			multiplier = (1 + lawful_bonus / 100.)
		elseif (alignment == 'chaotic') then
			multiplier = (1 - lawful_bonus / 100.)
		elseif (alignment == 'liminal') then
			multiplier = (1 - math.abs(lawful_bonus) / 100.)
		end
	end
	return multiplier
end

local function live_units(filter)
	return wesnoth.units.find_on_map { T["not"] { status = "petrified" }, T["and"] (filter) }
end

-- співвідношення здоров'я своїх і ворожих військ, із золотом, переведеним у hp
local function hp_ratio_with_gold(side)
	local function sum_gold(side_filter)
		local gold = 0
		for _,s in ipairs(wesnoth.sides.find(side_filter)) do
			if s.gold > 0 then gold = gold + s.gold end
		end
		return gold
	end

	local my_hp, enemy_hp = 0, 0
	for _,u in ipairs(live_units { T.filter_side { T.allied_with { side = side } } }) do
		my_hp = my_hp + u.hitpoints
	end
	for _,u in ipairs(live_units { T.filter_side { T.enemy_of { side = side } } }) do
		enemy_hp = enemy_hp + u.hitpoints
	end

	my_hp = my_hp + sum_gold { T.allied_with { side = side } } * 2.3
	enemy_hp = enemy_hp + sum_gold { T.enemy_of { side = side } } * 2.3
	if (enemy_hp == 0) then enemy_hp = 1 end
	return my_hp / enemy_hp
end

local function enemy_composition(side)
	local counts, types, num = {}, {}, 0
	for _,u in ipairs(live_units { T.filter_side { T.enemy_of { side = side } } }) do
		if wesnoth.unit_types[u.type] then
			if not counts[u.type] then
				counts[u.type] = 0
				table.insert(types, u.type)
			end
			counts[u.type] = counts[u.type] + 1
			num = num + 1
		end
	end
	return counts, types, num
end

local function possible_enemy_recruit_count(side)
	local count = 0
	for _,s in ipairs(wesnoth.sides.find { T.enemy_of { side = side } }) do
		count = count + #s.recruit
	end
	for _,u in ipairs(live_units { canrecruit = "yes", T.filter_side { T.enemy_of { side = side } } }) do
		count = count + #u.extra_recruit
	end
	return count
end

-- Що сторона взагалі може вербувати з цього лідера
local function recruit_types_of(side, leader)
	local types = {}
	for _,unit_type in ipairs(wesnoth.sides[side].recruit) do
		if wesnoth.unit_types[unit_type] then types[unit_type] = true end
	end
	for _,unit_type in ipairs(leader.extra_recruit) do
		if wesnoth.unit_types[unit_type] then types[unit_type] = true end
	end
	return types
end

-- Вільні гекси замку, з'єднаного саме з кіпом цього лідера
local function free_castle_hexes(leader)
	return wesnoth.map.find {
		terrain = CASTLE,
		T["and"] {
			x = leader.x, y = leader.y,
			radius = 99,
			T.filter_radius { terrain = CASTLE }
		},
		T["not"] { T.filter {} }
	}
end

-- Порт фолбек-гілки find_best_recruit_hex(): гекс, найближчий до ворога
local function find_best_recruit_hex(side, hexes)
	local enemy_leaders = live_units { canrecruit = "yes", T.filter_side { T.enemy_of { side = side } } }
	local enemies = live_units { T.filter_side { T.enemy_of { side = side } } }

	local best_hex, max_rating = hexes[1], -1
	for _,c in ipairs(hexes) do
		local rating = 0
		for _,e in ipairs(enemy_leaders) do
			rating = rating + 1 / math.max(M.distance_between(c[1], c[2], e.x, e.y), 1) ^ 2.
		end

		local closest_dist = math.huge
		for _,e in ipairs(enemies) do
			local d = M.distance_between(c[1], c[2], e.x, e.y)
			if d < closest_dist then closest_dist = d end
		end
		if closest_dist < math.huge then
			rating = rating + 1 / math.max(closest_dist, 1) ^ 2.
		end

		if (rating > max_rating) then
			max_rating, best_hex = rating, c
		end
	end
	return best_hex
end

-- Куди взагалі рухатись: найближчий ворог, інакше стартовий гекс ворожої
-- сторони, інакше дзеркальна точка мапи. Порт із find_best_recruit().
local function enemy_location_for(side, reference_hex)
	local closest, min_dist = nil, math.huge
	for _,e in ipairs(live_units { T.filter_side { T.enemy_of { side = side } } }) do
		local d = M.distance_between(reference_hex[1], reference_hex[2], e.x, e.y)
		if d < min_dist then min_dist, closest = d, { x = e.x, y = e.y } end
	end
	if closest then return closest, min_dist end

	for _,s in ipairs(wesnoth.sides.find { T.enemy_of { side = side } }) do
		local start_hex = wesnoth.current.map.special_locations[s.side]
		if start_hex then
			local d = M.distance_between(reference_hex[1], reference_hex[2], start_hex[1], start_hex[2])
			if d < min_dist then min_dist, closest = d, { x = start_hex[1], y = start_hex[2] } end
		end
	end
	if closest then return closest, min_dist end

	local map = wesnoth.current.map
	closest = { x = map.playable_width + 1 - reference_hex[1], y = map.playable_height + 1 - reference_hex[2] }
	return closest, M.distance_between(reference_hex[1], reference_hex[2], closest.x, closest.y)
end

-- Порт першої половини ca_recruit_rushers:execution(): наскільки кожен
-- доступний тип б'є наявних ворогів і наскільки сам від них потерпає.
local function rate_recruit_types(side, recruit_types, enemy_counts, enemy_types, num_enemies, enemy_recruit_count)
	local recruit_count = {}
	for recruit_id in pairs(recruit_types) do
		recruit_count[recruit_id] = #live_units { side = side, type = recruit_id, canrecruit = "no" }
	end

	local effectiveness, vulnerability = {}, {}
	local attack_type_count, attack_range_count = {}, {}
	local unit_attack_type_count, unit_attack_range_count = {}, {}
	local enemy_type_count, poisoner_count, poisonable_count = 0, 0.1, 0

	for _,unit_type in ipairs(enemy_types) do
		enemy_type_count = enemy_type_count + 1
		local poison_vulnerable = false

		for recruit_id in pairs(recruit_types) do
			local analysis = analyze(unit_type, recruit_id)

			if not effectiveness[recruit_id] then
				effectiveness[recruit_id] = { damage = 0, poison_damage = 0 }
				vulnerability[recruit_id] = 0
			end

			effectiveness[recruit_id].damage = effectiveness[recruit_id].damage
				+ analysis.defense.damage * enemy_counts[unit_type] ^ 2
			if analysis.defense.poison_damage and analysis.defense.poison_damage > 0 then
				poison_vulnerable = true
				effectiveness[recruit_id].poison_damage = effectiveness[recruit_id].poison_damage
					+ analysis.defense.poison_damage * enemy_counts[unit_type] ^ 2
			end
			vulnerability[recruit_id] = vulnerability[recruit_id]
				+ (analysis.retaliation.damage * enemy_counts[unit_type]) ^ 3

			unit_attack_type_count[recruit_id] = unit_attack_type_count[recruit_id] or {}
			unit_attack_range_count[recruit_id] = unit_attack_range_count[recruit_id] or {}

			-- у типу без жодної атаки best_attack порожній, і рахувати нічого
			if analysis.defense.attack then
				local attack_type = analysis.defense.attack.type
				attack_type_count[attack_type] = (attack_type_count[attack_type] or 0) + recruit_count[recruit_id]

				local attack_range = analysis.defense.attack.range
				attack_range_count[attack_range] = (attack_range_count[attack_range] or 0) + recruit_count[recruit_id]

				unit_attack_type_count[recruit_id][attack_type] = true
				unit_attack_range_count[recruit_id][attack_range] = true
			end
		end

		if poison_vulnerable then
			poisonable_count = poisonable_count + enemy_counts[unit_type]
		end
	end

	for recruit_id in pairs(recruit_types) do
		if effectiveness[recruit_id].poison_damage > 0 then
			poisoner_count = poisoner_count + recruit_count[recruit_id]
		end
	end

	local poison_modifier = math.max(0, math.min(((poisonable_count - enemy_recruit_count) / (poisoner_count * 5)), 1)) ^ 2
	for recruit_id in pairs(recruit_types) do
		if effectiveness[recruit_id].damage <= 0 then
			effectiveness[recruit_id].damage = 0.01
		else
			effectiveness[recruit_id].damage = (effectiveness[recruit_id].damage / num_enemies ^ 2) ^ 0.5
		end
		effectiveness[recruit_id].poison_damage =
			(effectiveness[recruit_id].poison_damage / num_enemies ^ 2) ^ 0.5 * poison_modifier
		if vulnerability[recruit_id] <= 0 then
			vulnerability[recruit_id] = 0.01
		else
			vulnerability[recruit_id] = (vulnerability[recruit_id] / num_enemies ^ 2) ^ 0.5
		end
	end

	if enemy_type_count == 0 then enemy_type_count = 1 end

	local most_common_range, most_common_range_count = nil, 0
	for range, count in pairs(attack_range_count) do
		attack_range_count[range] = count / enemy_type_count
		if attack_range_count[range] > most_common_range_count then
			most_common_range, most_common_range_count = range, attack_range_count[range]
		end
	end
	for attack_type, count in pairs(attack_type_count) do
		attack_type_count[attack_type] = count / enemy_type_count
	end

	return {
		effectiveness = effectiveness,
		vulnerability = vulnerability,
		attack_type_count = attack_type_count,
		attack_range_count = attack_range_count,
		unit_attack_type_count = unit_attack_type_count,
		unit_attack_range_count = unit_attack_range_count,
		most_common_range_count = most_common_range_count
	}
end

-- Порт find_best_recruit(): підсумковий рейтинг типів
local function find_best_recruit(side, recruit_types, ratings, best_hex, gold, opts)
	local enemy_location, distance_to_enemy = enemy_location_for(side, best_hex)

	local recruit_scores = {}
	local best_scores = { offense = 0, defense = 0, move = 0 }

	for recruit_id in pairs(recruit_types) do
		local attack_types, neighbours = 0, 0
		for attack_type in pairs(ratings.unit_attack_type_count[recruit_id]) do
			attack_types = attack_types + 1
			neighbours = neighbours + ratings.attack_type_count[attack_type]
		end
		if attack_types > 0 then neighbours = neighbours / attack_types end
		local recruit_modifier = 1 + neighbours / 50
		local unit_cost = wesnoth.unit_types[recruit_id].cost

		local recruit_unit = wesnoth.units.create {
			type = recruit_id,
			x = best_hex[1], y = best_hex[2],
			random_traits = false,
			name = "X",
			random_gender = false
		}

		local max_moves = wesnoth.unit_types[recruit_id].max_moves
		local _, cost = wesnoth.paths.find_path(recruit_unit, enemy_location.x, enemy_location.y, { ignore_units = true })
		local time_to_enemy = (max_moves > 0) and (cost / max_moves) or math.huge
		-- тримаємо значення скінченним: math.ceil(math.huge) у Lua 5.4 — помилка,
		-- а нескінченність тут цілком реальна (max_moves=0 або ворог недосяжний)
		if time_to_enemy <= 0 then time_to_enemy = 0.01 end
		if time_to_enemy > 100 then time_to_enemy = 100 end
		local move_score = 1 / (time_to_enemy * unit_cost ^ 0.5)

		local eta = math.ceil(time_to_enemy)
		local eta_turn = wesnoth.current.turn + eta
		local lawful_bonus = 0
		if (wesnoth.scenario.turns < 0) or (eta_turn <= wesnoth.scenario.turns) then
			lawful_bonus = wesnoth.schedule.get_time_of_day(nil, eta_turn).lawful_bonus / eta ^ 2
		end
		local damage_bonus = time_of_day_bonus(recruit_unit.alignment, lawful_bonus)

		local offense_score =
			(ratings.effectiveness[recruit_id].damage * damage_bonus + ratings.effectiveness[recruit_id].poison_damage)
			/ (unit_cost ^ 0.3 * recruit_modifier ^ 4)
		local defense_score = hp_efficiency(recruit_id) / ratings.vulnerability[recruit_id]

		local unit_score = { offense = offense_score, defense = defense_score, move = move_score }
		recruit_scores[recruit_id] = unit_score
		for key, score in pairs(unit_score) do
			if score > best_scores[key] then best_scores[key] = score end
		end

		if can_slow(recruit_unit) then unit_score["slows"] = true end
		if recruit_unit:matches { ability = "healing" } then unit_score["heals"] = true end
		if recruit_unit:matches { ability = "skirmisher" } then unit_score["skirmisher"] = true end
	end

	local healer_count = #live_units { side = side, ability = "healing", canrecruit = "no" }
	local healable_count = #live_units { side = side, T["not"] { ability = "regenerates" } }
	local hp_ratio = hp_ratio_with_gold(side)

	local offense_weight = 2.5
	local defense_weight = 1 / hp_ratio ^ 0.5
	local move_weight = math.max((distance_to_enemy / 20) ^ 2, 0.25)

	-- бонус вищим рівням, бо їх карає врахування ціни
	local all_units = live_units { side = side, canrecruit = "no" }
	local level_count = {}
	for _,unit in ipairs(all_units) do
		level_count[unit.level] = (level_count[unit.level] or 0) + 1
	end
	local min_recruit_level, max_recruit_level = math.huge, -math.huge
	for recruit_id in pairs(recruit_types) do
		local level = wesnoth.unit_types[recruit_id].level
		if (level < min_recruit_level) then min_recruit_level = level end
		if (level > max_recruit_level) then max_recruit_level = level end
	end
	if (min_recruit_level < 1) then min_recruit_level = 1 end

	local high_level_fraction = opts.high_level_fraction
	local unit_deficit = {}
	for i = min_recruit_level + 1, max_recruit_level do
		local n_units = #all_units
		local n_units_this_level = level_count[i] or 0
		if (n_units == 0) then
			n_units = max_recruit_level - min_recruit_level
			n_units_this_level = 1
		end
		unit_deficit[i] = high_level_fraction ^ (i - min_recruit_level) * n_units - n_units_this_level
	end

	local candidates, total_weight = {}, 0
	local best_score, best_type = 0, nil
	for recruit_id in pairs(recruit_types) do
		local level_bonus = 0
		local level = wesnoth.unit_types[recruit_id].level
		if (level > min_recruit_level) and (unit_deficit[level] > 0) then
			level_bonus = 0.25 * unit_deficit[level] ^ 2
		end

		local scores = recruit_scores[recruit_id]
		local offense_score = (scores["offense"] / best_scores["offense"]) ^ 0.5
		local defense_score = (scores["defense"] / best_scores["defense"]) ^ 0.5
		local move_score = (scores["move"] / best_scores["move"]) ^ 0.5

		local bonus = 0
		if scores["slows"] then bonus = bonus + 0.4 end
		if scores["heals"] then bonus = bonus + (healable_count / (healer_count + 1)) / 20 end
		if scores["skirmisher"] then bonus = bonus + 0.1 end
		for attack_range in pairs(ratings.unit_attack_range_count[recruit_id]) do
			bonus = bonus + 0.02 * ratings.most_common_range_count / (ratings.attack_range_count[attack_range] + 1)
		end
		local race = wesnoth.races[wesnoth.unit_types[recruit_id].race]
		local num_traits = race and race.num_traits or 0
		bonus = bonus + 0.03 * num_traits ^ 2

		local score = offense_score * offense_weight + defense_score * defense_weight
			+ move_score * move_weight + bonus + level_bonus

		if (score > 0) and (wesnoth.unit_types[recruit_id].cost <= gold) then
			if score > best_score then
				best_score, best_type = score, recruit_id
			end
			local weight = score ^ opts.selectivity
			table.insert(candidates, { id = recruit_id, weight = weight })
			total_weight = total_weight + weight
		end
	end

	if #candidates == 0 then return nil end
	if opts.selectivity <= 0 then return best_type end

	-- Замість жорсткого argmax — випадковий вибір із вагою score^selectivity.
	-- Інакше та сама оцінка щоразу дає той самий тип, і замок заповнюється
	-- клонами; штатний ШІ розводить це аспектом recruitment_randomness.
	-- mathx.random — синхронізований ГВЧ, тож у мережевій грі десинку не буде.
	local roll = mathx.random(1, 1000000) / 1000000 * total_weight
	for _,candidate in ipairs(candidates) do
		roll = roll - candidate.weight
		if roll <= 0 then return candidate.id end
	end
	return candidates[#candidates].id
end

function wesnoth.wml_actions.force_recruit_full(cfg)
	local side = cfg.side or wml.error "[force_recruit_full] потребує side="
	local leader = wesnoth.units.find_on_map { side = side, canrecruit = "yes", id = cfg.id }[1]
	if not leader then return end

	test_units, analyses = {}, {}

	local recruit_types = recruit_types_of(side, leader)
	if not next(recruit_types) then return end

	local cheapest = math.huge
	for recruit_id in pairs(recruit_types) do
		local cost = wesnoth.unit_types[recruit_id].cost
		if cost < cheapest then cheapest = cost end
	end

	local hexes = free_castle_hexes(leader)
	if (#hexes == 0) or (wesnoth.sides[side].gold < cheapest) then return end

	local enemy_counts, enemy_types, num_enemies = enemy_composition(side)
	if num_enemies == 0 then return end
	local enemy_recruit_count = possible_enemy_recruit_count(side)

	local opts = {
		-- приблизна частка юнітів 2-го рівня й вище; без цього ціна у знаменнику
		-- hp_efficiency (cost^2) намертво тягне вибір у найдешевший 1-й рівень
		high_level_fraction = tonumber(cfg.high_level_fraction) or 0.5,
		-- 0 = завжди найкращий тип, більше = сильніше тримається найкращих
		selectivity = tonumber(cfg.selectivity) or 4
	}

	if cfg.animate then
		wesnoth.wml_actions.animate_unit { flag = "leading", T.filter { id = leader.id } }
	end

	while (#hexes > 0) and (wesnoth.sides[side].gold >= cheapest) do
		-- рейтинги перераховуються щоразу: щойно завербований юніт змінює
		-- склад війська, а отже й доцільність наступного вербування
		local ratings = rate_recruit_types(side, recruit_types, enemy_counts, enemy_types, num_enemies, enemy_recruit_count)

		local best_hex = find_best_recruit_hex(side, hexes)
		local recruit_type = find_best_recruit(side, recruit_types, ratings, best_hex, wesnoth.sides[side].gold, opts)
		if not recruit_type then break end

		wesnoth.wml_actions.unit {
			side = side,
			type = recruit_type,
			x = best_hex[1], y = best_hex[2],
			placement = "map",
			passable = true,
			animate = cfg.animate
		}
		wesnoth.sides[side].gold = wesnoth.sides[side].gold - wesnoth.unit_types[recruit_type].cost

		hexes = free_castle_hexes(leader)
	end

	test_units, analyses = nil, nil
end
