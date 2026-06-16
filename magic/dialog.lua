-- dialog.lua
-- Magic System — Layer 3: Dialog
-- Splits the spell menu into three focused functions:
--   build_layout()      — builds the WML dialog structure (no side effects)
--   make_preshow()      — returns a preshow callback that wires up interactivity
--   open_dialog()       — orchestrates sync + result handling (public entry point)

local _ = wesnoth.textdomain "wesnoth-ctl"
local T = wml.tag

local spell_data -- set by init(), avoids circular require at load time

-- Formats a spell's costs into a short colored string, or nil when free.
-- Colors match the rest of the UI: XP cyan, HP red, gold yellow.
-- Built with `..` (not table.concat): the translatable _"..." pieces are
-- t_string userdata, which table.concat cannot handle.
local function format_cost(spell)
    local s
    local function add(part) s = s and (s .. ", " .. part) or part end
    if spell.xp_cost   then add("<span color='#00bbe6'>" .. spell.xp_cost   .. " " .. _"XP"   .. "</span>") end
    if spell.hp_cost   then add("<span color='#cc3333'>" .. spell.hp_cost   .. " " .. _"HP"   .. "</span>") end
    if spell.gold_cost then add("<span color='#FFD700'>" .. spell.gold_cost .. " " .. _"gold" .. "</span>") end
    if spell.atk_cost  then add(spell.atk_cost .. " " .. _"attack") end
    return s
end

-- Neutral label for a locked subskill, so its real name/cost isn't spoiled.
-- Padded with spaces (like the real subskill labels in table.lua) so the button
-- auto-sizes wide enough at build time — otherwise the word "Locked" gets clipped
-- to "Locke" on buttons whose original (shorter) label set a narrow width.
local function locked_subskill_label()
    return "   <span color='grey'>" .. _"Locked" .. "</span>   "
end

---------------------------------------------------------------------------
-- Private: skill preprocessing
-- Converts raw group data into display-ready tables, marking locked spells.
---------------------------------------------------------------------------

-- Build a fast lookup map: spell_id → spell_def
local function build_spell_index()
    local idx = {}
    -- Use pairs (not ipairs): the catalogue is keyed by number but may have
    -- gaps or be edited out of order; ipairs would silently drop every spell
    -- after the first missing index.
    for _, s in pairs(spell_data.skill_set) do
        if type(s) == "table" and s.id then idx[s.id] = s end
    end
    return idx
end

---------------------------------------------------------------------------
-- Free-assign helpers (spell picker)
---------------------------------------------------------------------------

-- Extracts a compact, single-line name from a spell's display label.
-- Spell labels are built by table.lua's label() helper, which wraps the name
-- in tall padding spans; the picker grid wants just the inner name. Falls back
-- to the full label if the expected markup is not present.
local function compact_name(spell)
    local s = tostring(spell.label or "")
    local inner = s:match("size='large'>(.-)</span>")
    return inner or s
end

