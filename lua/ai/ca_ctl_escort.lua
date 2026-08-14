-- Chasing the Light -- escort candidate action
--
-- Replacement for ai_type=messenger_escort's escort_move CA, whose entire notion
-- of "defending" is
--     10/(dist to messenger + 2) + sum over enemies of 1/(dist to enemy + 2)
-- i.e. pure geometry: no terrain, no threat, no matching of unit to hex, and it
-- grabs every unit of the side that still has moves.
--
-- Two layers, in this order of priority:
--   1. screen -- seal a hex next to a protected unit that an enemy could
--                otherwise step into, with the unit best able to hold it
--   2. column -- keep everyone else in a band a little ahead of the convoy,
--                measured along the convoy's actual route. This is what stops
--                units drifting off north to fight while the convoy heads
--                south, pulls stragglers forward, and puts the escort on the
--                hexes the convoy needs covered before it can advance.
--                When something is chasing the column, a share of the escort
--                proportional to the threat behind is held back as a rearguard
--                instead of being sent to the front.
--
-- [args] parameters:
--   [filter]         -- protected units (SUF, own side implied)      required
--   [filter_second]  -- units allowed to act as escorts (SUF)        required
--   goal_x=, goal_y= -- where the convoy is heading                  required
--   [avoid]          -- hexes escorts must never stand on (SLF)      optional
--   ring2=yes/no     -- also form a second line at distance 2        default yes
--   max_per_unit=N   -- cap of escorts committed per protectee       default 6
--   min_quality=F    -- refuse screen placements worse than this     default 0.18
--   vanguard_lead=N  -- how far ahead of the convoy the column sits  default 4
--   column_slack=N   -- tolerance before a unit is repositioned      default 2
--   rear_guard=N     -- how far behind the convoy the tail sits      default 3
--   threat_radius=N  -- enemies inside this count towards the split  default 12
--   ca_score=N       -- passed in by the [candidate_action]          default 105000

local AH = wesnoth.require "ai/lua/ai_helper.lua"
local LS = wesnoth.require "location_set"
local MAPS = wesnoth.require "~add-ons/Chasing_the_Light/lua/ai/ctl_ai_maps.lua"
local M = wesnoth.map

-- Result of the evaluation, consumed by the execution
local best_unit, best_hex

-- How many reach maps one evaluation may build. This CA runs after every single
-- action of the side, so this is the main lever on how heavy it is.
local MAX_REACHMAPS = 6

-- Fraction of @unit expected to still be standing on (@x,@y) at the start of our
-- next turn, clamped to (0, 1]. Also returns the defense there and how many
-- enemies can reach it. The damage model itself lives in ctl_ai_maps so that the
-- convoy CA works from exactly the same numbers.
local function survival_on(unit, x, y, threats)
    local incoming, defense, n_attackers = MAPS.exposure(unit, x, y, threats)

    local survival = (unit.hitpoints - incoming) / unit.max_hitpoints
    if (survival < 0.05) then survival = 0.05 end
    if (survival > 1.) then survival = 1. end

    return survival, defense, n_attackers
end

--------------------------------------------------------------------------------
-- screen hexes
--------------------------------------------------------------------------------

