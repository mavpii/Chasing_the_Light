local AH = wesnoth.require "ai/lua/ai_helper.lua"
local M = wesnoth.map

local plan

----------------------------
-- TARGETS
----------------------------
local function is_target(boss, e)
    return wesnoth.sides.is_enemy(boss.side, e.side)
        and not e.status.petrified
        and e.type ~= "Brazier" and e.type ~= "Brazier_Duty"
end

local function usable_hex(boss, x, y)
    local occ = wesnoth.units.get(x, y)
    if not occ or occ.id == boss.id then return true end
    return occ.side == boss.side and occ.moves > 0
end

----------------------------
-- ATTACK
----------------------------
local function best_attack(boss, reach, enemies, priority)
    local best, best_r
    for _, r in ipairs(reach) do
        local x, y = r[1], r[2]
        if usable_hex(boss, x, y) then
            for _, e in ipairs(enemies) do
                if M.distance_between(x, y, e.x, e.y) == 1 then
                    local probe = boss:clone()
                    probe.x, probe.y = x, y
                    local _, def = wesnoth.simulate_combat(probe, e)
                    local rating = (priority[e.id] and 1000 or 0)
                        + 100 * def.hp_chance[0]
                        + (e.hitpoints - def.average_hp)
                        + 5 * e.level
                        + 0.01 * (r[3] or 0)
                    if not best_r or rating > best_r then
                        best_r = rating
                        best = { src = { boss.x, boss.y }, dst = { x, y }, target = { e.x, e.y } }
                    end
                end
            end
        end
    end
    return best
end

----------------------------
-- APPROACH
----------------------------
local function best_approach(boss, reach, goals)
    local in_reach = {}
    for _, r in ipairs(reach) do
        if usable_hex(boss, r[1], r[2]) then in_reach[r[1] * 1000 + r[2]] = r[3] or 0 end
    end

    local best_path, best_cost
    for _, g in ipairs(goals) do
        local path, cost = wesnoth.paths.find_path(boss, g.x, g.y, { ignore_units = true })
        if path and #path > 1 and (not best_cost or cost < best_cost) then
            best_path, best_cost = path, cost
        end
    end

    if best_path then
        for i = #best_path - 1, 2, -1 do
            local s = best_path[i]
            local x, y = s.x or s[1], s.y or s[2]
            if in_reach[x * 1000 + y] and not (x == boss.x and y == boss.y) then
                return { src = { boss.x, boss.y }, dst = { x, y } }
            end
        end
    end

    local best, best_r
    for key, left in pairs(in_reach) do
        local x, y = key // 1000, key % 1000
        local d
        for _, g in ipairs(goals) do
            local dg = M.distance_between(x, y, g.x, g.y)
            if not d or dg < d then d = dg end
        end
        local rating = -d + 0.001 * left
        if not best_r or rating > best_r then best_r, best = rating, { x, y } end
    end
    if best and not (best[1] == boss.x and best[2] == boss.y) then
        return { src = { boss.x, boss.y }, dst = best }
    end
end

----------------------------
-- PLAN
----------------------------
local function find_plan(cfg)
    local boss = wesnoth.units.find_on_map{
        side = wesnoth.current.side,
        wml.tag["and"](wml.get_child(cfg, "filter") or {})
    }[1]
    if not boss or boss.status.petrified then return nil end
    if boss.moves <= 0 and boss.attacks_left <= 0 then return nil end

    local priority, goals = {}, {}
    local second = wml.get_child(cfg, "filter_second")
    if second then
        for _, h in ipairs(wesnoth.units.find_on_map(second)) do
            if is_target(boss, h) then
                priority[h.id] = true
                goals[#goals + 1] = h
            end
        end
    end

    local enemies = {}
    for _, e in ipairs(wesnoth.units.find_on_map{}) do
        if is_target(boss, e) then enemies[#enemies + 1] = e end
    end
    if #enemies == 0 then return nil end
    if #goals == 0 then goals = enemies end

    local reach
    if boss.moves > 0 then
        reach = wesnoth.paths.find_reach(boss)
    else
        reach = { { boss.x, boss.y, 0 } }
    end

    if boss.attacks_left > 0 then
        local att = best_attack(boss, reach, enemies, priority)
        if att then return att end
    end

    if boss.moves > 0 then
        return best_approach(boss, reach, goals)
    end
end

----------------------------
-- CA
----------------------------
local ca_ctl_boss_hunt = {}

function ca_ctl_boss_hunt:evaluation(cfg)
    plan = find_plan(cfg)
    if plan then return cfg.ca_score or 320000 end
    return 0
end

function ca_ctl_boss_hunt:execution(cfg)
    local p = plan
    plan = nil
    if not p then return end
    AH.robust_move_and_attack(ai, p.src, p.dst, p.target)
end

return ca_ctl_boss_hunt
