-- ai.lua
-- Magic System — Adaptive AI casting (Lua candidate action).
--
-- Lets an AI side use its casters' spells as part of its normal decision loop.
-- Autonomous mode ({CASTER_AI side score}): each caster looks at ITS OWN equipped
-- spells and, via the editable profiles in ai_profiles.lua, picks the most useful
-- one for the current board. Explicit mode ({CASTER_AI_SPELL...}) forces one spell.
-- The cast itself goes through the [cast_spell] / [cast_targeted_spell] WML tags.
--
-- Casts are CHARGED by default (xp/hp/gold/attack) — the AI never picks a spell it
-- cannot afford. Pass free=true in a hand-written candidate action to cast for free.
--
-- Full-path requires so this works no matter how it is loaded (it is required
-- lazily from the candidate-action eval/exec strings).

local CasterState = wesnoth.require "~add-ons/Chasing_the_Light/magic/state.lua"
local CasterOps   = wesnoth.require "~add-ons/Chasing_the_Light/magic/ops.lua"
local spell_data  = wesnoth.require "~add-ons/Chasing_the_Light/magic/table.lua"

local M = {}

-- Editable spell catalogue (see ai_profiles.lua). Overridable at runtime via
-- M.set_profile / M.forget_profile.
M.profiles = wesnoth.require "~add-ons/Chasing_the_Light/magic/ai_profiles.lua"

function M.set_profile(id, profile) M.profiles[id] = profile end
function M.forget_profile(id)       M.profiles[id] = nil end

---------------------------------------------------------------------------
-- Cost index (id -> costs), including subskills, for affordability checks.
---------------------------------------------------------------------------
local cost = {}
do
    local function put(s)
        if type(s) == "table" and s.id then
            cost[s.id] = { xp = s.xp_cost, hp = s.hp_cost, gold = s.gold_cost, atk = s.atk_cost }
            if s.subskills then for _, sub in pairs(s.subskills) do put(sub) end end
        end
    end
    for _, s in pairs(spell_data.skill_set) do put(s) end
end

