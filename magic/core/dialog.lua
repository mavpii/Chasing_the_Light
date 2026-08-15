-- dialog.lua
-- Magic System — Layer 3: Dialog
-- Splits the spell menu into three focused functions:
--   build_layout()      — builds the WML dialog structure (no side effects)
--   make_preshow()      — returns a preshow callback that wires up interactivity
--   open_dialog()       — orchestrates sync + result handling (public entry point)

local _ = wesnoth.textdomain "wesnoth-ctl"
local T = wml.tag

local CasterState = wesnoth.require "state.lua"

local spell_data -- set by init(), avoids circular require at load time
local M = {}

-- The modification's options, as the gear in the cast window edits them. Read
-- straight from the WML variables the [options] block writes, rather than from
-- mod.lua: the two files load through different require paths ("dialog.lua" from
-- core.lua, the full path from mod.lua), which gives them SEPARATE module tables
-- and made an injected hook invisible here.
local MOD_LIVE_OPTIONS = {
    { id = "ctl_magic_mod_slots",   kind = "number", min = 1, max = 8,
      label = _"Spell slots per caster", default = 3 },
    { id = "ctl_magic_mod_casts",   kind = "number", min = 1, max = 4,
      label = _"Spells cast per turn", default = 1 },
    -- The top stop means "no limit"; the slider's own [value_labels] spell that out.
    { id = "ctl_magic_mod_limit",   kind = "limit",  min = 1, max = 11,
      label = _"Casters per side", default = "3" },
    { id = "ctl_magic_mod_costs",   kind = "choice", values = { "free", "normal" },
      labels = { _"Free casting", _"Normal costs" },
      label = _"Casting cost", default = "free" },
    { id = "ctl_magic_mod_advance", kind = "choice", values = { "default", "amla", "levels" },
      labels = { _"Spells only", _"Spells + AMLAs", _"Spells + Level ups" },
      label = _"Experience is used for", default = "levels" },
    { id = "ctl_magic_mod_change",  kind = "bool",
      label = _"Spells can be changed later", default = true },
    { id = "ctl_magic_mod_ai",      kind = "bool",
      label = _"Computer players get casters", default = true },
}

local function mod_option(opt)
    local v = wml.variables[opt.id]
    if v == nil or v == "" then return opt.default end
    if opt.kind == "bool"   then return v == true or v == "yes" end
    if opt.kind == "number" then return tonumber(v) or opt.default end
    return tostring(v)
end


-- The gear shows when the modification is running (its options exist) and the
-- game was set up to allow changes. Whose turn it is needs no check here: the
-- cast window itself only opens for a local human side on its own turn.
local function mod_settings_allowed()
    if wml.variables["ctl_magic_mod_slots"] == nil then return false end
    local live = wml.variables["ctl_magic_mod_live"]
    return live == nil or live == "" or live == true or live == "yes"
end

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

---------------------------------------------------------------------------
-- Private: spell descriptions
-- A description is either plain text (`description`, as before) or varies with
-- the caster: `description_by_level` holds one text per level, and every
-- `description_extra` entry is appended once the caster unlocks the spell or
-- subskill it is keyed by.
---------------------------------------------------------------------------

-- The caster the dialog is currently open for. Set by open_dialog before anything
-- is built: descriptions are read from five places (both picker views, free-assign
-- slots, and the selection/cast rows), and passing the caster through all of them
-- would change every builder's signature for one string.
local desc_ctx = nil

-- Picks the description_by_level entry for `level`: the highest level listed that
-- the caster has reached, so a "level 2 and up" text keeps showing at level 3+.
-- Below the lowest listed level the lowest entry is used, so the text is never blank.
--
-- Second return value: the lowest level listed, but ONLY when the caster has not
-- reached it. Those spells grant nothing at all below it -- spells.cfg gates the
-- attack on the caster's level and simply skips it (Chain Lightning starts at 3,
-- Magic Rage at 3, Fireball at 2) -- so the text alone would promise an attack
-- that never appears on the unit. describe() turns it into a warning line.
local function description_for_level(by_level, level)
    local best, best_level, lowest, lowest_level
    for lvl, text in pairs(by_level) do
        if not lowest_level or lvl < lowest_level then lowest, lowest_level = text, lvl end
        if lvl <= level and (not best_level or lvl > best_level) then best, best_level = text, lvl end
    end
    if best then return best end
    return lowest, lowest_level
