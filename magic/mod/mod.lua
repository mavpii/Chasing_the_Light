-- mod.lua
-- Magic System — "Free Casters" modification glue.
--
-- Loaded only when the modification is enabled (see the CTL_MAGIC_MOD block in
-- _main.cfg). It adds NO new magic: the whole system — dialog, spells, TRSS
-- targeting, AI — is used exactly as the campaign uses it. All this file does is
--   * read the modification's [options] (they arrive as plain WML variables),
--   * turn ordinary units into blank free-assign casters on demand,
--   * keep the right-click menu items in sync,
--   * optionally arm AI sides with casters of their own.
--
-- Everything runs from a synced context (menu-item commands and prestart), so
-- every client builds the same caster state; the spell picker itself is opened
-- through [select_caster_skills], which defers it to an unsynced moment — see
-- core.lua's deferred_select_ids.

local _ = wesnoth.textdomain "wesnoth-ctl"

local CasterState = wesnoth.require "~add-ons/Chasing_the_Light/magic/core/state.lua"
local spell_data  = wesnoth.require "~add-ons/Chasing_the_Light/magic/spells/table.lua"

local M = {}

local AWAKEN_ITEM = "ctl_magic_mod_awaken"

-- Cached before any loop can shadow `_` (same reason as core.lua's CAST_SPELLS_LABEL).
local AWAKEN_LABEL = _"Awaken Magic"
local AWAKENED_MSG = _"Magic Awakened!"
local FULL_MSG     = _"No more casters"

---------------------------------------------------------------------------
-- Modification options
-- Each [options] entry becomes a WML variable named after its id, inserted
-- straight into the scenario, so it is readable from prestart onwards. Every
-- read falls back to a default, so the system still works if a variable is
-- missing (an old save, or the mod driven by hand from a scenario).
---------------------------------------------------------------------------

local function num_opt(id, default, lo, hi)
    local v = tonumber(wml.variables[id])
    if not v then return default end
    return math.max(lo, math.min(hi, math.floor(v)))
end

local function bool_opt(id, default)
    local v = wml.variables[id]
    if v == nil or v == "" then return default end
    return v == true or v == "yes"
end

local function str_opt(id, default)
    local v = wml.variables[id]
    if v == nil or v == "" then return default end
    return tostring(v)
end

-- "Casters per side" is a picker: 1..10 or "unlimited". A slider could not do it
-- — labelling its top stop the way the built-in "Number of Turns" slider does
-- needs maximum_value_label, which is a GUI2 widget key the custom-options panel
-- never passes on. math.huge stands in for "unlimited" so every caller can just
-- compare against that.
local function limit_opt()
    local v = str_opt("ctl_magic_mod_limit", "3")
    if v == "unlimited" then return math.huge end
    return math.max(1, math.floor(tonumber(v) or 3))
end

function M.settings()
    return {
        slots        = num_opt("ctl_magic_mod_slots",  3, 1, 8),
        casts        = num_opt("ctl_magic_mod_casts",  1, 1, 4),
        who          = str_opt("ctl_magic_mod_who",    "any"),     -- "any" | "leaders"
        -- Casters per side: a number, or the literal "unlimited" from the option's
        -- last entry.
        limit        = limit_opt(),
        costs        = str_opt("ctl_magic_mod_costs",  "free"),    -- "free" | "normal"
        awaken_xp    = num_opt("ctl_magic_mod_xp",     40, 0, 200),
        allow_change = bool_opt("ctl_magic_mod_change", true),
        levels       = bool_opt("ctl_magic_mod_levels", true),
        ai           = bool_opt("ctl_magic_mod_ai",     true),
    }
end

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------

-- Unit name for dialog titles. Falls back to the unit type's name, so unnamed
-- units (monsters, most non-leader recruits in some eras) don't produce a title
-- like "Cast 's Spells".
local function display_name(u)
    local n = tostring(u.name or "")
    if n ~= "" then return n end
    local ut = wesnoth.unit_types[u.type]
    return ut and tostring(ut.name) or tostring(u.type)
end

local function eligible(u, s)
    if not u then return false end
    if s.who == "leaders" and not u.canrecruit then return false end
    return true
end

-- Caster state is keyed by unit id, and the WML side of the system builds
-- variable NAMES out of that id -- polymorph stores the original unit in
-- "pre_polymorphed_caster_<id>", and $-substitution stops at the first character
-- that cannot appear in a variable name. Scenario-authored casters (Haralin,
-- Mage_1) are fine; units that were never given an id are not, and in a
-- multiplayer game most units are exactly that. Give those a safe one, derived
-- from the engine's own unique number so every client computes the same id.
local function ensure_id(u)
    local id = tostring(u.id or "")
    if id ~= "" then return id end
    local safe = "ctl_caster_" .. tostring(u.underlying_id)
    wml.fire("modify_unit", { wml.tag.filter{ x = u.x, y = u.y }, id = safe })
    return safe
end

-- Live count of the side's casters (any caster, including ones a scenario
-- assigned). Counting units rather than a stored tally means a fallen caster
-- frees its place again.
local function caster_count(side)
    local n = 0
    for _, u in ipairs(wesnoth.units.find_on_map{ side = side }) do
        if CasterState.exists(u.id) then n = n + 1 end
    end
    return n
