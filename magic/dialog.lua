-- dialog.lua
-- Magic System — Layer 3: Dialog
-- Splits the spell menu into three focused functions:
--   build_layout()      — builds the WML dialog structure (no side effects)
--   make_preshow()      — returns a preshow callback that wires up interactivity
--   open_dialog()       — orchestrates sync + result handling (public entry point)

local _ = wesnoth.textdomain "wesnoth-ctl"
local T = wml.tag

local spell_data -- set by init(), avoids circular require at load time

---------------------------------------------------------------------------
-- Private: skill preprocessing
-- Converts raw group data into display-ready tables, marking locked spells.
---------------------------------------------------------------------------

-- Build a fast lookup map: spell_id → spell_def
local function build_spell_index()
    local idx = {}
    for _, s in ipairs(spell_data.skill_set) do idx[s.id] = s end
    return idx
end

local function prepare_groups(caster_data)
    -- Returns an ordered array of display groups (no sparse keys).
    -- Order follows the numeric order of caster_data.groups keys.
    local spell_index = build_spell_index()
    local result = {}

    -- Collect group keys and sort them to guarantee stable order.
    local keys = {}
    for i in pairs(caster_data.groups) do table.insert(keys, i) end
    table.sort(keys)

    for _, i in ipairs(keys) do
        local group = caster_data.groups[i]
        local display_group = {}
        local all_locked = true

        for _, spell_id in ipairs(group) do
            local spell_def = spell_index[spell_id]
            if spell_def then
                if caster_data.unlocked_set[spell_id] then
                    table.insert(display_group, spell_def)
                    all_locked = false
                else
                    table.insert(display_group, spell_data.locked)
                end
            end
        end

        if not all_locked and #display_group > 0 then
            table.insert(result, display_group)
        end
    end

    return result
end

---------------------------------------------------------------------------
-- Private: layout builders
---------------------------------------------------------------------------

local function build_header(caster_data, selecting)
    local title = selecting and caster_data.title_select or caster_data.title_cast
    local help  = "<span size='small'><i>" .. caster_data.description .. "</i></span>"
    return {
        T.row{ T.column{ border="bottom", border_size=15,
            T.image{ label="icons/banner1.png" }}},
        T.row{ T.column{
            T.label{ definition="title", horizontal_alignment="center", label=title }}},
        T.row{ T.column{ border="top", border_size=15,
            T.label{ use_markup=true, label=help }}},
        T.row{ T.column{ border="top", border_size=15,
            T.image{ label="icons/banner2.png" }}},
    }
end

local function build_skill_rows(groups, selecting, equipped_list)
    local equipped_set = {}
    for _, s in ipairs(equipped_list) do equipped_set[s] = true end

    local skill_grid = T.grid{}

    for i, group in ipairs(groups) do

        local button, subskill_row

        if selecting then
            -- Menu button for picking which spell from this group.
            button = T.menu_button{ id="button"..i, use_markup=true }
            for _, spell in ipairs(group) do
                table.insert(button[2], T.option{ label=spell.label })
            end
        else
            -- Show label or castable button for the equipped spell in this group.
            local equipped_spell = nil
            for _, spell in ipairs(group) do
                if spell.id and equipped_set[spell.id] then
                    equipped_spell = spell
                    break
                end
            end

            if equipped_spell then
                local has_cost = equipped_spell.xp_cost or equipped_spell.gold_cost
                    or equipped_spell.hp_cost or equipped_spell.atk_cost
                if has_cost then
                    button = T.button{ id="button"..i, use_markup=true, label=equipped_spell.label }
                else
                    button = T.label{ id="button"..i, use_markup=true, label=equipped_spell.label }
                end

                -- Subskills row.
                if equipped_spell.subskills then
                    subskill_row = T.row{}
                    for _, sub in ipairs(equipped_spell.subskills) do
                        -- Subskills are always considered unlocked if the parent is unlocked.
                        table.insert(subskill_row[2],
                            T.column{ T.button{ id=sub.id, use_markup=true, label=sub.label }})
                    end
                end
            else
                button = T.label{ id="button"..i } -- invisible placeholder
            end
        end

        -- Main row: button | spacer | image | spacer | description label
        table.insert(skill_grid[2], T.row{
            T.column{ border="left",  border_size=15, button },
            T.column{ T.label{ label="  " }},
            T.column{ horizontal_alignment="left", T.image{ id="image"..i }},
            T.column{ border="right", border_size=15, T.label{ label="  " }},
            T.column{ horizontal_alignment="left", T.label{ id="label"..i, use_markup=true }},
        })

        -- Subskill row (only in cast mode).
        if subskill_row then
            table.insert(skill_grid[2], T.row{
                T.column{ T.label{} }, T.column{ T.label{} },
                T.column{ T.label{} }, T.column{ T.label{} },
                T.column{ T.grid{ subskill_row }},
            })
        end

        -- Spacer row.
        table.insert(skill_grid[2], T.row{
            T.column{ T.label{ label="  " }},
            T.column{ T.label{} }, T.column{ T.label{} },
            T.column{ T.label{} }, T.column{ T.label{} },
        })
    end

    return skill_grid