-- The hexes worth standing on: those adjacent to a protectee that an enemy could
-- otherwise step into, plus (optionally) a second line behind them.
local function get_screen_hexes(protectees, reach, avoid_map, use_ring2)
    local hexes, seen = {}, LS.create()

    local function consider(x, y, ring, protectee)
        local ring_weight = (ring == 1) and 3. or 1.

        -- A hex that shields two protectees at once is worth more, not the same
        local existing = seen:get(x, y)
        if existing then
            hexes[existing].importance = hexes[existing].importance
                + (reach:get(x, y) or 0) * ring_weight
            return
        end

        if (not wesnoth.current.map:on_board(x, y)) then return end
        if avoid_map:get(x, y) then return end

        -- A hex an enemy cannot enter does not need to be sealed
        local n_enemies = reach:get(x, y) or 0
        if (n_enemies == 0) then return end

        local occupant = wesnoth.units.get(x, y)
        if occupant then
            -- Already held by a unit that cannot move any more, or blocked by
            -- someone we do not command
            if (occupant.side ~= wesnoth.current.side) then return end
            if (occupant.moves == 0) then return end
        end

        table.insert(hexes, {
            x = x, y = y,
            protectee = protectee,
            importance = n_enemies * ring_weight
        })
        seen:insert(x, y, #hexes)
    end

    for _,p in ipairs(protectees) do
        for xa,ya in wesnoth.current.map:iter_adjacent(p) do
            consider(xa, ya, 1, p)
        end
    end

    if use_ring2 then
        for _,p in ipairs(protectees) do
            -- Each ring 2 hex neighbours up to two ring 1 hexes of the same
            -- protectee; it must still only be credited to it once
            local done = LS.create()
            for xa,ya in wesnoth.current.map:iter_adjacent(p) do
                for xb,yb in wesnoth.current.map:iter_adjacent({ xa, ya }) do
                    if (not done:get(xb, yb))
                        and (M.distance_between(xb, yb, p.x, p.y) == 2)
                    then
                        done:insert(xb, yb, true)
                        consider(xb, yb, 2, p)
                    end
                end
            end
        end
    end

    table.sort(hexes, function(a, b) return a.importance > b.importance end)
    return hexes
end

--------------------------------------------------------------------------------
-- candidate action
--------------------------------------------------------------------------------

local ca_ctl_escort = {}

function ca_ctl_escort:evaluation(cfg)
    best_unit, best_hex = nil, nil

    local score = cfg.ca_score or 105000
    local use_ring2 = (cfg.ring2 ~= false)
    local max_per_unit = tonumber(cfg.max_per_unit) or 6
    local min_quality = tonumber(cfg.min_quality) or 0.18
    local vanguard_lead = tonumber(cfg.vanguard_lead) or 4
    local column_slack = tonumber(cfg.column_slack) or 2
    local rear_guard = tonumber(cfg.rear_guard) or 3
    local threat_radius = tonumber(cfg.threat_radius) or 12

    local goal_x, goal_y = tonumber(cfg.goal_x), tonumber(cfg.goal_y)
    local filter = wml.get_child(cfg, "filter")
    local filter_second = wml.get_child(cfg, "filter_second")
    if (not filter) or (not filter_second) or (not goal_x) or (not goal_y) then
        wml.error("ca_ctl_escort requires [filter], [filter_second], goal_x= and goal_y= in [args]")
    end

    local protectees = AH.get_live_units {
        side = wesnoth.current.side,
        { "and", filter }
    }
    if (not protectees[1]) then return 0 end

    local escorts = AH.get_units_with_moves({
        side = wesnoth.current.side,
        { "and", filter_second }
    }, true)
    if (not escorts[1]) then return 0 end

    local reach, threats, enemies = MAPS.threat()
    local avoid_map = AH.get_avoid_map(ai, wml.get_child(cfg, "avoid"), true)

    local reachmaps, n_reachmaps = {}, 0
    local function reachmap_of(unit)
        local existing = reachmaps[unit.id]
        if existing then return existing end
        if (n_reachmaps >= MAX_REACHMAPS) then return end

        n_reachmaps = n_reachmaps + 1
        reachmaps[unit.id] = AH.get_reachmap(unit, {
            exclude_occupied = true,
            avoid_map = avoid_map
        })
        return reachmaps[unit.id]
    end

    ----------------------------------------------------------------------------
    -- layer 1: seal a threatened hex next to a protected unit
    ----------------------------------------------------------------------------

    local hexes = get_screen_hexes(protectees, reach, avoid_map, use_ring2)

    if hexes[1] then
        -- Do not commit more units than the ring around each protectee is worth
        local committed = {}
        for _,p in ipairs(protectees) do
            local n = 0
            for xa,ya in wesnoth.current.map:iter_adjacent(p) do
                local occupant = wesnoth.units.get(xa, ya)
                if occupant and (occupant.side == wesnoth.current.side)
                    and (occupant.moves == 0)
                then
                    n = n + 1
                end
            end
            committed[p.id] = n
        end

        local max_rating = -math.huge
        for _,hex in ipairs(hexes) do
            if (committed[hex.protectee.id] < max_per_unit) then
                -- Nearest units first, so the reach map budget is spent on the
                -- ones actually likely to be able to take the hex
                local near = {}
                for _,unit in ipairs(escorts) do
                    local dist = M.distance_between(unit.x, unit.y, hex.x, hex.y)
                    if (dist <= unit.moves) then
                        table.insert(near, { unit = unit, dist = dist })
                    end
                end
                table.sort(near, function(a, b) return a.dist < b.dist end)

                for i = 1, math.min(#near, 4) do
                    local unit = near[i].unit
                    local reachmap = reachmap_of(unit)

                    if reachmap and reachmap:get(hex.x, hex.y) then
                        local survival, defense, n_attackers =
                            survival_on(unit, hex.x, hex.y, threats)

                        -- A unit that cannot hit back is a wall, not a defender
                        local retaliation = 0
                        if (n_attackers > 0) then
                            for _,attack in ipairs(unit.attacks) do
                                if (attack.range == 'melee') then
                                    local dmg = (attack.damage or 0) * (attack.number or 0)
                                    if (dmg > retaliation) then retaliation = dmg end
                                end
                            end
                        end

                        local quality = survival * (0.5 + defense / 100.)
                            + retaliation / 200.

                        if (quality >= min_quality) then
                            local rating = hex.importance * quality
                            if (rating > max_rating) then
                                max_rating = rating
                                best_unit, best_hex = unit, { hex.x, hex.y }
                            end
                        end
                    end
                end
            end
        end

        if best_unit then return score end
    end

    ----------------------------------------------------------------------------
    -- layer 2: hold the column a little ahead of the convoy, along its route
    ----------------------------------------------------------------------------

    -- Route of whichever protectee is furthest along, so the escort forms up on
    -- the corridor the convoy is actually going to use
    local lead = protectees[1]
    for _,p in ipairs(protectees) do
        if (M.distance_between(p.x, p.y, goal_x, goal_y)
            < M.distance_between(lead.x, lead.y, goal_x, goal_y))
        then
            lead = p
        end
    end

    local route, progress = MAPS.route(lead, goal_x, goal_y, avoid_map)
    if (not route) then return 0 end

    local convoy_progress = -math.huge
    for _,p in ipairs(protectees) do
        local value = progress(p.x, p.y)
        if (value > convoy_progress) then convoy_progress = value end
    end

    ----------------------------------------------------------------------------
    -- Which side of the convoy the pressure is on. Pushing the whole escort to
    -- the front leaves the tail open whenever something is chasing the column,
    -- so part of it is held back when there is a threat behind.
    ----------------------------------------------------------------------------

    local front_threat, rear_threat = 0, 0
    for _,enemy in ipairs(enemies) do
        if enemy.valid then
            local relevant = false
            for _,p in ipairs(protectees) do
                if (M.distance_between(enemy.x, enemy.y, p.x, p.y) <= threat_radius) then
                    relevant = true
                    break
                end
            end

            if relevant then
                if (progress(enemy.x, enemy.y) > convoy_progress) then
                    front_threat = front_threat + 1
                else
                    rear_threat = rear_threat + 1
                end
            end
        end
    end

    -- Every escort counts towards manning a side, whether it has moves left or
    -- not, otherwise the split drifts as units are used up during the turn
    local all_escorts = AH.get_live_units {
        side = wesnoth.current.side,
        { "and", filter_second }
    }

    local desired_rear = 0
    if (rear_threat > 0) then
        desired_rear = math.ceil(#all_escorts * rear_threat / (rear_threat + front_threat))
        local cap = math.floor(#all_escorts / 2)
        if (desired_rear > cap) then desired_rear = cap end
    end

    local target_front = convoy_progress + vanguard_lead
    local target_rear = convoy_progress - rear_guard

    -- The units already furthest back become the rearguard, so nobody is marched
    -- past the wagons and straight back again. Assigning by "is behind the
    -- convoy" instead would break down in the usual case where most of the
    -- escort is behind it.
    local rear_set = {}
    if (desired_rear > 0) then
        local by_progress = {}
        for _,unit in ipairs(all_escorts) do table.insert(by_progress, unit) end
        table.sort(by_progress, function(a, b)
            return progress(a.x, a.y) < progress(b.x, b.y)
        end)

        for i = 1, math.min(desired_rear, #by_progress) do
            rear_set[by_progress[i].id] = true
        end
    end

    local function target_for(unit)
        if rear_set[unit.id] then return target_rear end
        return target_front
    end

    -- Reposition the unit that is furthest out of place, one per evaluation.
    -- Being behind its target is worse than being ahead of it: a straggler is
    -- doing nothing at all, while a unit that overshot is at least in the way.
    local worst_offset, chosen, chosen_target = column_slack, nil, nil
    for _,unit in ipairs(escorts) do
        local unit_target = target_for(unit)
        local offset = unit_target - progress(unit.x, unit.y)
        if (offset < 0) then offset = -offset * 0.5 end

        if (offset > worst_offset) then
            worst_offset, chosen, chosen_target = offset, unit, unit_target
        end
    end
    if (not chosen) then return 0 end
    local target = chosen_target

    -- Deliberately not going through the budget: this is a single map, and the
    -- column must not be starved by whatever layer 1 already spent
    local reachmap = reachmaps[chosen.id] or AH.get_reachmap(chosen, {
        exclude_occupied = true,
        avoid_map = avoid_map
    })

    local here = progress(chosen.x, chosen.y)
    local best_rating = -math.huge

    reachmap:iter(function(x, y)
        local offset = math.abs(progress(x, y) - target)
        local survival, defense = survival_on(chosen, x, y, threats)

        local rating = -offset * 10. + survival * 20. + defense / 10.

        if (rating > best_rating) then
            best_rating = rating
            best_unit, best_hex = chosen, { x, y }
        end
    end)

    -- Staying put is always in the reach map, so this only fires when the move
    -- genuinely improves the unit's place in the column
    if best_hex
        and (best_hex[1] == chosen.x) and (best_hex[2] == chosen.y)
        and (math.abs(here - target) <= column_slack)
    then
        best_unit, best_hex = nil, nil
    end

    if (not best_unit) then return 0 end
    return score
end

function ca_ctl_escort:execution(cfg)
    local unit, hex = best_unit, best_hex
    best_unit, best_hex = nil, nil

    -- Both branches leave attacks_left intact, so a unit told to hold a hex can
    -- still hit whatever comes adjacent to it
    if (unit.x == hex[1]) and (unit.y == hex[2]) then
        AH.checked_stopunit_moves(ai, unit)
    else
        AH.checked_move_full(ai, unit, hex[1], hex[2])
    end
end

return ca_ctl_escort
