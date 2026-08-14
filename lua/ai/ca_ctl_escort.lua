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

-- Damage profiles are per turn, since time of day changes between turns
local profile_cache = { turn = -1, profiles = {} }

--------------------------------------------------------------------------------
-- damage estimation
--------------------------------------------------------------------------------

-- Per-attack damage of @enemy against @unit, before terrain is taken into
-- account. Returns an array of { damage = , magical = , marksman = }.
local function threat_profile(enemy, unit)
    if (profile_cache.turn ~= wesnoth.current.turn) then
        profile_cache.turn, profile_cache.profiles = wesnoth.current.turn, {}
    end

    local key = enemy.id .. '|' .. unit.id
    local cached = profile_cache.profiles[key]
    if cached then return cached end

    local tod = AH.get_unit_time_of_day_bonus(
        enemy.alignment,
        wesnoth.schedule.get_illumination(enemy).lawful_bonus
    )

    local profile = {}
    for _,attack in ipairs(enemy.attacks) do
        local magical, marksman = false, false
        for _,sp in ipairs(attack.specials) do
            if (sp[1] == 'chance_to_hit') then
                if (sp[2].id == 'magical') then magical = true end
                if (sp[2].id == 'marksman') then marksman = true end
            end
        end

        -- resistance_against() returns the UI-sense resistance (positive means
        -- resistant), so the damage multiplier is (100 - resistance)/100
        local resistance = unit:resistance_against(attack.type)
        table.insert(profile, {
            damage = (attack.damage or 0) * (attack.number or 0)
                * (100 - resistance) / 100. * tod,
            magical = magical,
            marksman = marksman
        })
    end

    profile_cache.profiles[key] = profile
    return profile
end

-- Expected damage of one attack round, given the defense the escort has on the
-- hex it would be standing on. @defense is unit:defense_on(), UI sense.
local function expected_damage(profile, defense)
    local base_hit = 100 - defense

    local worst = 0
    for _,a in ipairs(profile) do
        local hit = base_hit
        if a.magical then
            hit = 70
        elseif a.marksman and (hit < 60) then
            hit = 60
        end

        local dmg = a.damage * hit / 100.
        if (dmg > worst) then worst = dmg end
    end

    return worst
end

-- Enemies still alive that can attack the hex. The threat map is built once per
-- turn, so some of the units in it may have been killed since; their proxies
-- must not be touched.
local function live_attackers(threats, x, y)
    local attackers = {}
    for _,enemy in ipairs(threats:get(x, y) or {}) do
        if enemy.valid then table.insert(attackers, enemy) end
    end
    return attackers
end

-- Fraction of @unit expected to still be standing on (@x,@y) at the start of our
-- next turn, clamped to (0, 1]. Also returns the defense on that hex.
local function survival_on(unit, x, y, threats)
    local defense = unit:defense_on(wesnoth.current.map[{ x, y }])
    local attackers = live_attackers(threats, x, y)

    -- No more enemies can hit at once than there are hexes to hit from
    local free_slots = 0
    for xa,ya in wesnoth.current.map:iter_adjacent({ x, y }) do
        local occupant = wesnoth.units.get(xa, ya)
        if (not occupant) or (occupant.side ~= wesnoth.current.side) then
            free_slots = free_slots + 1
        end
    end

    local damages = {}
    for _,enemy in ipairs(attackers) do
        table.insert(damages, expected_damage(threat_profile(enemy, unit), defense))
    end
    table.sort(damages, function(a, b) return a > b end)

    local incoming = 0
    for i = 1, math.min(#damages, free_slots) do
        incoming = incoming + damages[i]
    end

    local survival = (unit.hitpoints - incoming) / unit.max_hitpoints
    if (survival < 0.05) then survival = 0.05 end
    if (survival > 1.) then survival = 1. end

    return survival, defense, #attackers
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

    local reach, threats = MAPS.threat()
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
    local target = convoy_progress + vanguard_lead

    -- Reposition the unit that is furthest out of place, one per evaluation.
    -- Being behind is worse than being ahead: a straggler is doing nothing at
    -- all, while a unit that overshot is at least in front of the convoy.
    local worst_offset, chosen = column_slack, nil
    for _,unit in ipairs(escorts) do
        local offset = target - progress(unit.x, unit.y)
        if (offset < 0) then offset = -offset * 0.5 end

        if (offset > worst_offset) then
            worst_offset, chosen = offset, unit
        end
    end
    if (not chosen) then return 0 end

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