end

-- Takes a hex, not a unit: the callers below fire events that can replace the
-- unit object, which leaves an old proxy dangling ("unit not found" on index).
local function floating(x, y, text, color)
    wml.fire("floating_text", {
        x = x, y = y,
        text = "<span color='" .. color .. "'>" .. tostring(text) .. "</span>",
    })
end

-- The caster dialog shows one of two descriptions: the first tells the player to
-- pick spells, the second is for a caster that already has them. The swap
-- happens in [magic_mod_refresh_description] once a selection is committed —
-- otherwise a fully equipped caster would still be told to choose its spells.
local function pick_description(name, slots)
    return string.format(tostring(
        _"%s has awakened to magic. Choose %d spells, then double-click %s (or use its right-click menu) to cast them."),
        name, slots, name)
end

local function ready_description(name, allow_change)
    if allow_change then
        return string.format(tostring(
            _"%s's magic is awake. Double-click %s (or use its right-click menu) to cast a spell, or press Change Spells to pick a different set."),
            name, name)
    end
    return string.format(tostring(
        _"%s's magic is awake. Double-click %s (or use its right-click menu) to cast a spell."),
        name, name)
end

-- Returns { spell_id, sub1, sub2, ... } so unlocking a multi-skill (Summon,
-- Bend, Polymorph) also unlocks the subskills that are the actually castable ids.
local function with_subskills(spell_id)
    local out = { spell_id }
    for _, s in pairs(spell_data.skill_set) do
        if type(s) == "table" and s.id == spell_id and s.subskills then
            for _, sub in pairs(s.subskills) do
                if type(sub) == "table" and sub.id then out[#out + 1] = sub.id end
            end
        end
    end
    return out
end

---------------------------------------------------------------------------
-- Building a caster
---------------------------------------------------------------------------

-- Turns a unit into a caster configured from the modification's settings.
--   opts.spells — ordered list of spell ids to start with (AI casters). When
--                 omitted the caster starts blank in free-assign mode, i.e. the
--                 player picks all `slots` spells from the full catalogue.
function M.make_caster(u, s, opts)
    opts = opts or {}
    local name = display_name(u)

    local cfg = {
        wml.tag.filter{ x = u.x, y = u.y },
        title_select = tostring(_"Choose Spells") .. " — " .. name,
        title_cast   = tostring(_"Cast Spells")   .. " — " .. name,
    }

    if opts.spells then
        -- Fixed loadout: one spell per group, already unlocked and equipped.
        local unlocked = {}
        for i, spell_id in ipairs(opts.spells) do
            cfg["spell_group_" .. i] = spell_id
            for _, id in ipairs(with_subskills(spell_id)) do unlocked[#unlocked + 1] = id end
        end
        cfg.unlocked_spells = table.concat(unlocked, ",")
        cfg.equipped_spells = table.concat(opts.spells, ",")
        cfg.description     = tostring(_"This unit casts spells on its own.")
    else
        -- Blank free-assign caster: one EMPTY group per slot. The picker offers
        -- `slots` slots (free_slots below states it outright, so the count holds
        -- even before any group exists), and assign_free turns the confirmed
        -- picks into one-spell groups — from there on this is an ordinary caster.
        for i = 1, s.slots do cfg["spell_group_" .. i] = "" end
        cfg.free_assign = true
        cfg.description = pick_description(name, s.slots)
    end

    -- assign_caster fires refresh_skills, which can attach [object]s to the unit;
    -- re-fetch it afterwards so the writes below land on the live unit and not on
    -- a proxy the engine has replaced underneath us.
    local unit_id = u.id
    wml.fire("assign_caster", cfg)
    u = wesnoth.units.find_on_map{ id = unit_id }[1]
    if not u then return nil end

    local data = CasterState.load(u.id)
    if not data then return nil end

    data.free_slots      = (not opts.spells) and s.slots or nil
    -- A blank caster opens straight into the picker until a selection is
    -- confirmed, so closing the picker with Escape leaves a caster you can still
    -- equip instead of a cast window with nothing in it. magic_apply_selection
    -- clears the flag on Confirm; "Choose Later" puts it back.
    data.wait_to_select  = (not opts.spells) and "yes" or nil
    data.max_casts       = s.casts
    data.reselect_free   = s.allow_change and not opts.spells
    data.free_casting    = (s.costs == "free")
    data.levels_normally = s.levels
    -- Equipping Summon/Bend/Polymorph/Astral Arms hands over all of its
    -- subskills at once: there is no campaign here to earn them from, so
    -- without this every multi-skill would sit in the cast window showing
    -- nothing but "Locked" buttons.
    data.unlock_subskills = true
    -- The cast dialog's own "advance" button (spend 90% of max XP for +6 HP and
    -- a bigger XP bar) is the alternative to levelling up. Show only one of the
    -- two: hide it whenever the unit advances the ordinary way.
    data.advancement_disabled = s.levels
    CasterState.save(data)

    -- In "normal cost" games a fresh unit has no XP to spend, so awakening comes
    -- with a starting pool. Capped below the advancement threshold so the grant
    -- itself can never level the unit up.
    if s.costs ~= "free" and s.awaken_xp > 0 then
        u.experience = math.max(u.experience,
            math.min(u.experience + s.awaken_xp, u.max_experience - 1))
    end

    return data
end

---------------------------------------------------------------------------
-- Right-click menu
-- Rebuilt every turn: the playing side is baked into the filter when the item
-- is created, exactly like core.lua's caster_set_menu.
---------------------------------------------------------------------------

function M.refresh_menu()
    local s    = M.settings()
    local side = wml.variables["side_number"]

    local awaken_filter = { side = side }
    if s.who == "leaders" then awaken_filter.canrecruit = true end

    -- Keep the item off units that already have magic. The caster registry is the
    -- authority on that (core.lua maintains it), which also covers casters a
    -- scenario assigned itself — in the campaign, "Awaken Magic" must not appear
    -- on Haralin or Daeola, who are casters already.
    --
    -- [not] holds filter conditions DIRECTLY. Wrapping them in a nested [filter]
    -- makes it an empty [not], i.e. "not everything" — which matched no unit at
    -- all and made the whole item vanish the moment the first caster registered.
    local registered = wml.variables["caster_registry"]
    if registered and registered ~= "" then
        table.insert(awaken_filter, wml.tag["not"]{ id = registered })
    end

    wml.fire("clear_menu_item", { id = AWAKEN_ITEM })
    wml.fire("set_menu_item", {
        id          = AWAKEN_ITEM,
        image       = "misc/staff-magic-wand.png",
        description = AWAKEN_LABEL,
        -- Synced: awakening writes caster state, so it must run on every client.
        -- (The spell picker it opens is deferred to an unsynced moment instead.)
        synced      = true,
        wml.tag.filter_location{ wml.tag.filter(awaken_filter) },
        wml.tag.command{
            wml.tag.magic_mod_awaken{ x = "$x1", y = "$y1" },
            -- Same reason as the magic_sync_flush event: caster state written by
            -- a synced command sits in the undo stack until something clears it,
            -- so push it out to the other clients right away.
            wml.tag.disallow_undo{},
        },
    })
end

---------------------------------------------------------------------------
-- AI sides
---------------------------------------------------------------------------

-- Loadout pool for AI casters, in priority order. Every id here has an entry in
-- ai_profiles.lua (Summon through its subskills), which is what makes the
-- adaptive AI able to use it at all — edit that file to change how they are used.
local AI_LOADOUT = {
    "skill_disattack",    -- ranged damage
    "skill_shield",       -- defensive buff
    "skill_disheal",      -- heal an ally
    "skill_smite",        -- adjacent burst
    "skill_summon",       -- elemental bodies
    "skill_massheal",     -- aura heal
    "skill_blizzard",     -- wide area damage
    "skill_counterspell", -- suppress enemy casters
}

-- Deterministic (never random — every client must build the same loadout) but
-- varied: each side starts at a different point in the pool.
local function ai_spells(side_num, count)
    local out = {}
    for i = 1, math.min(count, #AI_LOADOUT) do
        out[i] = AI_LOADOUT[((side_num - 1) * 2 + i - 1) % #AI_LOADOUT + 1]
    end
    return out
end

function M.arm_ai_side(side_num, s)
    for _, u in ipairs(wesnoth.units.find_on_map{ side = side_num, canrecruit = true }) do
        if not CasterState.exists(u.id) then
            M.make_caster(u, s, { spells = ai_spells(side_num, s.slots) })
        end
    end

    -- Register the casting brain if the side has ANY caster, not just one we
    -- built: a scenario may have assigned one itself, and without the candidate
    -- action that caster would sit on its spells all game.
    if caster_count(side_num) == 0 then return end

    -- Autonomous casting: one candidate action for the side, the same one
    -- {CASTER_AI} registers. eval_auto/exec_auto read the acting side from
    -- wesnoth.current.side, so nothing needs to be passed through the string.
    wml.fire("modify_ai", {
        side   = side_num,
        action = "add",
        path   = "stage[main_loop].candidate_action",
        wml.tag.candidate_action{
            id        = "ctl_magic_mod_ai_" .. side_num,
            engine    = "lua",
            name      = "ctl_magic_mod_ai_" .. side_num,
            max_score = 95000,
            evaluation = 'return wesnoth.require("~add-ons/Chasing_the_Light/magic/ai/ai.lua").eval_auto()',
            execution  = 'wesnoth.require("~add-ons/Chasing_the_Light/magic/ai/ai.lua").exec_auto()',
        },
    })
end

---------------------------------------------------------------------------
-- WML actions
---------------------------------------------------------------------------

-- [magic_mod_setup] — once per scenario, from prestart.
wesnoth.wml_actions.magic_mod_setup = function(_cfg)
    M.refresh_menu()
end

-- [magic_mod_arm_ai] — fired on `start`, not prestart: a scenario places its own
-- units in ITS prestart handler, and event handlers run in registration order, so
-- at prestart the modification may still be looking at an empty map and find no
-- leader to arm. By `start` everything is on the board.
wesnoth.wml_actions.magic_mod_arm_ai = function(_cfg)
    local s = M.settings()
    if not s.ai then return end
    for i = 1, #wesnoth.sides do
        local side = wesnoth.sides[i]
        -- `controller` is the side's kind, not the per-client ownership (that is
        -- `is_local`), so every client arms the same sides. Matched loosely so a
        -- remotely-run AI ("network_ai") counts too.
        if tostring(side.controller or ""):find("ai") then
            M.arm_ai_side(side.side, s)
        end
    end
end

-- [magic_mod_menu] — rebuild the menu items for the side now playing.
wesnoth.wml_actions.magic_mod_menu = function(_cfg)
    M.refresh_menu()
end

-- [magic_mod_refresh_description] — fired on refresh_skills, which runs on every
-- client right after a selection is committed (and whenever a caster's abilities
-- are rebuilt). Swaps the "choose your spells" text for the "here is how to cast
-- them" one as soon as the caster actually has spells.
wesnoth.wml_actions.magic_mod_refresh_description = function(_cfg)
    local id = wml.variables["current_caster"]
    if not id then return end

    local data = CasterState.load(id)
    -- free_slots is what marks a caster this modification built, so a scenario's
    -- own casters (Haralin, Daeola) keep the description their script gave them
    -- even when the modification is running alongside the campaign.
    if not data or not data.free_slots then return end
    -- No spells yet (awakened, picker cancelled): keep telling the player to choose.
    if #data.equipped == 0 then return end

    local u = wesnoth.units.find_on_map{ id = id }[1]
        or wesnoth.units.find_on_recall{ id = id }[1]
    if not u then return end

    local desc = ready_description(display_name(u), M.settings().allow_change)
    if tostring(data.description or "") ~= desc then
        data.description = desc
        CasterState.save(data)
    end
end

-- [magic_mod_awaken] x,y — make the unit on that hex a caster and open the picker.
wesnoth.wml_actions.magic_mod_awaken = function(cfg)
    local x, y = tonumber(cfg.x), tonumber(cfg.y)
    if not (x and y) then return end
    local u = wesnoth.units.get(x, y)
    if not u then return end

    local s = M.settings()
    if u.side ~= wesnoth.current.side then return end
    if CasterState.exists(u.id) then return end
    if not eligible(u, s) then return end

    -- Must happen before any caster state is written: the state is keyed by id.
    local had_id = tostring(u.id or "") ~= ""
    ensure_id(u)
    if not had_id then
        u = wesnoth.units.get(x, y)   -- [modify_unit] may have replaced the unit
        if not u then return end
    end

    if s.limit ~= math.huge and caster_count(u.side) >= s.limit then
        floating(x, y, FULL_MSG, "#d85a5a")
        return
    end

    local unit_id = u.id
    if not M.make_caster(u, s) then return end

    wesnoth.audio.play("heal.wav")
    floating(x, y, AWAKENED_MSG, "#a308b8")
    M.refresh_menu()

    -- Deferred to the next mouse move by [select_caster_skills], because the
    -- picker must open from an unsynced context (this command is synced).
    wml.fire("select_caster_skills", { wml.tag.filter{ id = unit_id } })
end

return M
