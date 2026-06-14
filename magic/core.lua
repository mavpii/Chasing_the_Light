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

-- Synced: set current_caster on ALL clients.
-- Called from dialog.lua button click handlers via wesnoth.sync.invoke_command.
-- Must be called from inside show_dialog button clicks (not after show_dialog returns).
function wesnoth.custom_synced_commands.magic_set_caster(t)
    wml.variables["current_caster"] = t.id
end

-- Synced: write equipped spells + refresh skill abilities on ALL clients.
-- Called from dialog.lua confirm/wait button clicks via wesnoth.sync.invoke_command.
-- Must be called from inside show_dialog button clicks (not after show_dialog returns).
function wesnoth.custom_synced_commands.magic_sync_equipped(t)
    if t.wait == "yes" then
        -- "Choose Later": only set the wait flag, don't touch spell_equipped.
        wml.variables["caster_" .. t.caster_id .. ".wait_to_select_spells"] = "yes"
    else
        -- "Confirm": update equipped list and clear wait flag.
        wml.variables["caster_" .. t.caster_id .. ".spell_equipped"] =
            (t.equipped ~= "") and t.equipped or nil
        wml.variables["caster_" .. t.caster_id .. ".wait_to_select_spells"] = nil
        wml.fire("refresh_skills", { id = t.caster_id })
    end
end

---------------------------------------------------------------------------
-- ASSIGN CASTER
---------------------------------------------------------------------------

wml_actions["assign_caster"] = function(cfg)
    local units = wesnoth.units.find(require_filter(cfg, "assign_caster"))
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
    local units = wesnoth.units.find(require_filter(cfg, "modify_caster"))
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
    local units = wesnoth.units.find(require_filter(cfg, "remove_caster"))
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
    local units = wesnoth.units.find(require_filter(cfg, "unlock_spell"))
    for _, u in ipairs(units) do
        local data = CasterState.load(u.id)
        if data then
            for spell_id in cfg.spell_id:gmatch("[^,]+") do
                CasterOps.unlock(data, spell_id)
            end
            CasterState.save(data)
        end
    end
end

wml_actions["lock_spell"] = function(cfg)
    if not cfg.spell_id then return end
    local units = wesnoth.units.find(require_filter(cfg, "lock_spell"))
    for _, u in ipairs(units) do
        local data = CasterState.load(u.id)
        if data then
            for spell_id in cfg.spell_id:gmatch("[^,]+") do
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
    local units = wesnoth.units.find(require_filter(cfg, "equip_spell"))
    for _, u in ipairs(units) do
        local data = CasterState.load(u.id)
        if data then
            for spell_id in cfg.spell_id:gmatch("[^,]+") do
                CasterOps.equip(data, spell_id)
            end
            CasterState.save(data)
            wml.fire("refresh_skills", { id=u.id })
        end
    end
end

wml_actions["unequip_spell"] = function(cfg)
    if not cfg.spell_id then return end
    local units = wesnoth.units.find(require_filter(cfg, "unequip_spell"))
    for _, u in ipairs(units) do
        local data = CasterState.load(u.id)
        if data then
            for spell_id in cfg.spell_id:gmatch("[^,]+") do
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
    local units = wesnoth.units.find(require_filter(cfg, "find_equipped_spell"))
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
    local units = wesnoth.units.find(require_filter(cfg, "find_unlocked_spell"))
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
    local units = wesnoth.units.find(require_filter(cfg, "caster_status"))
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
    local units = wesnoth.units.find(require_filter(cfg, "caster_advance"))
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
    local units = wesnoth.units.find(require_filter(cfg, "caster_reselect"))
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
    local units = wesnoth.units.find(require_filter(cfg, "caster_max_casts"))
    for _, u in ipairs(units) do
        local data = CasterState.load(u.id)
        if data then
            CasterOps.set_max_casts(data, cfg.max_casts or 1)
            CasterState.save(data)
        end
    end
end

---------------------------------------------------------------------------
-- REFRESH SKILLS
-- Sets current_caster and fires the refresh_skills WML event (defined in spells.cfg).
---------------------------------------------------------------------------

wml_actions["refresh_skills"] = function(cfg)
    wml.variables["current_caster"] = cfg.id
    wml.variables["caster_" .. cfg.id .. ".spellcasted_this_turn"] = nil
    wesnoth.game_events.fire("refresh_skills")
end

---------------------------------------------------------------------------
-- REFRESH CASTER ANIMATIONS
---------------------------------------------------------------------------

wml_actions["refresh_caster_animations"] = function(cfg)
    local units = wesnoth.units.find(require_filter(cfg, "refresh_caster_animations"))
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
    wml.variables["caster_" .. u.id .. ".spellcasted_this_turn"] = nil

    -- Reselect upgrade: cast dialog requested switching to spell selection mode.
    if reselect then
        local fresh_data = CasterState.load(u.id)
        if fresh_data then
            Dialog.open_dialog(u, fresh_data, true)
        end
    end
end

wml_actions["select_caster_skills"] = function(cfg)
    wesnoth.audio.play("miss-2.ogg")
    local units = wesnoth.units.find(require_filter(cfg, "select_caster_skills"))
    for _, u in ipairs(units) do open_for_unit(u, true) end
end

wml_actions["show_caster_skills"] = function(cfg)
    wesnoth.audio.play("miss-2.ogg")
    local units = wesnoth.units.find(require_filter(cfg, "show_caster_skills"))
    for _, u in ipairs(units) do open_for_unit(u, false) end
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