-- Returns every selectable spell from the catalogue, ordered by catalogue key.
-- Uses pairs (not ipairs) so gaps in the numeric keys do not truncate the list.
local function all_spells_sorted()
    local keys = {}
    for k, v in pairs(spell_data.skill_set) do
        if type(v) == "table" and v.id then keys[#keys + 1] = k end
    end
    table.sort(keys)
    local list = {}
    for _, k in ipairs(keys) do list[#list + 1] = spell_data.skill_set[k] end
    return list
end

-- Builds the tooltip text for a spell: description plus its cost (if any).
local function spell_tooltip(spell)
    local tip  = tostring(spell.description or "")
    local cost = format_cost(spell)
    if cost then tip = tip .. "\n" .. _"Cost: " .. cost end
    return tip
end

-- Builds the spell-picker dialog: a grid of clickable spell cells (image + name),
-- each showing a description/cost tooltip on hover.
local PICKER_COLS = 6
local function build_picker_layout(spells)
    local table_grid = T.grid{}
    local row
    for idx, spell in ipairs(spells) do
        if (idx - 1) % PICKER_COLS == 0 then
            row = { "row", {} }
            table.insert(table_grid[2], row)
        end
        table.insert(row[2], T.column{ border="all", border_size=4,
            T.toggle_panel{ id="pick" .. idx, definition="fancy",
                tooltip = spell_tooltip(spell),
                T.grid{
                    T.row{ T.column{ horizontal_alignment="center", border="all", border_size=3,
                        T.image{ id="pick_img" .. idx, label = spell.image }}},
                    T.row{ T.column{ horizontal_alignment="center", border="bottom", border_size=3,
                        T.label{ id="pick_name" .. idx, use_markup=true,
                            label = "<span size='small'>" .. compact_name(spell) .. "</span>" }}},
                }}})
    end
    -- Pad the final row so every row has the same column count (grids must be rectangular).
    if row then
        local filled = #spells % PICKER_COLS
        if filled ~= 0 then
            for _ = filled + 1, PICKER_COLS do
                table.insert(row[2], T.column{ T.spacer{ width=1, height=1 }})
            end
        end
    end

    local grid = T.grid{}
    table.insert(grid[2], T.row{ T.column{ border="all", border_size=10,
        T.label{ definition="title", horizontal_alignment="center",
            label = _"Choose a Spell" }}})
    table.insert(grid[2], T.row{ T.column{ border="all", border_size=8, table_grid }})
    table.insert(grid[2], T.row{ T.column{ horizontal_alignment="center", border="all", border_size=8,
        T.button{ id="picker_cancel", return_value=2, label=_"Cancel" }}})

    return { definition="menu",
        T.helptip{ id="helptip" },
        T.tooltip{ id="tooltip" },
        grid }
end

-- Opens the picker as a nested modal dialog and returns the chosen spell id,
-- or nil if the player cancelled. Pure local UI: no game state changes here.
-- `used` is a set of spell ids already taken by OTHER slots; those cells are
-- shown disabled so the same spell cannot be picked into two slots.
-- `allowed_set` (optional) is a set of spell ids the player may pick; when given,
-- the grid is filtered to those spells only (used by free-pick / unlocked mode).
local function open_picker(used, allowed_set)
    used = used or {}
    local spells = all_spells_sorted()
    if allowed_set then
        local filtered = {}
        for _, s in ipairs(spells) do
            if allowed_set[s.id] then filtered[#filtered + 1] = s end
        end
        spells = filtered
    end
    local layout = build_picker_layout(spells)
    local chosen = nil

    gui.show_dialog(layout, function(dlg)
        for idx, spell in ipairs(spells) do
            local cell = dlg["pick" .. idx]
            if cell then
                if used[spell.id] then
                    -- Already chosen in another slot: block it and make the
                    -- "taken" state obvious — greyed-out image + struck-through name.
                    cell.enabled = false
                    local img = dlg["pick_img" .. idx]
                    if img then img.label = spell.image .. "~GS()~O(0.4)" end
                    local nm = dlg["pick_name" .. idx]
                    if nm then
                        nm.label = "<span size='small' color='#888888'><s>"
                            .. compact_name(spell) .. "</s></span>"
                    end
                else
                    cell.on_modified = function()
                        chosen = spell.id
                        gui.widget.close(dlg)
                    end
                end
            end
        end
    end)

    return chosen
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

-- Free-assign mode: returns an ordered array of initial spell ids, one per slot.
-- Each slot is pre-filled with the spell currently equipped from that group (so
-- re-opening keeps the player's previous choices), falling back to the group's
-- first spell, to the equipped spell at that index, or nil (empty).
--
-- Slot count is normally the caster's number of groups, but if the groups are
-- missing (e.g. a caster whose state was reset) it falls back to a sensible number
-- so free-assign always shows usable slots and can rebuild the caster from scratch.
local function prepare_free_slots(caster_data)
    local keys = {}
    for i in pairs(caster_data.groups) do table.insert(keys, i) end
    table.sort(keys)

    local count = #keys
    if count == 0 then
        count = math.max(caster_data.max_casts or 1, #caster_data.equipped, 3)
    end

    local slots = {}
    for n = 1, count do
        local i      = keys[n]
        local group  = i and caster_data.groups[i] or nil
        local chosen = nil
        if group then
            for _, spell_id in ipairs(group) do
                if caster_data.equipped_set[spell_id] then chosen = spell_id; break end
            end
            if not chosen and group[1] then chosen = group[1] end
        end
        if not chosen then chosen = caster_data.equipped[n] end -- fallback when no group
        -- Use `false` (never nil) for an empty slot, so #slots / ipairs stay correct
        -- even when slots are unfilled. Consumers treat false as "no spell".
        slots[n] = chosen or false
    end
    return slots
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

local function build_skill_rows(groups, selecting, equipped_list, unlocked_set)
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
                -- Castable if it has a cost OR is explicitly flagged castable,
                -- so a zero-cost spell can still be cast via a clickable button.
                if has_cost or equipped_spell.castable then
                    local cost = format_cost(equipped_spell)
                    button = T.button{ id="button"..i, use_markup=true, label=equipped_spell.label,
                        tooltip = cost and (_"Cost: " .. cost) or nil }
                else
                    button = T.label{ id="button"..i, use_markup=true, label=equipped_spell.label }
                end

                -- Subskills row.
                if equipped_spell.subskills then
                    subskill_row = T.row{}
                    for _, sub in ipairs(equipped_spell.subskills) do
                        -- Locked subskills show a neutral "Locked" label (set here, at
                        -- build time, so the button sizes to it and the text never clips).
                        local sub_label = (unlocked_set and not unlocked_set[sub.id])
                            and locked_subskill_label() or sub.label
                        table.insert(subskill_row[2],
                            T.column{ T.button{ id=sub.id, use_markup=true, label=sub_label }})
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

-- Free-assign selection mode: one clickable slot per group. Each slot is a
-- toggle_panel holding the current spell's image and name (so clicking either
-- the image or the text opens the picker), with the description shown alongside.
local function build_free_select_rows(slots, spell_index)
    local skill_grid = T.grid{}

    for i, spell_id in ipairs(slots) do
        local def  = spell_id and spell_index[spell_id] or nil
        local img  = def and def.image or "icons/locked.png"
        local name = def and def.label or _"<span color='grey'><i>— click to choose —</i></span>"
        local desc = def and def.description or ""

        local panel = T.toggle_panel{ id="slot" .. i, definition="fancy",
            tooltip = _"Click to choose any spell for this slot.",
            T.grid{ T.row{
                T.column{ border="all", border_size=6,
                    T.image{ id="slot_image" .. i, label=img }},
                T.column{ border="all", border_size=6, horizontal_alignment="left",
                    T.label{ id="slot_name" .. i, use_markup=true, label=name }},
            }}}

        table.insert(skill_grid[2], T.row{
            T.column{ border="left", border_size=15, horizontal_alignment="left", panel },
            T.column{ T.label{ label="  " }},
            T.column{ horizontal_alignment="left",
                T.label{ id="slot_desc" .. i, use_markup=true, label=desc }},
        })

        -- Spacer row.
        table.insert(skill_grid[2], T.row{
            T.column{ T.label{ label="  " }},
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
                    tooltip=_"You must choose an unlocked spell in every group.",
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
        T.button{ id="confirm_button", use_markup=true, return_value=1, label=_"Cancel" }}})

    local inner = T.grid{}
    for _, r in ipairs(rows) do table.insert(inner[2], r) end

    return T.row{ T.column{ border="top", border_size=7, horizontal_grow=true, inner }}
end

---------------------------------------------------------------------------
-- Public: build_layout
-- Returns a complete WML dialog table ready for gui.show_dialog.
---------------------------------------------------------------------------
local function build_layout(caster, caster_data, groups, selecting, free_slots)
    local dialog = { definition="menu",
        T.helptip{ id="helptip" },
        T.tooltip{ id="tooltip" },
        T.grid{} }
    local grid = dialog[3]

    for _, row in ipairs(build_header(caster_data, selecting)) do
        table.insert(grid[2], row)
    end

    local skill_grid
    if free_slots then
        skill_grid = build_free_select_rows(free_slots, build_spell_index())
    else
        skill_grid = build_skill_rows(groups, selecting, caster_data.equipped, caster_data.unlocked_set)
    end
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
local function make_preshow(caster, caster_data, groups, selecting, free_slots)
    -- Selection Confirm / Choose Later button handlers commit the chosen spells on
    -- all clients via the "magic_commit" synced command (data passed as parameters),
    -- the same in-handler invoke_command pattern cast mode uses for spell costs.

    -- Free-assign selection mode: each slot opens the spell picker; the final
    -- choice per slot is committed on confirm. This path is self-contained and
    -- returns early, never touching the group/cast wiring below.
    if free_slots then
        local spell_index = build_spell_index()

        -- Free-pick mode: restrict the picker grid to the caster's unlocked
        -- spells. Plain free-assign (nil) shows the whole catalogue. If both
        -- flags are set, free-assign wins (full catalogue) — it is the superset.
        local allowed_set = (caster_data.free_unlocked and not caster_data.free_assign)
            and caster_data.unlocked_set or nil

        local slot_choice = {}
        for i, spell_id in ipairs(free_slots) do
            -- Drop any pre-filled pick that isn't selectable in this mode, so a
            -- locked spell can never be confirmed via free-pick.
            if spell_id and allowed_set and not allowed_set[spell_id] then
                slot_choice[i] = false
            else
                slot_choice[i] = spell_id
            end
        end

        return function(dlg)
            local function refresh_slot(i)
                local def = slot_choice[i] and spell_index[slot_choice[i]] or nil
                dlg["slot_image" .. i].label = def and def.image or "icons/locked.png"
                dlg["slot_name"  .. i].label = def and def.label
                    or _"<span color='grey'><i>— click to choose —</i></span>"
                if dlg["slot_desc" .. i] then
                    dlg["slot_desc" .. i].label = def and def.description or ""
                end
            end

            local function update_confirm_enabled()
                local cb = dlg["confirm_button"]
                if not cb then return end
                for i = 1, #free_slots do
                    if not slot_choice[i] then cb.enabled = false; return end
                end
                cb.enabled = true
            end

            for i = 1, #free_slots do
                refresh_slot(i)
                local panel = dlg["slot" .. i]
                if panel then
                    local busy = false -- guards against re-entrant on_modified
                    panel.on_modified = function()
                        if busy then return end
                        busy = true
                        -- Block spells already chosen in other slots (no duplicates).
                        local used = {}
                        for j = 1, #free_slots do
                            if j ~= i and slot_choice[j] then used[slot_choice[j]] = true end
                        end
                        local picked = open_picker(used, allowed_set)
                        if picked then
                            slot_choice[i] = picked
                            refresh_slot(i)
                        end
                        panel.selected = false -- reset so the slot can be reopened
                        update_confirm_enabled()
                        busy = false
                    end
                end
            end
            update_confirm_enabled()

            local cb = dlg["confirm_button"]
            if cb then
                cb.on_button_click = function()
                    -- Filter out empty (false) slots so table.concat never sees a boolean.
                    local list = {}
                    for i = 1, #free_slots do
                        if slot_choice[i] then list[#list + 1] = slot_choice[i] end
                    end
                    wesnoth.sync.invoke_command("magic_commit",
                        { id = caster.id, equipped = table.concat(list, ","), wait = "" })
                    gui.widget.close(dlg)
                end
            end

            local wb = dlg["wait_button"]
            if wb then
                wb.on_button_click = function()
                    wesnoth.sync.invoke_command("magic_commit",
                        { id = caster.id, equipped = "", wait = "yes" })
                    gui.widget.close(dlg)
                end
            end
        end
    end

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
            btn.label = small_label(_"Cancel")
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
            -- Locked subskill: hide its real name/cost so an un-earned upgrade
            -- isn't spoiled — show a neutral "Locked" tag instead. (Main equipped
            -- spells are always unlocked, so in practice this only hits subskills.)
            -- Uses the same padded label as build time, so the width already fits.
            if small then btn.label = locked_subskill_label() end
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

    return function(dlg)
        -- Selection mode: keep Confirm disabled while any group still has a
        -- "Locked" option selected — every pick must be a valid unlocked spell.
        local function update_confirm_enabled()
            local cb = dlg["confirm_button"]
            if not cb then return end
            for gi, g in ipairs(groups) do
                local mb  = dlg["button" .. gi]
                local sel = mb and g[mb.selected_index]
                if sel and sel.id == "skill_locked" then cb.enabled = false; return end
            end
            cb.enabled = true
        end

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

                -- Refresh the preview image/label whenever the menu changes,
                -- and re-evaluate whether Confirm may be enabled.
                -- IMPORTANT: on_modified is invoked with NO arguments (Wesnoth
                -- 1.19 widget API), so read the selection from the captured `btn`
                -- rather than a parameter — otherwise changing a dropdown crashes
                -- with "attempt to index a nil value".
                local function refresh()
                    local sel = group[btn.selected_index]
                    if sel then
                        dlg["image"..i].label = sel.image
                        dlg["label"..i].label = sel.description
                    end
                    update_confirm_enabled()
                end
                refresh()
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

        -- Selection mode: Confirm/Choose Later commit on ALL clients via the
        -- magic_commit synced command (data passed as parameters). invoke_command
        -- from inside the button handler is the proven cast-mode pattern and works
        -- because the dialog is always opened from an unsynced context.
        if selecting then
            local cb = dlg["confirm_button"]
            if cb then
                cb.on_button_click = function()
                    -- Read each group's current menu selection directly, so the
                    -- same spell may appear in multiple groups without collisions.
                    local new_eq = {}
                    for gi, g in ipairs(groups) do
                        local mb  = dlg["button" .. gi]
                        local sel = mb and g[mb.selected_index]
                        if sel and sel.id and sel.id ~= "skill_locked" then
                            table.insert(new_eq, sel.id)
                        end
                    end
                    wesnoth.sync.invoke_command("magic_commit",
                        { id = caster.id, equipped = table.concat(new_eq, ","), wait = "" })
                    gui.widget.close(dlg)
                end
            end
            local wb = dlg["wait_button"]
            if wb then
                wb.on_button_click = function()
                    wesnoth.sync.invoke_command("magic_commit",
                        { id = caster.id, equipped = "", wait = "yes" })
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

    end
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

    -- Free-assign and free-pick (unlocked-only) both use the slot/picker UI while
    -- selecting; cast mode is unchanged. The two differ only in which spells the
    -- picker offers (see open_picker's allowed_set in make_preshow).
    local free_slots = (selecting and (caster_data.free_assign or caster_data.free_unlocked))
        and prepare_free_slots(caster_data) or nil

    local groups = free_slots and {} or prepare_groups(caster_data)
    local dialog = build_layout(caster, caster_data, groups, selecting, free_slots)
    local preshow = make_preshow(caster, caster_data, groups, selecting, free_slots)

    -- Deselect caster so the dialog doesn't appear over a selected unit.
    wesnoth.interface.game_display.selected_unit = nil
    wesnoth.interface.delay(300)
    wesnoth.units.select()
    wesnoth.interface.deselect_hex()
    wml.fire("redraw")

    if selecting then
        -- The dialog is local UI; the Confirm / Choose Later button handlers commit
        -- the result on all clients via the magic_commit synced command (data passed
        -- as parameters). This is the same pattern cast mode uses for spell costs.
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