end

local function build_footer(caster, caster_data, selecting)
    if selecting then
        -- No return_value: on_button_click handlers in make_preshow close the dialog
        -- and call invoke_command from inside the click (required for MP sync).
        return T.row{ T.column{ T.grid{ T.row{
            T.column{ border="top,right", border_size=10,
                T.button{ id="confirm_button", use_markup=true,
                    label=_"Confirm Spells <small><i>(can be changed every scenario)</i></small>" }},
            T.column{ border="top,left",  border_size=10,
                T.button{ id="wait_button", use_markup=true,
                    label=_"Choose Later" }},
        }}}}
    end

    -- Cast mode footer: Cancel button, and optionally an Advance button.
    local advance_xp = math.floor(0.9 * caster.max_experience)
    local advance_tip = _"Spend <span color='#00bbe6'><i>" .. advance_xp .. " XP</i></span> to:\n"
        .. "• fully heal " .. caster.name .. ".\n"
        .. "• get <span color='red'><i>+6 max HP</i></span>.\n"
        .. "• increase <span color='#00bbe6'><i>max XP by 20%</i></span>."

    local show_advance = caster_data and not caster_data.advancement_disabled

    local rows = {}

    -- Upgrade row: [↑] 59/43 XP   3/3 spells   [Change Spells]
    local max_casts     = caster_data and (caster_data.max_casts or 1) or 1
    local casts_done    = caster_data and (caster_data.casts_this_turn or 0) or 0
    local show_counter  = caster_data and max_casts > 1
    local show_reselect = caster_data and caster_data.reselect_free == true

    if show_advance or show_reselect or show_counter then
        local upgrade_row = { "row", {} }

        if show_advance then
            table.insert(upgrade_row[2], T.column{
                border="right", border_size=6, grow_factor=0, horizontal_alignment="left",
                T.button{ id="advance_button", use_markup=true, return_value=3,
                    tooltip=advance_tip, definition="up_arrow" }})
            table.insert(upgrade_row[2], T.column{
                border="right", border_size=18, grow_factor=0, horizontal_alignment="left",
                T.label{ use_markup=true, tooltip=advance_tip,
                    label="<span color='#00bbe6'><i>"
                        .. caster.experience .. "/" .. advance_xp .. " XP</i></span>" }})
        end

        -- Counter in the middle, reselect button on the right
        if show_counter then
            local remaining = max_casts - casts_done
            local color = remaining > 0 and "#00bbe6" or "#cc3333"
            table.insert(upgrade_row[2], T.column{
                border="right", border_size=14, grow_factor=0, horizontal_alignment="center",
                T.label{ use_markup=true,
                    label="<span color='"..color.."'><i>"
                        ..remaining.."/"..max_casts.." ".._"spells".."</i></span>" }})
        end

        if show_reselect then
            table.insert(upgrade_row[2], T.column{
                grow_factor=0, horizontal_alignment="right",
                T.button{ id="reselect_button", use_markup=true, return_value=4,
                    label=_"Change Spells" }})
        end

        table.insert(rows, T.row{ T.column{ border="left", border_size=15,
            grow_factor=0, horizontal_alignment="left",
            T.grid{ upgrade_row }}})
        table.insert(rows, T.row{ T.column{ T.spacer{ width=1, height=6 }}})
    end

    table.insert(rows, T.row{ T.column{ horizontal_alignment="center",
        T.button{ id="confirm_button", use_markup=true, return_value=1, label="Cancel" }}})

    local inner = T.grid{}
    for _, r in ipairs(rows) do table.insert(inner[2], r) end

    return T.row{ T.column{ border="top", border_size=7, horizontal_grow=true, inner }}