end

-- Resolves a spell's description for the caster the dialog is open for.
-- Returns "" for a nil spell (an empty free-assign slot).
local function describe(spell)
    if not spell then return "" end

    local level    = desc_ctx and desc_ctx.level    or 1
    local unlocked = desc_ctx and desc_ctx.unlocked or {}

    local text, needs_level
    if spell.description_by_level then
        text, needs_level = description_for_level(spell.description_by_level, level)
    else
        text = spell.description
    end
    if text == nil then return "" end

    -- A description may refer to the caster by name with $caster (Polymorph does:
    -- "Replaces $caster's attacks..."). One string then serves every caster that
    -- can learn the spell, instead of naming one of them in the text.
    local name = desc_ctx and desc_ctx.name
    if name and tostring(text):find("$caster", 1, true) then
        -- gsub with a function, not a plain replacement string: a name is player
        -- data and a % in it would be read as a capture reference otherwise.
        text = tostring(text):gsub("%$caster", function() return name end)
    end

    -- Only flatten to a plain string when the extra lines actually have to be
    -- glued on: everywhere else the translatable string is handed to the widget
    -- exactly as table.lua wrote it, which is what TDG's dialog does too.
    if spell.description_extra then
        text = tostring(text)
        local shown, lines = {}, {}
        local function add(id)
            local extra = spell.description_extra[id]
            if extra and unlocked[id] and not shown[id] then
                shown[id] = true
                lines[#lines + 1] = tostring(extra)
            end
        end
        -- Subskill order first, so the lines always appear in the order the spell
        -- lists them; any remaining keys follow, sorted, to stay deterministic.
        for _, sub in ipairs(spell.subskills or {}) do add(sub.id) end
        local rest = {}
        for id in pairs(spell.description_extra) do
            if not shown[id] then rest[#rest + 1] = id end
        end
        table.sort(rest)
        for _, id in ipairs(rest) do add(id) end

        if #lines > 0 then
            -- One entry per line by default. A spell can set
            -- description_extra_separator (e.g. ", ") to keep them on a single line;
            -- then only the first entry keeps its indent, so the joined line reads
            -- as one sentence.
            local separator = spell.description_extra_separator
            if separator then
                for i = 2, #lines do lines[i] = lines[i]:gsub("^%s+", "") end
            end
            text = text .. "\n" .. table.concat(lines, separator or "\n")
        end
    end

    -- Said last, and only when the caster is below the spell's first listed level:
    -- equipping it there is legal and costs a slot, but spells.cfg grants nothing,
    -- so without this the row describes an attack the unit will never have.
    if needs_level then
        text = tostring(text) .. "\n           <span color='grey'>"
            .. tostring(_"Grants nothing until level %d."):format(needs_level)
            .. "</span>"
    end

    return text
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

-- Descriptions carry <ref dst='...'> links into the help browser, which only a
-- rich_label understands; every row that shows a description uses one. What is
-- left over goes through Pango and has the links flattened to the words they
-- wrap, since Pango would refuse to parse a tag it does not know: the picker's
-- hover tooltips (a tooltip cannot hold a link at all) and its list view, where
-- the text sits inside the panel that selects the spell, so a link there would
-- swallow that click.
local function strip_refs(text)
    return (tostring(text or ""):gsub("<ref[^>]*>", ""):gsub("</ref>", ""))
end

-- Makes the <ref> links in a rich_label's description clickable: clicking one
-- opens that topic in the help browser, exactly as TDG's spell dialog does.
-- A rich_label only wires up its click/hover signals when a handler is
-- registered, so setting the label alone leaves the links inert.
local function make_links_clickable(widget)
    if not widget then return end
    -- pcall'd on purpose: a rich_label supports both fields, but a dialog must
    -- never die over a link. link_aware first — the widget refuses to register
    -- the callback while it is off.
    pcall(function() widget.link_aware = true end)
    pcall(function() widget.on_link_click = function(dest) gui.show_help(dest) end end)
end

-- Builds the tooltip text for a spell: description plus its cost (if any).
local function spell_tooltip(spell)
    local tip  = strip_refs(describe(spell))
    local cost = format_cost(spell)
    if cost then tip = tip .. "\n" .. _"Cost: " .. cost end
    return tip
end

-- Remembers the player's last-used picker view (1 = grid, 2 = list) across
-- multiple slot clicks within the same selection dialog session.
local picker_view = 1

-- Grid view: a compact table of clickable spell cells (image + name), each
-- showing its description/cost as a hover tooltip only.
local PICKER_COLS = 6

-- Width left for a list row's description once the icon (56) and name (150)
-- columns, the borders and the scrollbar are taken out. A formula, not a number,
-- so it tracks PICKER_LIST_WIDTH below (keep the two expressions in step): that
-- view is size_lock'ed to that width with horizontal scrolling "never", so a
-- fixed width would overflow the lock on a small screen and the dialog would
-- throw instead of opening. Declared up here because build_picker_list closes
-- over it -- a local declared further down would compile to a global lookup and
-- arrive as nil.
local PICKER_LIST_DESC_WIDTH = "(min(900, screen_width * 45 / 100) - 260)"
local function build_picker_grid(spells)
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
                    -- Fixed cell width, so the grid is a grid: without it every
                    -- column is as wide as its longest spell name and the icons
                    -- sit on a ragged set of verticals.
                    --
                    -- Must stay well under PICKER_GRID_WIDTH / PICKER_COLS: the
                    -- view is size_lock'ed to that width with horizontal scrolling
                    -- set to "never", so content wider than the lock cannot be laid
                    -- out at all and the dialog throws instead of opening.
                    -- 6 x 90 + borders + the vertical scrollbar still fits in 650.
                    T.row{ T.column{ T.spacer{ width=90, height=1 }}},
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
    return table_grid
end

-- List view: one row per spell, with image + name + full description all
-- visible at once (no hover needed). Wrapped in a scrollbar_panel since the
-- full catalogue (free-assign mode) is far too long to fit on screen as a
-- flat list.
local function build_picker_list(spells)
    local rows_grid = T.grid{}
    for idx, spell in ipairs(spells) do
        table.insert(rows_grid[2], T.row{ T.column{ border="all", border_size=2, horizontal_grow=true,
            T.toggle_panel{ id="pick_list" .. idx, definition="fancy",
                T.grid{
                -- Each row is its own panel, so its own grid: widths are negotiated
                -- per row, every panel ends up as wide as its own description, and
                -- the whole lot is centred -- which is why nothing lined up.
                --
                -- All three columns are pinned instead. The last one is a formula
                -- rather than a number so it tracks PICKER_LIST_WIDTH: the view is
                -- size_lock'ed to that width with horizontal scrolling "never", so
                -- a fixed pixel width would overflow (and throw) on a small screen.
                T.row{
                    T.column{ T.spacer{ width=56,  height=1 }},
                    T.column{ T.spacer{ width=150, height=1 }},
                    T.column{ T.spacer{ width=PICKER_LIST_DESC_WIDTH, height=1 }},
                },
                T.row{
                    T.column{ border="all", border_size=4, horizontal_alignment="center", vertical_alignment="center",
                        T.image{ id="pick_list_img" .. idx, label = spell.image }},
                    T.column{ border="all", border_size=4, horizontal_alignment="left", vertical_alignment="center",
                        T.label{ id="pick_list_name" .. idx, use_markup=true,
                            label = "<span size='small'>" .. compact_name(spell) .. "</span>" }},
                    -- No grow: the spacer row above already fixes this column's
                    -- width, and growing it back would undo that.
                    T.column{ border="all", border_size=4, horizontal_alignment="left", vertical_alignment="center",
                        T.label{ id="pick_list_desc" .. idx, use_markup=true, wrap=true,
                            label = "<span size='small'><i>" .. spell_tooltip(spell) .. "</i></span>" }},
                }}
            }}})
    end
    return rows_grid
end

-- Builds the spell-picker dialog for a single view (1 = grid, 2 = list): a
-- title, a button that switches to the OTHER view, the chosen view's content,
-- and a Cancel button.
--
-- Both views are never built into the same dialog. An earlier version put
-- both into a [stacked_widget] and toggled its active layer in place, but
-- gui2::stacked_widget only searches its currently-active layer unless
-- find_in_all_layers_ is set (stacked_widget.cpp), and that flag has no Lua
-- binding (only a C++ setter, used by core dialogs like preferences/mp_create_game).
-- So widgets in the inactive layer could never be found/wired from Lua. Closing
-- and reopening the dialog with the other view sidesteps that entirely, at the
-- cost of a brief flicker when toggling.
-- Neither view's content has an intrinsic height limit, so its best size is
-- the full height of every row stacked up (free-assign mode lists ~49 spells,
-- 9 rows even in the 6-wide grid) and the dialog grows to fit -- nearly the
-- whole screen. [size_lock] forces a fixed size on its single child
-- (size_lock.cpp: calculate_best_size always returns exactly width x height,
-- content-size is not consulted), so each view is locked to the same sensible
-- height and scrolls the rest, the same way GUI_FORCE_WIDGET_SIZE locks widget
-- sizes elsewhere in core Wesnoth. Width is tuned per view (grid's rows are
-- much narrower than list's, and since size_lock fixes width unconditionally
-- too, sharing one value would either starve the list's description column or
-- stretch the grid wider than its content needs). Both use screen-relative
-- formulas (same mechanism already used in this addon by
-- journey_ui.lua/outro_teaser.lua) capped with an absolute pixel ceiling so
-- the box neither overflows small screens nor balloons on huge ones.
local PICKER_HEIGHT     = "(min(700, screen_height * 65 / 100))"
local PICKER_GRID_WIDTH = "(min(650, screen_width * 35 / 100))"
local PICKER_LIST_WIDTH = "(min(900, screen_width * 45 / 100))"

-- Wraps any picker content grid in a scrollbar_panel locked to PICKER_HEIGHT
-- tall by `width` wide, so it scrolls internally instead of growing the dialog.
local function wrap_scrollable(inner_grid, width, h_grow)
    local inner_col = h_grow
        and T.column{ horizontal_grow=true, vertical_alignment="top", inner_grid }
        or  T.column{ horizontal_alignment="center", vertical_alignment="top", inner_grid }
    return T.grid{ T.row{ T.column{ horizontal_grow=true, vertical_grow=true,
        T.size_lock{ width = width, height = PICKER_HEIGHT,
            T.widget{
                T.scrollbar_panel{ vertical_scrollbar_mode="initial_auto", horizontal_scrollbar_mode="never",
                    T.definition{ T.row{ inner_col }}
                }}
        }}}}
end

local function build_picker_layout(spells, view)
    local content = (view == 1)
        and wrap_scrollable(build_picker_grid(spells), PICKER_GRID_WIDTH, false)
        or  wrap_scrollable(build_picker_list(spells), PICKER_LIST_WIDTH, true)

    local grid = T.grid{}
    table.insert(grid[2], T.row{ T.column{ border="all", border_size=10,
        T.label{ definition="title", horizontal_alignment="center",
            label = _"Choose a Spell" }}})
    table.insert(grid[2], T.row{ T.column{ horizontal_alignment="right", border="all", border_size=4,
        T.button{ id="picker_view_toggle", use_markup=true,
            label = (view == 1) and _"List View" or _"Grid View" }}})
    table.insert(grid[2], T.row{ T.column{ border="all", border_size=8, content }})
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

    -- Loops on view-toggle: the toggle button closes this dialog and the loop
    -- reopens it built for the other view, rather than switching views in place
    -- (see build_picker_layout's comment for why in-place switching can't work).
    while true do
        local view = picker_view
        local prefix     = (view == 1) and "pick"      or "pick_list"
        local img_prefix  = (view == 1) and "pick_img"  or "pick_list_img"
        local name_prefix = (view == 1) and "pick_name" or "pick_list_name"

        local layout = build_picker_layout(spells, view)
        local chosen = nil
        local switch_view = false

        gui.show_dialog(layout, function(dlg)
            local toggle = dlg["picker_view_toggle"]
            if toggle then
                toggle.on_button_click = function()
                    switch_view = true
                    gui.widget.close(dlg)
                end
            end

            for idx, spell in ipairs(spells) do
                local cell = dlg[prefix .. idx]
                if cell then
                    if used[spell.id] then
                        -- Already chosen in another slot: block it and make the
                        -- "taken" state obvious — greyed-out image + struck-through name.
                        cell.enabled = false
                        local img = dlg[img_prefix .. idx]
                        if img then img.label = spell.image .. "~GS()~O(0.4)" end
                        local nm = dlg[name_prefix .. idx]
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

        if switch_view then
            picker_view = (view == 1) and 2 or 1
        else
            return chosen
        end
    end
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
-- Slot count is normally the caster's number of groups, but an explicit
-- free_slots overrides it (the magic modification sets the slot count from a
-- game setting, for casters that start with no groups at all), and if neither is
-- present it falls back to a sensible number so free-assign always shows usable
-- slots and can rebuild the caster from scratch.
local function prepare_free_slots(caster_data)
    local keys = {}
    for i in pairs(caster_data.groups) do table.insert(keys, i) end
    table.sort(keys)

    local count = tonumber(caster_data.free_slots) or #keys
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
                            T.column{ horizontal_alignment="left",
                                T.button{ id=sub.id, use_markup=true, label=sub_label }})
                    end
                end
            else
                button = T.label{ id="button"..i } -- invisible placeholder
            end
        end

        -- Main row: button | spacer | image | spacer | description label
        -- The description is a rich_label, not a label: it is the one place the
        -- <ref dst='...'> links in table.lua are rendered as links into the help
        -- browser (a plain label goes straight to Pango, which does not know the
        -- tag). width=0 means "do not wrap", as in TDG's own spell dialog.
        table.insert(skill_grid[2], T.row{
            T.column{ border="left",  border_size=15, button },
            T.column{ T.label{ label="  " }},
            T.column{ horizontal_alignment="left", T.image{ id="image"..i }},
            T.column{ border="right", border_size=15, T.label{ label="  " }},
            T.column{ horizontal_alignment="left", T.rich_label{ id="label"..i, width=0 }},
        })

        -- Subskill row (only in cast mode). Left-aligned, not centred: the rows
        -- hold different numbers of buttons of different widths, and a centred
        -- grid starts each one at its own offset, so the columns of buttons never
        -- line up between one spell and the next.
        if subskill_row then
            table.insert(skill_grid[2], T.row{
                T.column{ T.label{} }, T.column{ T.label{} },
                T.column{ T.label{} }, T.column{ T.label{} },
                T.column{ horizontal_alignment="left", T.grid{ subskill_row }},
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
        local desc = describe(def)

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
            -- rich_label, like the per-group rows above: the slot description is
            -- outside the clickable panel, so its <ref> links can be followed
            -- without stealing the click that opens the picker.
            T.column{ horizontal_alignment="left",
                T.rich_label{ id="slot_desc" .. i, width=0, label=desc }},
        })

        -- Spacer row.
        table.insert(skill_grid[2], T.row{
            T.column{ T.label{ label="  " }},
            T.column{ T.label{} }, T.column{ T.label{} },
        })
    end

    return skill_grid
end

-- The gear's dialog. Local and side-effect free: it only collects values, and
-- the synced command mod.lua registers is what actually writes them, so every
-- client ends up with the same settings.
local function open_mod_settings()
    local chosen = {}

    local rows = { T.row{ T.column{ border="all", border_size=8,
        T.label{ definition="title", label=_"Magic System Settings" }}} }

    for i, opt in ipairs(MOD_LIVE_OPTIONS) do
        if opt.kind == "choice" then
            table.insert(rows, T.row{ T.column{ border="left,top", border_size=10,
                horizontal_alignment="left", T.label{ label=opt.label }}})
            for k, label in ipairs(opt.labels) do
                table.insert(rows, T.row{ T.column{ border="left", border_size=25,
                    horizontal_alignment="left",
                    T.toggle_button{ id="opt"..i.."_"..k, definition="radio", label=label }}})
            end
        elseif opt.kind == "bool" then
            table.insert(rows, T.row{ T.column{ border="all", border_size=6,
                horizontal_alignment="left",
                T.toggle_button{ id="opt"..i, label=opt.label }}})
        else
            -- The slider prints its own value, so there is no separate number
            -- label. [value_labels] is how the top stop of "casters per side"
            -- can read "unlimited"; the engine requires exactly one label per
            -- step (slider.cpp: the count is validated).
            local slider = { id="opt"..i, minimum_value=opt.min, maximum_value=opt.max, step_size=1 }
            if opt.kind == "limit" then
                local labels = {}
                for v = opt.min, opt.max do
                    table.insert(labels, T.label{ label = (v == opt.max) and _"unlimited" or tostring(v) })
                end
                table.insert(slider, T.value_labels(labels))
            end

            table.insert(rows, T.row{ T.column{ border="all", border_size=6,
                horizontal_alignment="left", T.grid{ T.row{
                    T.column{ border="right", border_size=8, horizontal_alignment="left",
                        T.label{ label=opt.label }},
                    T.column{ horizontal_alignment="left", T.slider(slider) },
                }}}})
        end
    end

    table.insert(rows, T.row{ T.column{ border="all", border_size=8, T.grid{ T.row{
        T.column{ border="right", border_size=10, T.button{ id="ok",     return_value=1, label=_"OK" }},
        T.column{                                 T.button{ id="cancel", return_value=2, label=_"Cancel" }},
    }}}})

    local grid = T.grid{}
    for _, r in ipairs(rows) do table.insert(grid[2], r) end
    local dialog = { T.tooltip{ id="tooltip_large" }, T.helptip{ id="tooltip_large" }, grid }

    local rv = gui.show_dialog(dialog, function(dlg)
        for i, opt in ipairs(MOD_LIVE_OPTIONS) do
            local value = mod_option(opt)
            if opt.kind == "bool" then
                dlg["opt"..i].selected = value and true or false
            elseif opt.kind == "limit" then
                dlg["opt"..i].value = (value == "unlimited") and opt.max
                    or math.min(opt.max - 1, math.max(opt.min, tonumber(value) or 3))
            elseif opt.kind == "number" then
                dlg["opt"..i].value = value
            else
                for k, v in ipairs(opt.values) do
                    local button = dlg["opt"..i.."_"..k]
                    button.selected = (v == value)
                    -- Radio buttons are independent toggles in GUI2; clearing the
                    -- others by hand is what makes the group behave like a group.
                    button.on_modified = function()
                        if not button.selected then button.selected = true return end
                        for other = 1, #opt.values do
                            if other ~= k then dlg["opt"..i.."_"..other].selected = false end
                        end
                    end
                end
            end
        end
    end, function(dlg)
        for i, opt in ipairs(MOD_LIVE_OPTIONS) do
            if opt.kind == "bool" then
                chosen[opt.id] = dlg["opt"..i].selected and "yes" or "no"
            elseif opt.kind == "number" then
                chosen[opt.id] = dlg["opt"..i].value
            elseif opt.kind == "limit" then
                local v = dlg["opt"..i].value
                chosen[opt.id] = (v >= opt.max) and "unlimited" or tostring(v)
            else
                chosen[opt.id] = opt.values[1]
                for k, v in ipairs(opt.values) do
                    if dlg["opt"..i.."_"..k].selected then chosen[opt.id] = v end
                end
            end
        end
    end)

    if rv == 1 and next(chosen) then
        wesnoth.sync.invoke_command("magic_mod_settings", chosen)
    end
end

local function build_footer(caster, caster_data, selecting)
    if selecting then
        -- No return_value: on_button_click handlers in make_preshow close the dialog
        -- and call invoke_command from inside the click (required for MP sync).
        return T.row{ T.column{ T.grid{ T.row{
            T.column{ border="top,right", border_size=10,
                T.button{ id="confirm_button", use_markup=true,
                    tooltip=_"Your spells can be changed every scenario.\nConfirm is unavailable until you pick an unlocked spell in every group.",
                    label=_"Confirm Spells" }},
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

    local show_settings = mod_settings_allowed()

    if show_advance or show_reselect or show_counter or show_settings then
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

        if show_settings then
            table.insert(upgrade_row[2], T.column{
                border="left", border_size=10, grow_factor=0, horizontal_alignment="right",
                T.button{ id="mod_settings_button", use_markup=true, return_value=5,
                    tooltip=_"Change the magic system's settings for this game.",
                    label="<span size='large'>⚙</span>" }})
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
                    dlg["slot_desc" .. i].label = describe(def)
                    make_links_clickable(dlg["slot_desc" .. i])
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

        -- Any label swapped onto a button at this point must carry its own side
        -- padding, exactly like locked_subskill_label() and the subskill labels in
        -- table.lua do. This button gives its text almost no horizontal padding of
        -- its own, so an unpadded replacement loses its last characters: "No Gold"
        -- renders as "No Go", and "Locked" used to render as "Locke" before it was
        -- padded at build time. The padding is part of the label, so the button
        -- sizes to it and the whole string fits.
        local function small_label(text)
            local body = small and ("<span size='small'>" .. text .. "</span>") or text
            return "   " .. body .. "   "
        end

        -- Active toggle: show Cancel if the object is already applied.
        if has_object(spell.id) then
            btn.label = small_label(_"Cancel")
            btn.on_button_click = function()
                -- Set current_caster on ALL clients before the cancel event fires.
                wesnoth.sync.invoke_command("magic_set_caster", { id = caster.id })
                wml.variables[CasterState.key(caster.id) .. ".spell_to_cast"] = spell.id .. "_cancel"
                gui.widget.close(dlg)
            end
            return
        end

        -- Blocking conditions (ordered by priority).
        local max_casts    = caster_data.max_casts or 1
        local casts_done   = caster_data.casts_this_turn or 0
        local free_casting = caster_data.free_casting == true
        local blocked_label
        if not caster_data.unlocked_set[spell.id] then
            -- Locked subskill: hide its real name/cost so an un-earned upgrade
            -- isn't spoiled — show a neutral "Locked" tag instead. (Main equipped
            -- spells are always unlocked, so in practice this only hits subskills.)
            -- Uses the same padded label as build time, so the width already fits.
            if small then btn.label = locked_subskill_label() end
            btn.enabled = false; return
        elseif casts_done >= max_casts then
            -- The cap comes from caster_data, so a caster with the multi-cast upgrade
            -- shows its real limit ("2 spells/turn") instead of a hardcoded one.
            -- Padded on both sides, same as small_label above: an unpadded label
            -- loses its last characters on these buttons.
            blocked_label = "   <span>" .. ((max_casts == 1)
                and tostring(_"1 spell/turn")
                or  (max_casts .. " " .. _"spells/turn")) .. "</span>   "
        elseif caster_data.polymorphed then
            blocked_label = _"<span>  Blocked by\n  Polymorph</span>"
        elseif wesnoth.units.find_on_map{
            id=caster.id,
            wml.tag.filter_location{ radius=3, wml.tag.filter{ id="Haralin_mirror3" }}
        }[1] then
            blocked_label = _"<span>  Blocked by\n Counterspell</span>"
        elseif wml.variables["counterspell_active"] then
            blocked_label = _"<span>  Blocked by\n Counterspell</span>"
        -- A free-casting caster pays nothing, so none of the affordability checks
        -- below may block it (the spell's printed cost is still shown — it just
        -- isn't charged).
        elseif free_casting then
            -- no cost gate
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
                -- Free casting still goes through spellcasting_cost, with every
                -- cost dropped: the per-turn counter must be incremented (and
                -- synced) exactly the same way.
                xp_cost         = (not free_casting) and spell.xp_cost   or nil,
                hp_cost         = (not free_casting) and spell.hp_cost   or nil,
                gold_cost       = (not free_casting) and spell.gold_cost or nil,
                atk_cost        = (not free_casting) and spell.atk_cost  or nil,
                casts_increment = true, -- increment synced counter (multi-cast tracking)
            })
            -- Set current_caster on ALL clients from inside the button click.
            -- invoke_command is only valid inside show_dialog button handlers in MP.
            wesnoth.sync.invoke_command("magic_set_caster", { id = caster.id })
            wml.variables[CasterState.key(caster.id) .. ".spell_to_cast"] = spell.id
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
                        dlg["label"..i].label = describe(sel)
                        make_links_clickable(dlg["label"..i])
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
                    dlg["label"..i].label    = describe(equipped_spell)
                    make_links_clickable(dlg["label"..i])
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
                    wml.variables[CasterState.key(caster.id) .. ".spell_to_cast"] = "advance_caster"
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

    -- Descriptions may depend on the caster (level, unlocked subskills, its name),
    -- so the context is set before anything below builds a description. The name
    -- is the displayed one, falling back to the id for a caster without one.
    desc_ctx = {
        level    = caster.level or 1,
        unlocked = caster_data.unlocked_set or {},
        name     = tostring(caster.name ~= nil and caster.name ~= "" and caster.name or caster.id),
    }

    -- Every read below happens AFTER the dialog closed, and the cast fired from it may
    -- have replaced the unit — polymorph swaps in a whole new unit — which leaves this
    -- proxy dangling ("bad argument #1 to 'index' (unit not found)"). The id is stable
    -- across that swap, so capture it now, while the unit is definitely still there.
    local caster_id = caster.id

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
    --wesnoth.interface.delay(300)
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
                wml.variables[CasterState.key(caster_id) .. ".requested_reselect"] = true
                return
            end

            if rv == 5 then
                open_mod_settings()
                return
            end

            local spell_to_cast = wml.variables[CasterState.key(caster_id) .. ".spell_to_cast"]
            if spell_to_cast then
                wml.variables["is_badly_timed"] = true
                -- Set current_caster INSIDE do_command so it's synced atomically with fire_event.
                -- invoke_command("magic_set_caster") from show_dialog button handlers may arrive
                -- on non-active clients AFTER the do_command packet, causing a race condition.
                --
                -- [set_variable] is NOT in [do_command]'s allowed_tags (only "attack", "move",
                -- "recruit", "recall", "disband", "fire_event", "custom_command" — see
                -- src/game_events/action_wml.cpp's do_command handler), so a bare set_variable
                -- child here is silently dropped (logged as "unsupported tag", never applied).
                -- Use a [custom_command] child instead — same shape intf_invoke_synced_command
                -- builds for wesnoth.sync.invoke_command — so current_caster is set by the same
                -- in-order replay command that fires the spell event, not a separate packet.
                -- The _pre/_post hooks travel inside the SAME do_command as the spell
                -- event itself, so all three arrive in this order on every client
                -- (see magic_fire_spell_event in core.lua for the Lua-side casts).
                wml.fire.do_command({
                    wml.tag.custom_command{
                        name = "magic_set_caster",
                        wml.tag.data{ id = caster_id },
                    },
                    wml.tag.fire_event{ raise = spell_to_cast .. "_pre" },
                    wml.tag.fire_event{ raise = spell_to_cast },
                    wml.tag.fire_event{ raise = spell_to_cast .. "_post" },
                })
                wml.variables[CasterState.key(caster_id) .. ".spell_to_cast"] = nil
                wml.variables["is_badly_timed"] = nil
            end
        end)
    end

    -- Check if the user clicked "Change Spells" (free-reselect upgrade).
    local reselect = wml.variables[CasterState.key(caster_id) .. ".requested_reselect"] == true
    if reselect then
        wml.variables[CasterState.key(caster_id) .. ".requested_reselect"] = nil
    end
    return reselect
end

---------------------------------------------------------------------------
-- Module init: inject spell_data dependency to avoid circular require.
---------------------------------------------------------------------------

function M.init(sd)
    spell_data = sd
end

M.open_dialog = open_dialog

return M
