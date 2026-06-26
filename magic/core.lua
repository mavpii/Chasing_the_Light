-- core.lua
-- Magic System — Entry point
-- Registers all wml_actions and input handlers.
-- This file should contain NO business logic — only thin wrappers that delegate
-- to state.lua (data), ops.lua (pure functions), and dialog.lua (UI).

local _ = wesnoth.textdomain "wesnoth-ctl"
local CAST_SPELLS_LABEL = _"Cast Spells" -- cached before any loop can shadow _

local CasterState = wesnoth.require "state.lua"
local CasterOps   = wesnoth.require "ops.lua"
local Dialog      = wesnoth.require "dialog.lua"
local spell_data  = wesnoth.require "table.lua"

Dialog.init(spell_data) -- inject spell catalogue into dialog layer

local wml_actions = wesnoth.wml_actions

-- spell id -> definition, INCLUDING subskills (skill_summon_mud, etc.), so the
-- command-cast tags can look up costs for both top-level spells and subskills.
local spell_index = (function()
    local idx = {}
    for _, s in pairs(spell_data.skill_set) do
        if type(s) == "table" and s.id then
            idx[s.id] = s
            if s.subskills then
                for _, sub in pairs(s.subskills) do
                    if type(sub) == "table" and sub.id then idx[sub.id] = sub end
                end
            end
        end
    end
    return idx
end)()

---------------------------------------------------------------------------
-- Caster registry
-- Tracks which unit IDs are currently registered as casters.
-- Lets caster_set_menu avoid scanning ALL units on the map every turn.
---------------------------------------------------------------------------

local function registry_add(unit_id)
    local reg = wml.variables["caster_registry"] or ""
    for existing in reg:gmatch("[^,]+") do
        if existing == unit_id then return end
    end
    wml.variables["caster_registry"] = reg == "" and unit_id or (reg .. "," .. unit_id)
end

local function registry_remove(unit_id)
    local ids = {}
    for id in (wml.variables["caster_registry"] or ""):gmatch("[^,]+") do
        if id ~= unit_id then table.insert(ids, id) end
    end
    wml.variables["caster_registry"] = table.concat(ids, ",")
end

local function registry_each()
    local ids = {}
    for id in (wml.variables["caster_registry"] or ""):gmatch("[^,]+") do
        table.insert(ids, id)
    end
    return ipairs(ids)
end

---------------------------------------------------------------------------
-- Helpers shared by wml_actions
---------------------------------------------------------------------------

local function require_filter(cfg, tag_name)
    return wml.get_child(cfg, "filter")
        or wml.error("[" .. tag_name .. "] missing required [filter] tag")
end