end

---------------------------------------------------------------------------
-- Public: build_layout
-- Returns a complete WML dialog table ready for gui.show_dialog.
---------------------------------------------------------------------------
local function build_layout(caster, caster_data, groups, selecting)
    local dialog = { definition="menu",
        T.helptip{ id="helptip" },
        T.tooltip{ id="tooltip" },
        T.grid{} }
    local grid = dialog[3]

    for _, row in ipairs(build_header(caster_data, selecting)) do
        table.insert(grid[2], row)
    end

    local skill_grid = build_skill_rows(groups, selecting, caster_data.equipped)
    table.insert(grid[2], T.row{ T.column{
        horizontal_alignment="left", skill_grid }})

    table.insert(grid[2], T.row{ T.column{
        T.image{ label="icons/banner2.png" }}})

    table.insert(grid[2], build_footer(caster, caster_data, selecting))

    table.insert(grid[2], T.row{ T.column{ border="top", border_size=15,
        T.image{ label="icons/banner4.png" }}})

    return dialog
end

---------------------------------------------------------------------------
-- Public: make_preshow
-- Returns a function(dialog) that populates and wires the dialog.
---------------------------------------------------------------------------
local function make_preshow(caster, caster_data, groups, selecting)
    -- Helper: check if caster has an object by id.
    local function has_object(object_id)
        return wesnoth.units.find_on_map{
            id = caster.id,
            wml.tag.filter_wml{ wml.tag.modifications{ wml.tag.object{ id=object_id }}}
        }[1] ~= nil
    end

    -- Helper: configure a castable button (or its subskill button).
    local function setup_cast_button(dlg, btn_id, spell, small)
        local btn = dlg[btn_id]
        if not btn or btn.type ~= "button" then return end

        local function small_label(text)
            return small and ("<span size='small'>"..text.."</span>") or text
        end

        -- Active toggle: show Cancel if the object is already applied.
        if has_object(spell.id) then
            btn.label = small_label("Cancel")
            btn.on_button_click = function()
                -- Set current_caster on ALL clients before the cancel event fires.
                wesnoth.sync.invoke_command("magic_set_caster", { id = caster.id })
                wml.variables["caster_" .. caster.id .. ".spell_to_cast"] = spell.id .. "_cancel"
                gui.widget.close(dlg)
            end
            return
        end

        -- Blocking conditions (ordered by priority).
        local max_casts  = caster_data.max_casts or 1
        local casts_done = caster_data.casts_this_turn or 0
        local blocked_label
        if not caster_data.unlocked_set[spell.id] then
            btn.enabled = false; return
        elseif casts_done >= max_casts then
            blocked_label = (max_casts == 1)
                and _"<span> Can only cast\n1 spell per turn</span>"
                or  ("<span> No spells left\n(" .. casts_done .. "/" .. max_casts .. ")</span>")
        elseif caster_data.polymorphed then
            blocked_label = _"<span>  Blocked by\n  Polymorph</span>"
        elseif wesnoth.units.find_on_map{
            id=caster.id,
            wml.tag.filter_location{ radius=3, wml.tag.filter{ id="Haralin_mirror3" }}
        }[1] then
            blocked_label = _"<span>  Blocked by\n Counterspell</span>"
        elseif wml.variables["counterspell_active"] then
            blocked_label = _"<span>  Blocked by\n Counterspell</span>"
        elseif spell.xp_cost and spell.xp_cost > caster.experience then
            blocked_label = small_label(_"No XP")
        elseif spell.hp_cost and spell.hp_cost >= caster.hitpoints then
            blocked_label = small_label(_"No HP")
        elseif spell.gold_cost and spell.gold_cost > wesnoth.sides[caster.side].gold then
            blocked_label = small_label(_"No Gold")
        elseif spell.atk_cost and spell.atk_cost > caster.attacks_left then
            blocked_label = small_label(_"No Attack")
        end

        if blocked_label then
            btn.label   = blocked_label
            btn.enabled = false
            return
        end

        -- Ready to cast.
        btn.on_button_click = function()
            wesnoth.sync.invoke_command("spellcasting_cost", {
                id              = caster.id,
                xp_cost         = spell.xp_cost,
                hp_cost         = spell.hp_cost,
                gold_cost       = spell.gold_cost,
                atk_cost        = spell.atk_cost,
                casts_increment = true, -- increment synced counter (multi-cast tracking)
            })
            -- Set current_caster on ALL clients from inside the button click.
            -- invoke_command is only valid inside show_dialog button handlers in MP.
            wesnoth.sync.invoke_command("magic_set_caster", { id = caster.id })
            wml.variables["caster_" .. caster.id .. ".spell_to_cast"]        = spell.id
            wml.variables["caster_" .. caster.id .. ".spellcasted_this_turn"] = spell.id
            gui.widget.close(dlg)
        end
    end

    -- result_table: used only in select mode to track menu selections.
    local result_table = {}

    return function(dlg)
        for i, group in ipairs(groups) do
            local btn = dlg["button"..i]

            if selecting then
                -- Set default selected index to the currently equipped spell.
                for j, spell in ipairs(group) do
                    if spell.id and caster_data.equipped_set[spell.id] then
                        btn.selected_index = j
                        break
                    end
                end

                -- Refresh image/label and update result_table whenever the menu changes.
                local function refresh(b)
                    if not group[1] then return end
                    local sel = group[b.selected_index]
                    dlg["image"..i].label = sel.image
                    dlg["label"..i].label = sel.description
                    for j, spell in ipairs(group) do
                        -- Store as boolean so evaluate_single sync is unambiguous.
                        result_table[spell.id] = (j == b.selected_index
                            and spell.id ~= "skill_locked")
                    end
                end
                refresh(btn)
                btn.on_modified = refresh

            else
                -- Cast mode: find which spell from this group is equipped.
                local equipped_spell = nil
                for _, spell in ipairs(group) do
                    if spell.id and caster_data.equipped_set[spell.id] then
                        equipped_spell = spell; break
                    end
                end

                if equipped_spell then
                    dlg["button"..i].visible = true
                    dlg["image"..i].label    = equipped_spell.image
                    dlg["label"..i].label    = equipped_spell.description
                    setup_cast_button(dlg, "button"..i, equipped_spell, false)

                    if equipped_spell.subskills then
                        for _, sub in ipairs(equipped_spell.subskills) do
                            setup_cast_button(dlg, sub.id, sub, true)
                        end
                    end
                else
                    if dlg["button"..i] then dlg["button"..i].visible = false end
                end
            end
        end

        -- Selection mode: wire Confirm and Choose Later buttons to sync on ALL clients.
        -- invoke_command MUST be called from inside a show_dialog button handler in MP —
        -- it does NOT work after show_dialog returns (non-active clients skip that code).
        if selecting then
            local cb = dlg["confirm_button"]
            if cb then
                cb.on_button_click = function()
                    local new_eq = {}
                    for spell_id, chosen in pairs(result_table) do
                        if chosen == true then table.insert(new_eq, spell_id) end
                    end
                    wesnoth.sync.invoke_command("magic_sync_equipped", {
                        caster_id = caster.id,
                        equipped  = table.concat(new_eq, ","),
                        wait      = "",
                    })
                    gui.widget.close(dlg)
                end
            end
            local wb = dlg["wait_button"]
            if wb then
                wb.on_button_click = function()
                    wesnoth.sync.invoke_command("magic_sync_equipped", {
                        caster_id = caster.id,
                        equipped  = "",
                        wait      = "yes",
                    })
                    gui.widget.close(dlg)
                end
            end
        end

        -- Advance button (cast mode only).
        if not selecting and not caster_data.advancement_disabled then
            local ab = dlg["advance_button"]
            if ab then
                local advance_xp_needed = math.floor(0.9 * caster.max_experience)
                ab.enabled = (caster.experience >= advance_xp_needed)
                ab.on_button_click = function()
                    wesnoth.sync.invoke_command("spellcasting_cost",
                        { id=caster.id, xp_cost=advance_xp_needed })
                    wesnoth.sync.invoke_command("magic_set_caster", { id = caster.id })
                    wml.variables["caster_" .. caster.id .. ".spell_to_cast"] = "advance_caster"
                end
            end
        end

    end, result_table
