-- Chasing the Light -- shared per-turn maps for the escort/convoy AI
--
-- Both ca_ctl_escort and ca_ctl_convoy need the same three things, and all
-- three are expensive enough that recomputing them on every candidate action
-- evaluation is what makes the AI crawl. Everything here is cached for the
-- duration of one side turn.
--
-- Note on the enemy maps: battle_calcs.get_attack_map takes every movable unit
-- of the current side off the map and puts it back *for each enemy unit*
-- (battle_calcs.lua:1170-1180). With ~40 enemies and ~35 own units that is
-- ~2800 extract/to_map round trips per call. The version here extracts once for
-- the whole loop instead.
--
-- Both candidate actions must pass the same escort set, since the cover map is
-- cached on the first call of the turn.

local AH = wesnoth.require "ai/lua/ai_helper.lua"
local LS = wesnoth.require "location_set"
local M = wesnoth.map

local ctl_ai_maps = {}

local threat_cache = { turn = -1, side = -1 }
local cover_cache = { turn = -1, side = -1 }
local route_cache = { turn = -1, side = -1, routes = {} }

local function stale(cache)
    return (cache.turn ~= wesnoth.current.turn) or (cache.side ~= wesnoth.current.side)
end

local function stamp(cache)
    cache.turn, cache.side = wesnoth.current.turn, wesnoth.current.side
end

--------------------------------------------------------------------------------
-- enemy reach and threat
--------------------------------------------------------------------------------

---Returns two location sets:
---  reach   : value = number of enemies that can MOVE onto the hex
---  threats : value = array of enemies that can ATTACK the hex
function ctl_ai_maps.threat()
    if (not stale(threat_cache)) then
        return threat_cache.reach, threat_cache.threats
    end

    local own = wesnoth.units.find_on_map { side = wesnoth.current.side }

    -- Only enemies close enough to interfere are worth the pathfinding
    local enemies = {}
    for _,enemy in ipairs(AH.get_attackable_enemies()) do
        local cutoff = enemy.max_moves + 6
        for _,u in ipairs(own) do
            if (M.distance_between(enemy.x, enemy.y, u.x, u.y) <= cutoff) then
                table.insert(enemies, enemy)
                break
            end
        end
    end

    local reach, threats = LS.create(), LS.create()

    -- Take own units that can still move off the map once for the whole loop,
    -- so that the enemy reach is the worst case rather than a function of the
    -- order we happen to move in
    local movable = {}
    for _,u in ipairs(own) do
        if (u.moves > 0) then
            table.insert(movable, u)
            u:extract()
        end
    end

    local ok, err = pcall(function()
        for _,enemy in ipairs(enemies) do
            local old_moves = enemy.moves
            enemy.moves = enemy.max_moves
            local enemy_reach = wesnoth.paths.find_reach(enemy)
            enemy.moves = old_moves

            -- Collect this enemy's attackable hexes first, so that it is entered
            -- into 'threats' once per hex rather than once per adjacent reach hex
            local attackable = LS.create()
            for _,loc in ipairs(enemy_reach) do
                reach:insert(loc[1], loc[2], (reach:get(loc[1], loc[2]) or 0) + 1)

                attackable:insert(loc[1], loc[2], true)
                for xa,ya in wesnoth.current.map:iter_adjacent(loc) do
                    attackable:insert(xa, ya, true)
                end
            end

            attackable:iter(function(x, y)
                local here = threats:get(x, y) or {}
                table.insert(here, enemy)
                threats:insert(x, y, here)
            end)
        end
    end)

    -- Always put the units back, even if the pathfinding blew up
    for _,u in ipairs(movable) do u:to_map() end
    if (not ok) then error(err) end

    stamp(threat_cache)
    threat_cache.reach, threat_cache.threats = reach, threats
    return reach, threats
end

--------------------------------------------------------------------------------
-- escort cover
--------------------------------------------------------------------------------

---Location set whose value is the number of escorts that could be standing on
---or next to the hex after one full turn of movement. Used to decide whether the
---convoy may advance to a hex, so it is deliberately computed from the escorts'
---start-of-turn positions.
function ctl_ai_maps.cover(escorts)
    if (not stale(cover_cache)) then return cover_cache.cover end

    local cover = LS.create()
    for _,escort in ipairs(escorts) do
        local old_moves = escort.moves
        escort.moves = escort.max_moves
        local reach = wesnoth.paths.find_reach(escort)
        escort.moves = old_moves

        local covered = LS.create()
        for _,loc in ipairs(reach) do
            covered:insert(loc[1], loc[2], true)
            for xa,ya in wesnoth.current.map:iter_adjacent(loc) do
                covered:insert(xa, ya, true)
            end
        end

        covered:iter(function(x, y)
            cover:insert(x, y, (cover:get(x, y) or 0) + 1)
        end)
    end

    stamp(cover_cache)
    cover_cache.cover = cover
    return cover
end

--------------------------------------------------------------------------------
-- route and progress along it
--------------------------------------------------------------------------------

---The convoy's actual route to the goal, and a function giving how far along
---that route any hex on the map is.
---
---Progress is defined as max over the route of (step index - distance to that
---step). That follows the real corridor rather than the straight line, which
---matters here because the only crossing of the Elderflow is the bridge: a hex
---due south of a unit north of the river is *not* closer to the mine.
---
---Returns route, progress_fn, or nil if there is no route at all.
function ctl_ai_maps.route(unit, goal_x, goal_y, avoid_map)
    if stale(route_cache) then
        stamp(route_cache)
        route_cache.routes = {}
    end

    local key = unit.id .. '|' .. goal_x .. ',' .. goal_y
    local entry = route_cache.routes[key]
    if entry then return entry.route, entry.progress end

    -- ignore_enemies gives the corridor the convoy is trying to follow rather
    -- than a detour around whatever happens to stand in the way this turn
    local route, cost = AH.find_path_with_avoid(
        unit, goal_x, goal_y, avoid_map, { ignore_enemies = true })

    if (not route) or (cost >= AH.no_path) then
        route_cache.routes[key] = { route = false }
        return
    end

    local memo = LS.create()
    local function progress(x, y)
        local cached = memo:get(x, y)
        if cached then return cached end

        local best = -math.huge
        for i,step in ipairs(route) do
            local value = i - M.distance_between(x, y, step[1], step[2])
            if (value > best) then best = value end
        end

        memo:insert(x, y, best)
        return best
    end

    route_cache.routes[key] = { route = route, progress = progress }
    return route, progress
end

return ctl_ai_maps
