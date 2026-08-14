-- Chasing the Light -- convoy candidate action
--
-- Caps how far a protected unit is allowed to advance in one turn: it may only
-- stop on a hex that enough of its escorts could reach by next turn. Without
-- this the caravan simply outruns its guard -- it makes 4-5 hexes a turn while
-- an escort that has fallen behind closes the gap by one hex a turn, so the gap
-- never shrinks and the escort arrives after the fight is over.
--
-- Runs above ca_messenger_move: once this CA has moved the unit, move_full has
-- taken its remaining MP, so the messenger CA leaves it alone for the turn. When
-- the escort is in position this CA finds a covered hex ahead and the convoy
-- rolls on at normal speed, so it costs nothing when nothing is wrong.
--
-- [args] parameters:
--   [filter]         -- the protected units (SUF, own side implied)   required
--   [filter_second]  -- units that count as their escort (SUF)        required
--   goal_x=, goal_y= -- where the protected units are heading         required
--   [avoid]          -- hexes to route around (SLF)                   optional
--   min_cover=N      -- escorts that must be able to reach the hex    default 2
--   ca_score=N       -- passed in by the [candidate_action]           default 300000

local AH = wesnoth.require "ai/lua/ai_helper.lua"
local LS = wesnoth.require "location_set"
local MAPS = wesnoth.require "~add-ons/Chasing_the_Light/lua/ai/ctl_ai_maps.lua"
local M = wesnoth.map

local best_unit, best_hex, best_is_wait

local ca_ctl_convoy = {}

function ca_ctl_convoy:evaluation(cfg)
    best_unit, best_hex, best_is_wait = nil, nil, false

    local score = cfg.ca_score or 300000
    local min_cover = tonumber(cfg.min_cover) or 2

    local goal_x, goal_y = tonumber(cfg.goal_x), tonumber(cfg.goal_y)
    local filter = wml.get_child(cfg, "filter")
    local filter_second = wml.get_child(cfg, "filter_second")
    if (not filter) or (not filter_second) or (not goal_x) or (not goal_y) then
        wml.error("ca_ctl_convoy requires [filter], [filter_second], goal_x= and goal_y= in [args]")
    end

    -- Everything below costs pathfinding, so get out early on the many
    -- evaluations of the turn where there is nothing left to move
    local protectees = AH.get_units_with_moves {
        side = wesnoth.current.side,
        { "and", filter }
    }
    if (not protectees[1]) then return 0 end

    local escorts = AH.get_live_units {
        side = wesnoth.current.side,
        { "and", filter_second }
    }

    -- Nothing left to wait for: holding the convoy back would only run the clock
    -- out, so the leash takes itself off
    if (#escorts < min_cover) then return 0 end

    -- Both maps are built once per side turn and shared with ca_ctl_escort
    local cover_map = MAPS.cover(escorts)
    local _, danger = MAPS.threat()

    local avoid_map = AH.get_avoid_map(ai, wml.get_child(cfg, "avoid"), true)

    -- How well defended the unit would be on a hex. A hex no enemy can attack
    -- counts as fully covered, since there is nothing to defend against; that is
    -- what keeps the convoy at full speed through empty country.
    local function safety_level(x, y)
        local attackers = danger:get(x, y)
        if (not attackers) or (not attackers[1]) then return min_cover end
        return cover_map:get(x, y) or 0
    end

    local function is_safe_enough(x, y)
        -- Finishing is never held back: the goal hex is where the unit is taken
        -- off the map, so there is nothing left to protect it from
        if (x == goal_x) and (y == goal_y) then return true end
        return safety_level(x, y) >= min_cover
    end

    -- Closest to the goal first, so they do not block each other in the queue
    table.sort(protectees, function(a, b)
        return M.distance_between(a.x, a.y, goal_x, goal_y)
             < M.distance_between(b.x, b.y, goal_x, goal_y)
    end)

    for _,p in ipairs(protectees) do
        -- Two reach maps, as next_hop does: one to tell how far along the route
        -- the unit could get this turn, one to tell where it may actually stop
        local reach_any = AH.get_reachmap(p, { avoid_map = avoid_map })
        local reach_free = AH.get_reachmap(p, {
            exclude_occupied = true,
            avoid_map = avoid_map
        })

        local path, cost = AH.find_path_with_avoid(p, goal_x, goal_y, avoid_map)

        -- 1. Advance along the actual route, but only as far as the escort reaches
        local chosen
        if path and (cost < AH.no_path) then
            for i = 2, #path do
                local x, y = path[i][1], path[i][2]
                if (not reach_any:get(x, y)) then break end

                if reach_free:get(x, y) and is_safe_enough(x, y) then
                    chosen = { x, y }
                end
            end
        end

        if chosen then
            best_unit, best_hex, best_is_wait = p, chosen, false
            return score
        end

        -- 2. Nothing covered ahead. If the unit is standing somewhere its escort
        --    cannot reach either, fall back towards them rather than sit there.
        local own_safety = safety_level(p.x, p.y)
        if (own_safety < min_cover) then
            local best_rating, fallback = -math.huge, nil
            reach_free:iter(function(x, y)
                local rating = math.min(safety_level(x, y), min_cover) * 100
                    - M.distance_between(x, y, goal_x, goal_y)
                    + p:defense_on(wesnoth.current.map[{ x, y }]) / 100.
                if (rating > best_rating) then best_rating, fallback = rating, { x, y } end
            end)

            if fallback
                and ((fallback[1] ~= p.x) or (fallback[2] ~= p.y))
                and (safety_level(fallback[1], fallback[2]) > own_safety)
            then
                best_unit, best_hex, best_is_wait = p, fallback, false
                return score
            end
        end

        -- 3. Covered where it stands, but not on anything it could advance to:
        --    hold this turn and let the escort catch up
        best_unit, best_hex, best_is_wait = p, { p.x, p.y }, true
        return score
    end

    return 0
end

function ca_ctl_convoy:execution(cfg)
    local unit, hex, wait = best_unit, best_hex, best_is_wait
    best_unit, best_hex, best_is_wait = nil, nil, false

    if wait then
        -- Only the movement is given up; the unit keeps its attack
        AH.checked_stopunit_moves(ai, unit)
    else
        AH.checked_move_full(ai, unit, hex[1], hex[2])
    end
end

return ca_ctl_convoy