-- Splits a comma-separated id list into trimmed, non-empty ids.
-- Trimming matters: scenario macros may pass "skill_a, skill_b" with spaces.
local function split_ids(str)
    local t = {}
    for raw in (str or ""):gmatch("[^,]+") do
        local item = raw:match("^%s*(.-)%s*$")
        if item ~= "" then t[#t + 1] = item end
    end
    return t
end

-- Finds matching units both on the map and on the recall list, so casters can
-- be assigned/modified even while they are waiting on the recall list.
local function find_casters(filter)
    local units = wesnoth.units.find_on_map(filter)
    for _, u in ipairs(wesnoth.units.find_on_recall(filter)) do
        units[#units + 1] = u
    end
    return units
end

---------------------------------------------------------------------------
-- SKILL COST  (synced command — runs identically on all clients)
---------------------------------------------------------------------------

function wesnoth.custom_synced_commands.spellcasting_cost(t)
    local u = wesnoth.units.find_on_map({ id=t.id })[1]
    if not u then return end
    if t.xp_cost   then u.experience              = u.experience              - t.xp_cost   end
    if t.hp_cost   then u.hitpoints               = u.hitpoints               - t.hp_cost   end
    if t.gold_cost then wesnoth.sides[u.side].gold = wesnoth.sides[u.side].gold - t.gold_cost end
    if t.atk_cost  then u.attacks_left            = u.attacks_left            - t.atk_cost  end
    -- Multi-cast: increment the per-turn cast counter (synced so it persists in saves/replays).
    if t.casts_increment then
        local ct = tonumber(wml.variables["caster_" .. u.id .. ".casts_this_turn"]) or 0
        wml.variables["caster_" .. u.id .. ".casts_this_turn"] = ct + 1
    end
end

-- Legacy alias used by TRSS.cfg and some spells.
function spellcasting_cost(t)
    wesnoth.custom_synced_commands.spellcasting_cost(t)
end

-- Deducts a spell's catalogue costs (XP/HP/gold/attack) from a unit, the same way
-- the cast dialog does. No-op if the spell id is unknown or has no costs.
-- Used by [cast_spell]/[cast_targeted_spell].
local function apply_spell_cost(unit_id, spell_id)
    local spell = spell_index[spell_id]
    if not spell then return end
    spellcasting_cost({
        id        = unit_id,
        xp_cost   = spell.xp_cost,
        hp_cost   = spell.hp_cost,
        gold_cost = spell.gold_cost,
        atk_cost  = spell.atk_cost,
    })
end

-- Increments the per-turn cast counter directly, INDEPENDENT of cost. A free cast
-- must still count against max_casts — otherwise the adaptive AI (which casts free
-- by default) would loop forever, because can_cast() never flips to false.
local function increment_cast(unit_id)
    local k = "caster_" .. unit_id .. ".casts_this_turn"
    wml.variables[k] = (tonumber(wml.variables[k]) or 0) + 1
end

-- Synced: set current_caster on ALL clients.
-- Called from dialog.lua button click handlers via wesnoth.sync.invoke_command.
-- Must be called from inside show_dialog button clicks (not after show_dialog returns).
function wesnoth.custom_synced_commands.magic_set_caster(t)
    wml.variables["current_caster"] = t.id
end

-- Commits a spell selection on ALL clients. The chosen spells are passed as the
-- command's own parameters (t.equipped / t.wait), so the data travels inside the
-- synced packet — unlike the earlier do_command+[set_variable] hand-off, where the
-- variable set inside do_command was not visible to the fired event (equipped
-- arrived empty). Safe because the selection dialog is always opened from an
-- unsynced context (right-click menu, double-click, or the deferred RESELECT).
function wesnoth.custom_synced_commands.magic_commit(t)
    wml.variables["current_caster"] = t.id
    wesnoth.wml_actions.magic_apply_selection({ id = t.id, equipped = t.equipped, wait = t.wait })
end

-- Applies a spell-selection result to a caster, then re-applies its abilities.
-- Invoked on every client by the `magic_commit` synced command (above), which the
-- dialog's Confirm / Choose Later button handlers call via wesnoth.sync.invoke_command.
-- The chosen spells travel as command PARAMETERS (id/equipped/wait), not through a
-- WML variable — the earlier do_command+[set_variable] hand-off delivered the spells
-- empty, because the variable set inside do_command was not visible to the fired event.
-- invoke_command is safe here because the dialog is always opened from an unsynced
-- context (right-click menu, double-click, or RESELECT deferred to a mouse move).
--
-- Parameters: id, equipped (comma-list, one spell per slot in free-assign mode),
--             wait ("yes" = "Choose Later").
-- Free-assign vs. standard is decided by the caster's own free_assign flag.
wml_actions["magic_apply_selection"] = function(cfg)
    local id = cfg.id
    if not id then return end

    -- "Choose Later". NOTE: wait travels through wesnoth.sync.invoke_command, and
    -- Wesnoth coerces the WML attribute "yes" into the Lua boolean true on the way
    -- back, so the value arrives here as `true`, not the string "yes". Accept both
    -- so the flag is always set (this was silently a no-op when only "yes" matched).
    if cfg.wait == "yes" or cfg.wait == true then
        wml.variables["caster_" .. id .. ".wait_to_select_spells"] = "yes"
        return
    end

    local data = CasterState.load(id)
    if not data then return end

    local list = split_ids(cfg.equipped or "")
    -- Safety: a confirmed selection always has at least one spell (Confirm is disabled
    -- otherwise). An empty list here means something went wrong upstream — never wipe
    -- the caster's groups/equipped over it.
    if #list == 0 then return end

    if data.free_assign or data.free_unlocked then
        -- Free-assign / free-pick: each entry becomes a one-spell slot, unlocked
        -- + equipped. (In free-pick the spells are already unlocked, so the
        -- unlock step inside assign_free is just idempotent.)
        CasterOps.assign_free(data, list)
    else
        -- Standard: just replace the equipped list.
        data.equipped     = list
        data.equipped_set = {}
        for _, s in ipairs(list) do data.equipped_set[s] = true end
    end
    data.wait_to_select = nil
    CasterState.save(data)
    wml.fire("refresh_skills", { id = id })
end

---------------------------------------------------------------------------
-- ASSIGN CASTER
---------------------------------------------------------------------------

wml_actions["assign_caster"] = function(cfg)
    local units = find_casters(require_filter(cfg, "assign_caster"))
    for _, u in ipairs(units) do
        local data = CasterState.from_config(u, cfg)
        CasterState.save(data)
        registry_add(u.id)
        wml.fire("caster_set_menu")
        wml.fire("refresh_skills", { id=u.id })
        wml.fire.do_command({ wml.tag.fire_event{ raise="magic_system_add_animations" }})
    end
end

---------------------------------------------------------------------------
-- MODIFY CASTER  (updates existing caster or assigns a new one)
---------------------------------------------------------------------------

wml_actions["modify_caster"] = function(cfg)
    local units = find_casters(require_filter(cfg, "modify_caster"))
    for _, u in ipairs(units) do
        local data = CasterState.load(u.id)
        if data then
            CasterOps.apply_config(data, cfg)
            CasterState.save(data)
            wml.fire("refresh_skills", { id=u.id })
            wml.fire.do_command({ wml.tag.fire_event{ raise="magic_system_add_animations" }})
        else
            wml.fire("assign_caster", cfg)
        end
    end
end

---------------------------------------------------------------------------
-- REMOVE CASTER
---------------------------------------------------------------------------

wml_actions["remove_caster"] = function(cfg)
    local units = wesnoth.units.find_on_map(require_filter(cfg, "remove_caster"))
    for _, u in ipairs(units) do
        if CasterState.exists(u.id) then
            CasterState.delete(u.id)
            registry_remove(u.id)
            wml.fire.remove_object({ id=u.id, object_id="magic_system_animations" })
            wml.fire("clear_menu_item", { id="spellcasting_object_" .. u.id })
        end
    end
end

---------------------------------------------------------------------------
-- UNLOCK / LOCK SPELL
---------------------------------------------------------------------------

wml_actions["unlock_spell"] = function(cfg)
    if not cfg.spell_id then return end
    local units = wesnoth.units.find_on_map(require_filter(cfg, "unlock_spell"))
    for _, u in ipairs(units) do
        local data = CasterState.load(u.id)
        if data then
            for _, spell_id in ipairs(split_ids(cfg.spell_id)) do
                CasterOps.unlock(data, spell_id)
            end
            CasterState.save(data)
        end
    end
end

wml_actions["lock_spell"] = function(cfg)
    if not cfg.spell_id then return end
    local units = wesnoth.units.find_on_map(require_filter(cfg, "lock_spell"))
    for _, u in ipairs(units) do
        local data = CasterState.load(u.id)
        if data then
            for _, spell_id in ipairs(split_ids(cfg.spell_id)) do
                CasterOps.lock(data, spell_id)
            end
            CasterState.save(data)
        end
    end
end

---------------------------------------------------------------------------
-- EQUIP / UNEQUIP SPELL
---------------------------------------------------------------------------

wml_actions["equip_spell"] = function(cfg)
    if not cfg.spell_id then return end
    local units = wesnoth.units.find_on_map(require_filter(cfg, "equip_spell"))
    for _, u in ipairs(units) do
        local data = CasterState.load(u.id)
        if data then
            for _, spell_id in ipairs(split_ids(cfg.spell_id)) do
                CasterOps.equip(data, spell_id)
            end
            CasterState.save(data)
            wml.fire("refresh_skills", { id=u.id })
        end
    end
end

wml_actions["unequip_spell"] = function(cfg)
    if not cfg.spell_id then return end
    local units = wesnoth.units.find_on_map(require_filter(cfg, "unequip_spell"))
    for _, u in ipairs(units) do
        local data = CasterState.load(u.id)
        if data then
            for _, spell_id in ipairs(split_ids(cfg.spell_id)) do
                CasterOps.unequip(data, spell_id)
            end
            CasterState.save(data)
            wml.fire("refresh_skills", { id=u.id })
        end
    end
end

---------------------------------------------------------------------------
-- FIND EQUIPPED / UNLOCKED SPELL  (query → WML variable)
-- Both write to "equipped_spell_found" for backwards compatibility with spells.cfg.
---------------------------------------------------------------------------

wml_actions["find_equipped_spell"] = function(cfg)
    wml.variables["equipped_spell_found"] = false
    if not cfg.spell_id then return end
    local units = wesnoth.units.find_on_map(require_filter(cfg, "find_equipped_spell"))
    for _, u in ipairs(units) do
        local data = CasterState.load(u.id)
        if data and CasterOps.is_equipped(data, cfg.spell_id) then
            wml.variables["equipped_spell_found"] = true
            return
        end
    end
end

wml_actions["find_unlocked_spell"] = function(cfg)
    wml.variables["equipped_spell_found"] = false
    if not cfg.spell_id then return end
    local units = wesnoth.units.find_on_map(require_filter(cfg, "find_unlocked_spell"))
    for _, u in ipairs(units) do
        local data = CasterState.load(u.id)
        if data and CasterOps.is_unlocked(data, cfg.spell_id) then
            wml.variables["equipped_spell_found"] = true
            return
        end
    end
end

---------------------------------------------------------------------------
-- CASTER STATUS / ADVANCE
---------------------------------------------------------------------------

wml_actions["caster_status"] = function(cfg)
    local units = wesnoth.units.find_on_map(require_filter(cfg, "caster_status"))
    for _, u in ipairs(units) do
        local data = CasterState.load(u.id)
        if data then
            CasterOps.set_spellcasting(data, cfg.spellcasting_allowed == true)
            CasterState.save(data)
        end
    end
    wml.fire("caster_set_menu")
end

wml_actions["caster_advance"] = function(cfg)
    local units = wesnoth.units.find_on_map(require_filter(cfg, "caster_advance"))
    for _, u in ipairs(units) do
        local data = CasterState.load(u.id)
        if data then
            CasterOps.set_advancement(data, cfg.advancement_allowed == true)
            CasterState.save(data)
        end
    end
end

---------------------------------------------------------------------------
-- CASTER RESELECT
-- Enables/disables the "Change Spells" button inside the cast dialog.
-- Use: [caster_reselect] reselect_allowed=yes [filter]...[/filter] [/caster_reselect]
---------------------------------------------------------------------------

wml_actions["caster_reselect"] = function(cfg)
    local units = wesnoth.units.find_on_map(require_filter(cfg, "caster_reselect"))
    for _, u in ipairs(units) do
        local data = CasterState.load(u.id)
        if data then
            CasterOps.set_reselect(data, cfg.reselect_allowed == true)
            CasterState.save(data)
        end
    end
end

---------------------------------------------------------------------------
-- CASTER MAX CASTS
-- Sets how many spells the caster may cast per turn (default 1).
-- Use: [caster_max_casts] max_casts=2 [filter]...[/filter] [/caster_max_casts]
---------------------------------------------------------------------------

wml_actions["caster_max_casts"] = function(cfg)
    local units = wesnoth.units.find_on_map(require_filter(cfg, "caster_max_casts"))
    for _, u in ipairs(units) do
        local data = CasterState.load(u.id)
        if data then
            CasterOps.set_max_casts(data, cfg.max_casts or 1)
            CasterState.save(data)
        end
    end
end

---------------------------------------------------------------------------
-- CASTER RESTORE CASTS
-- Gives back casts already spent this turn -- e.g. after a scripted retry,
-- or to refund a cancelled targeted spell. With no `count`, fully restores
-- (back to 0 spent). With `count`, restores only that many.
-- Use: [caster_restore_casts] count=1 [filter]...[/filter] [/caster_restore_casts]
---------------------------------------------------------------------------

wml_actions["caster_restore_casts"] = function(cfg)
    local units = wesnoth.units.find_on_map(require_filter(cfg, "caster_restore_casts"))
    for _, u in ipairs(units) do
        local data = CasterState.load(u.id)
        if data then
            CasterOps.restore_casts(data, cfg.count)
            CasterState.save(data)
        end
    end
end

---------------------------------------------------------------------------
-- CASTER FREE ASSIGN
-- Enables/disables free-assign mode: the spell selection dialog lets the
-- player pick ANY spell into ANY slot through a picker grid.
-- Use: [caster_free_assign] free_assign_allowed=yes [filter]...[/filter] [/caster_free_assign]
---------------------------------------------------------------------------

wml_actions["caster_free_assign"] = function(cfg)
    local units = wesnoth.units.find_on_map(require_filter(cfg, "caster_free_assign"))
    for _, u in ipairs(units) do
        local data = CasterState.load(u.id)
        if data then
            CasterOps.set_free_assign(data, cfg.free_assign_allowed == true)
            -- Leaving ALL free modes restores the original per-group pools that
            -- assign_free replaced with one-spell slots.
            local restored = false
            if not data.free_assign and not data.free_unlocked then
                restored = CasterOps.restore_groups(data)
            end
            CasterState.save(data)
            if restored then wml.fire("refresh_skills", { id=u.id }) end
        end
    end
end

---------------------------------------------------------------------------
-- CASTER FREE UNLOCKED (free-pick)
-- Enables/disables free-pick mode: same picker UI as free-assign, but the
-- grid is restricted to the caster's UNLOCKED spells only.
-- Use: [caster_free_unlocked] free_unlocked_allowed=yes [filter]...[/filter] [/caster_free_unlocked]
---------------------------------------------------------------------------

wml_actions["caster_free_unlocked"] = function(cfg)
    local units = wesnoth.units.find_on_map(require_filter(cfg, "caster_free_unlocked"))
    for _, u in ipairs(units) do
        local data = CasterState.load(u.id)
        if data then
            CasterOps.set_free_unlocked(data, cfg.free_unlocked_allowed == true)
            -- Leaving ALL free modes restores the original per-group pools that
            -- assign_free replaced with one-spell slots.
            local restored = false
            if not data.free_assign and not data.free_unlocked then
                restored = CasterOps.restore_groups(data)
            end
            CasterState.save(data)
            if restored then wml.fire("refresh_skills", { id=u.id }) end
        end
    end
end

---------------------------------------------------------------------------
-- REFRESH SKILLS
-- Sets current_caster and fires the refresh_skills WML event (defined in spells.cfg).
---------------------------------------------------------------------------

wml_actions["refresh_skills"] = function(cfg)
    wml.variables["current_caster"] = cfg.id
    wesnoth.game_events.fire("refresh_skills")
end

---------------------------------------------------------------------------
-- REFRESH CASTER ANIMATIONS
---------------------------------------------------------------------------

wml_actions["refresh_caster_animations"] = function(cfg)
    local units = wesnoth.units.find_on_map(require_filter(cfg, "refresh_caster_animations"))
    for _, u in ipairs(units) do
        if CasterState.exists(u.id) then
            wml.fire.remove_object({ id=u.id, object_id="magic_system_animations" })
            wml.variables["current_caster"] = u.id
            wml.fire.do_command({ wml.tag.fire_event{ raise="magic_system_add_animations" }})
        end
    end
end

---------------------------------------------------------------------------
-- CASTER SET MENU
-- Uses the registry instead of scanning all units.
---------------------------------------------------------------------------

wml_actions["caster_set_menu"] = function(_cfg)
    for _, unit_id in registry_each() do
        wml.fire("clear_menu_item", { id="spellcasting_object_" .. unit_id })

        local u = wesnoth.units.find_on_map{ id=unit_id }[1]
        if u and wml.variables["side_number"] == u.side then
            wml.fire("set_menu_item", {
                id          = "spellcasting_object_" .. unit_id,
                image       = "misc/staff-magic-wand.png",
                description = CAST_SPELLS_LABEL,
                synced      = false,
                wml.tag.filter_location{
                    wml.tag.filter{ id=unit_id, side=wml.variables["side_number"] }
                },
                wml.tag.command{
                    wml.tag.show_caster_skills{
                        wml.tag.filter{ id=unit_id }
                    }
                },
                wml.tag.show_if{
                    wml.tag.variable{
                        name       = "caster_" .. unit_id .. ".utils_spellcasting_allowed",
                        not_equals = "disabled",
                    }
                },
            })
        end
    end
end

---------------------------------------------------------------------------
-- SELECT / SHOW CASTER SKILLS
---------------------------------------------------------------------------

local function open_for_unit(u, force_select)
    if wml.variables["is_badly_timed"] then return end
    local data = CasterState.load(u.id)
    if not data or data.spellcasting_disabled then return end

    wml.variables["current_caster"] = u.id

    local selecting = force_select or (data.wait_to_select == "yes")
    local reselect = Dialog.open_dialog(u, data, selecting)

    -- Reselect upgrade: cast dialog requested switching to spell selection mode.
    if reselect then
        local fresh_data = CasterState.load(u.id)
        if fresh_data then
            Dialog.open_dialog(u, fresh_data, true)
        end
    end
end

-- Opening the selection dialog must happen from an UNSYNCED context — that's why
-- the right-click menu (registered synced=false) works. When [select_caster_skills]
-- / RESELECT_SKILLS is fired from a synced game event (e.g. moveto, mid-move),
-- open_dialog's evaluate_single + do_command commit can't run and the chosen spells
-- are silently dropped. So defer the open to the next mouse move — an unsynced
-- moment — the same approach RESELECT_SKILLS_AFTER_OBJECTIVES already relies on.
local deferred_select_ids = {}

wml_actions["select_caster_skills"] = function(cfg)
    local units = wesnoth.units.find_on_map(require_filter(cfg, "select_caster_skills"))
    if #units == 0 then return end

    local schedule = (#deferred_select_ids == 0) -- only install the handler once
    for _, u in ipairs(units) do
        deferred_select_ids[#deferred_select_ids + 1] = u.id
    end
    if not schedule then return end

    local prev = wesnoth.game_events.on_mouse_move
    wesnoth.game_events.on_mouse_move = function(x, y)
        wesnoth.game_events.on_mouse_move = prev -- one-shot: restore previous handler
        local ids = deferred_select_ids
        deferred_select_ids = {}
        wesnoth.audio.play("miss-2.ogg")
        for _, id in ipairs(ids) do
            local u = wesnoth.units.find_on_map{ id = id }[1]
            if u then open_for_unit(u, true) end
        end
        if prev then return prev(x, y) end
    end
end

wml_actions["show_caster_skills"] = function(cfg)
    wesnoth.audio.play("miss-2.ogg")
    local units = wesnoth.units.find_on_map(require_filter(cfg, "show_caster_skills"))
    for _, u in ipairs(units) do open_for_unit(u, false) end
end

---------------------------------------------------------------------------
-- COMMAND-DRIVEN CASTING
-- Cast a spell from WML (cutscenes, AI, scripted events) without the dialog.
--
-- [cast_spell]    — fires a normal (self/automatic) spell's event directly.
-- [cast_targeted_spell] — fires a TRSS spell's "_cast" effect on a chosen hex,
--                         skipping the interactive click-to-target step.
--
-- Both deduct the spell's catalogue costs by default; add free=yes to skip.
-- Optional gates: require_unlocked=yes / require_equipped=yes (skip if the caster
-- hasn't unlocked/equipped the spell). count_cast=yes also spends a per-turn cast.
---------------------------------------------------------------------------

-- Returns true when the caster passes the optional require_unlocked/require_equipped
-- gates in cfg (data may be nil for a non-registered unit, which fails any gate).
local function cast_gate_ok(cfg, data, spell_id)
    if cfg.require_unlocked and not (data and CasterOps.is_unlocked(data, spell_id)) then
        return false
    end
    if cfg.require_equipped and not (data and CasterOps.is_equipped(data, spell_id)) then
        return false
    end
    return true
end

wml_actions["cast_spell"] = function(cfg)
    local spell_id = cfg.spell_id or wml.error("[cast_spell] requires spell_id=")
    local units = wesnoth.units.find_on_map(require_filter(cfg, "cast_spell"))
    for _, u in ipairs(units) do
        local data = CasterState.load(u.id)
        if cast_gate_ok(cfg, data, spell_id) then
            if not cfg.free then apply_spell_cost(u.id, spell_id) end
            if cfg.count_cast then increment_cast(u.id) end
            wml.variables["current_caster"] = u.id
            wesnoth.game_events.fire(spell_id)
        end
    end
end

wml_actions["cast_targeted_spell"] = function(cfg)
    local spell_id = cfg.spell_id or wml.error("[cast_targeted_spell] requires spell_id=")

    -- Target hex: explicit target_x/target_y, or the first unit matching a [target] filter.
    local tx, ty = tonumber(cfg.target_x), tonumber(cfg.target_y)
    if not (tx and ty) then
        local tf = wml.get_child(cfg, "target")
        local tu = tf and wesnoth.units.find_on_map(tf)[1]
        if tu then tx, ty = tu.x, tu.y end
    end
    if not (tx and ty) then
        wml.error("[cast_targeted_spell] requires target_x/target_y or a [target] filter")
    end

    -- The effect lives in the "<spell>_cast" event (override with cast_event=).
    local cast_event = cfg.cast_event or (spell_id .. "_cast")

    local units = wesnoth.units.find_on_map(require_filter(cfg, "cast_targeted_spell"))
    for _, u in ipairs(units) do
        local data = CasterState.load(u.id)
        if cast_gate_ok(cfg, data, spell_id) then
            if not cfg.free then apply_spell_cost(u.id, spell_id) end
            if cfg.count_cast then increment_cast(u.id) end
            -- Recreate the variables the TRSS click-handler would have set.
            wml.variables["current_caster"]        = u.id
            wml.variables["unit_to_modify_x"]      = u.x
            wml.variables["unit_to_modify_y"]      = u.y
            wml.variables["unit_to_cast_on_x"]     = tx
            wml.variables["unit_to_cast_on_y"]     = ty
            wml.variables["distance_between_units"] = wesnoth.map.distance_between(u.x, u.y, tx, ty) * 72
            wesnoth.game_events.fire(cast_event)
            wesnoth.game_events.fire(cast_event .. "_post")
        end
    end
end

---------------------------------------------------------------------------
-- DOUBLE-CLICK DETECTION
-- Uses wesnoth.ms_since_init() (real wall-clock milliseconds) instead of
-- os.clock() which measured CPU time and misbehaved on slow/paused systems.
---------------------------------------------------------------------------

local last_click_ms  = 0
local DOUBLE_CLICK_MS = 250

register_mouse_handler(function(x, y)
    local clicked = wesnoth.units.find_on_map{ x=x, y=y }[1]
    if not clicked then return end
    if not CasterState.exists(clicked.id) then return end
    if wml.variables["is_badly_timed"] then return end

    wml.variables["current_caster"] = clicked.id

    local now = wesnoth.ms_since_init()
    if now - last_click_ms < DOUBLE_CLICK_MS then
        last_click_ms = 0 -- prevent triple-click re-trigger
        wesnoth.audio.play("miss-2.ogg")
        open_for_unit(clicked, false)
    else
        last_click_ms = now
    end
end)

---------------------------------------------------------------------------
-- MOUSEMOVE LISTENER  (used by RESELECT_SKILLS_AFTER_OBJECTIVES macro)
---------------------------------------------------------------------------

function wml_actions.listen_for_mousemove(_cfg)
    wesnoth.game_events.on_mouse_move = function(x, y)
        wesnoth.game_events.fire("mousemove_synced", x, y)
        wesnoth.game_events.on_mouse_move = nil -- trigger once only
    end
end

---------------------------------------------------------------------------
-- TRSS click handler passthrough (used by TRSS.cfg adjacent spells)
---------------------------------------------------------------------------

function wesnoth.custom_synced_commands.on_click_spell_event(t)
    _G["on_click_spell_event" .. t.type](t)
end