-- Parent spell id -> list of its subskill ids (summon/bend/polymorph). A caster
-- equips the PARENT, so the AI expands it to the individually-castable subskills.
local subcasts = {}
for _, s in pairs(spell_data.skill_set) do
    if type(s) == "table" and s.id and s.subskills then
        local list = {}
        for _, sub in pairs(s.subskills) do
            if type(sub) == "table" and sub.id then list[#list + 1] = sub.id end
        end
        subcasts[s.id] = list
    end
end
local function castable_ids(spell_id)
    return subcasts[spell_id] or { spell_id }
end

local function can_afford(u, id)
    local c = cost[id]
    if not c then return true end
    if c.xp   and u.experience   <  c.xp   then return false end
    if c.hp   and u.hitpoints     <= c.hp   then return false end
    if c.gold and wesnoth.sides[u.side].gold < c.gold then return false end
    if c.atk  and u.attacks_left  <  c.atk  then return false end
    return true
end

---------------------------------------------------------------------------
-- Geometry / unit helpers
---------------------------------------------------------------------------
local function same_team(a, b)
    return wesnoth.sides[a.side].team_name == wesnoth.sides[b.side].team_name
end

local function enemies_within(u, range)
    local out = {}
    for _, e in ipairs(wesnoth.units.find_on_map{}) do
        if e.id ~= u.id and not same_team(u, e)
           and wesnoth.map.distance_between(u.x, u.y, e.x, e.y) <= range then
            out[#out + 1] = e
        end
    end
    return out
end

local function allies_within(u, range, include_self)
    local out = {}
    for _, a in ipairs(wesnoth.units.find_on_map{}) do
        if same_team(u, a) and (include_self or a.id ~= u.id)
           and wesnoth.map.distance_between(u.x, u.y, a.x, a.y) <= range then
            out[#out + 1] = a
        end
    end
    return out
end

-- An empty hex adjacent to the caster, closest to the nearest enemy (for summons).
local function empty_adjacent_toward_enemy(u)
    local foes = enemies_within(u, 999)
    local nf, nd
    for _, e in ipairs(foes) do
        local d = wesnoth.map.distance_between(u.x, u.y, e.x, e.y)
        if not nf or d < nd then nf, nd = e, d end
    end
    if not nf then return nil end
    local best, bestd
    for dx = -1, 1 do for dy = -1, 1 do
        local x, y = u.x + dx, u.y + dy
        if wesnoth.map.distance_between(u.x, u.y, x, y) == 1
           and #wesnoth.units.find_on_map{ x = x, y = y } == 0 then
            local d = wesnoth.map.distance_between(x, y, nf.x, nf.y)
            if not best or d < bestd then best, bestd = { x = x, y = y }, d end
        end
    end end
    return best
end

---------------------------------------------------------------------------
-- Per-kind valuation. Each returns { util=, target=unit|hex, self=bool } or nil.
---------------------------------------------------------------------------
local KINDS = {}

KINDS.damage = function(u, p)
    local best, bu
    for _, e in ipairs(enemies_within(u, p.range or 1)) do
        local v = (p.power or 10)
        if (p.power or 0) >= e.hitpoints then v = v + 50 end          -- can finish it
        v = v + (e.max_hitpoints - e.hitpoints) * 0.2                 -- prefer wounded
        if not best or v > bu then best, bu = e, v end
    end
    if best then return { util = (p.base or 20) + bu, target = best } end
end

KINDS.aoe_self = function(u, p)
    local r = p.radius or 1
    local foes = #enemies_within(u, r)
    if foes < (p.min or 1) then return nil end
    local allies = #allies_within(u, r, false)
    local util = (p.base or 10) + (p.power or 10) * foes - (p.ally_penalty or 8) * allies
    if util <= 0 then return nil end
    return { util = util, self = true }
end

KINDS.heal_target = function(u, p)
    local best, bu
    for _, a in ipairs(allies_within(u, p.range or 1, true)) do
        local missing = a.max_hitpoints - a.hitpoints
        if missing > 0 and (not best or missing > bu) then best, bu = a, missing end
    end
    if best then return { util = (p.base or 15) + bu, target = best } end
end

KINDS.heal_self_aura = function(u, p)
    local total = 0
    for _, a in ipairs(allies_within(u, p.radius or 1, true)) do
        total = total + (a.max_hitpoints - a.hitpoints)
    end
    if total <= 0 then return nil end
    return { util = (p.base or 10) + total, self = true }
end

KINDS.buff_self = function(u, p)
    local n = #enemies_within(u, p.threat or 3)
    if n < (p.min or 1) then return nil end
    return { util = (p.base or 20) + (p.weight or 12) * n, self = true }
end

KINDS.debuff_aura = function(u, p)
    local foes = enemies_within(u, p.radius or 2)
    if #foes < (p.min or 1) then return nil end
    local util = (p.base or 15) + (p.weight or 8) * #foes
    if p.vs_casters then
        for _, e in ipairs(foes) do
            if CasterState.exists(e.id) then util = util + 40; break end
        end
    end
    return { util = util, self = true }
end

KINDS.buff_team = function(u, p)
    local allies = #allies_within(u, p.radius or 6, false)
    if allies < (p.min or 2) then return nil end
    return { util = (p.base or 10) + (p.weight or 8) * allies, self = true }
end

KINDS.summon = function(u, p)
    if #enemies_within(u, p.threat or 4) < 1 then return nil end
    local hex = empty_adjacent_toward_enemy(u)
    if not hex then return nil end
    return { util = (p.base or 15), target = hex }
end

---------------------------------------------------------------------------
-- Candidate casters: registered casters on cfg.side that can still cast.
---------------------------------------------------------------------------
local function casters_for(cfg)
    local filter = { side = cfg.side }
    if cfg.caster_id and cfg.caster_id ~= "" then filter.id = cfg.caster_id end
    local out = {}
    for _, u in ipairs(wesnoth.units.find_on_map(filter)) do
        local data = CasterState.load(u.id)
        if data and not data.spellcasting_disabled and CasterOps.can_cast(data) then
            out[#out + 1] = { unit = u, data = data }
        end
    end
    return out
end

-- Issues the chosen cast through the WML tags. Charged unless cfg.free == true.
local function do_cast(cfg, pick)
    local free = (cfg.free == true)
    local id = pick.cast or pick.spell
    if pick.self then
        wml.fire("cast_spell", {
            spell_id = id, free = free, count_cast = true,
            wml.tag.filter{ id = pick.caster.id },
        })
    else
        wml.fire("cast_targeted_spell", {
            spell_id = id, free = free, count_cast = true,
            target_x = pick.target.x, target_y = pick.target.y,
            wml.tag.filter{ id = pick.caster.id },
        })
    end
end

---------------------------------------------------------------------------
-- Autonomous mode: the caster picks the best of its own equipped spells.
---------------------------------------------------------------------------
local function choose_for(u, data)
    local best
    for _, spell_id in ipairs(data.equipped) do
        for _, cast_id in ipairs(castable_ids(spell_id)) do
            local prof = M.profiles[cast_id]
            local handler = prof and KINDS[prof.kind]
            if handler and can_afford(u, cast_id) then
                local res = handler(u, prof)
                if res and (not best or res.util > best.util) then
                    best = { caster = u, spell = spell_id, cast = cast_id,
                             util = res.util, self = res.self, target = res.target }
                end
            end
        end
    end
    return best
end

-- Best (caster, spell, target) across all of the side's ready casters. Stateless:
-- run in both eval and exec, so no cached state can go stale between them.
local function choose(cfg)
    local best
    for _, c in ipairs(casters_for(cfg)) do
        local pick = choose_for(c.unit, c.data)
        if pick and (not best or pick.util > best.util) then best = pick end
    end
    return best
end

-- IMPORTANT: the candidate-action eval/exec live in a WML <<...>> string, and the
-- WML preprocessor does NOT substitute macro parameters ({SIDE}, {SCORE}) inside
-- it. So we pass NOTHING through the string — the side comes from the AI context
-- (wesnoth.current.side, i.e. whose turn it is), and the priority is set by the
-- candidate action's max_score (a normal attribute, which does substitute). eval
-- returns a big constant that max_score caps to the configured score.
function M.eval_auto()
    local side = wesnoth.current.side
    return choose({ side = side }) and 1000000 or 0
end

function M.exec_auto()
    local pick = choose({ side = wesnoth.current.side })
    if pick then do_cast({}, pick) end
end

---------------------------------------------------------------------------
-- Explicit mode: cast one specific spell (used by CASTER_AI_SPELL macros).
-- cfg = { side, spell, range?, mode?, self?, score, caster_id?, free? }
---------------------------------------------------------------------------
local function pick_target(u, cfg)
    local best, bk
    for _, e in ipairs(enemies_within(u, cfg.range or 1)) do
        local key = (cfg.mode == "weakest")
            and -e.hitpoints
            or  -wesnoth.map.distance_between(u.x, u.y, e.x, e.y)
        if not best or key > bk then best, bk = e, key end
    end
    return best
end

local function select_explicit(cfg)
    for _, c in ipairs(casters_for(cfg)) do
        local u = c.unit
        if can_afford(u, cfg.spell) then
            if cfg.self then
                return { caster = u, spell = cfg.spell, self = true }
            else
                local t = pick_target(u, cfg)
                if t then return { caster = u, spell = cfg.spell, target = t } end
            end
        end
    end
end

-- Positional args (see the note on eval_auto for why).
function M.eval(side, spell, range, mode, score, is_self)
    local cfg = { side = side, spell = spell, range = range, mode = mode, self = is_self }
    return select_explicit(cfg) and (score or 1) or 0
end
function M.exec(side, spell, range, mode, score, is_self)
    local cfg = { side = side, spell = spell, range = range, mode = mode, self = is_self }
    local pick = select_explicit(cfg)
    if pick then do_cast(cfg, pick) end
end

return M