end

---------------------------------------------------------------------------
-- Public: open_dialog
-- Entry point. Call from wml_actions or the double-click handler.
--   caster      — Wesnoth unit proxy
--   caster_data — table from CasterState.load()
--   selecting   — true = spell selection mode, false = cast mode
---------------------------------------------------------------------------
local function open_dialog(caster, caster_data, selecting)
    -- Guard: do nothing during replays or when it's not the local player's turn.
    if wesnoth.current.user_is_replaying then return end
    local sides = wesnoth.sides.find{ side=caster.side }
    if not (sides[1].controller == "human"
        and sides[1].is_local
        and wml.variables["side_number"] == sides[1].side) then return end

    local groups = prepare_groups(caster_data)
    local dialog = build_layout(caster, caster_data, groups, selecting)
    local preshow, result_table = make_preshow(caster, caster_data, groups, selecting)

    -- Deselect caster so the dialog doesn't appear over a selected unit.
    wesnoth.interface.game_display.selected_unit = nil
    wesnoth.interface.delay(300)
    wesnoth.units.select()
    wesnoth.interface.deselect_hex()
    wml.fire("redraw")

    if selecting then
        -- invoke_command for sync is now handled inside button click handlers in preshow
        -- (confirm_button / wait_button). Non-active clients skip evaluate_single entirely,
        -- so any invoke_command called after show_dialog returns would only run locally.
        wesnoth.sync.evaluate_single(function()
            gui.show_dialog(dialog, preshow)
        end)
        return false -- no reselect from selection mode

    else
        -- Cast mode: result is the spell the user clicked (stored via spell_to_cast).
        local requested_reselect = false
        wesnoth.sync.evaluate_single(function()
            local rv = gui.show_dialog(dialog, preshow)

            -- rv == 4 means the "Change Spells" button was clicked (return_value=4).
            if rv == 4 then
                wml.variables["caster_" .. caster.id .. ".requested_reselect"] = true
                return
            end

            local spell_to_cast = wml.variables["caster_" .. caster.id .. ".spell_to_cast"]
            if spell_to_cast then
                wml.variables["is_badly_timed"] = true
                -- Set current_caster INSIDE do_command so it's synced atomically with fire_event.
                -- invoke_command("magic_set_caster") from show_dialog button handlers may arrive
                -- on non-active clients AFTER the do_command packet, causing a race condition.
                -- Including set_variable here guarantees correct current_caster on ALL clients.
                wml.fire.do_command({
                    wml.tag.set_variable{ name="current_caster", value=caster.id },
                    wml.tag.fire_event{ raise = spell_to_cast },
                })
                wml.variables["caster_" .. caster.id .. ".spell_to_cast"] = nil
                wml.variables["is_badly_timed"] = nil
            end
        end)
    end

    wml.variables["caster_" .. caster.id .. ".spellcasted_this_turn"] = nil

    -- Check if the user clicked "Change Spells" (free-reselect upgrade).
    local reselect = wml.variables["caster_" .. caster.id .. ".requested_reselect"] == true
    if reselect then
        wml.variables["caster_" .. caster.id .. ".requested_reselect"] = nil
    end
    return reselect
end

---------------------------------------------------------------------------
-- Module init: inject spell_data dependency to avoid circular require.
---------------------------------------------------------------------------
local M = {}

function M.init(sd)
    spell_data = sd
end

M.open_dialog = open_dialog

return M
