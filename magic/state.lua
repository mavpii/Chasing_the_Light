-- state.lua
-- Magic System — Layer 1: State
-- Responsible for reading/writing caster state from/to WML variables.
-- WML variables are the single source of truth for multiplayer sync.
-- This module never fires events, never touches units directly.

local CasterState = {}

---------------------------------------------------------------------------
-- Private helpers
---------------------------------------------------------------------------

local function parse_list(str)
    local t = {}
    for raw in (str or ""):gmatch("[^,]+") do
        -- Trim surrounding whitespace so " skill_x" (from comma-lists written
        -- with spaces in scenario configs) matches the clean "skill_x" id.
        local item = raw:match("^%s*(.-)%s*$")
        if item ~= "" then table.insert(t, item) end
    end
    return t
end

local function list_to_set(list)
    local set = {}
    for _, v in ipairs(list) do set[v] = true end
    return set
end

---------------------------------------------------------------------------
-- Public API
---------------------------------------------------------------------------

-- Returns true if a caster with this unit ID has been registered.
function CasterState.exists(unit_id)
    return wml.variables["caster_" .. unit_id] ~= nil
end

-- Loads caster state from WML variables into a Lua table.
-- Returns nil if the caster does not exist.
function CasterState.load(unit_id)
    local prefix = "caster_" .. unit_id
    if not wml.variables[prefix] then return nil end

    local unlocked_list = parse_list(wml.variables[prefix .. ".spell_unlocked"])
    local equipped_list = parse_list(wml.variables[prefix .. ".spell_equipped"])

    local groups = {}
    local gi = 1
    while wml.variables[prefix .. ".spell_group_" .. gi] do
        groups[gi] = parse_list(wml.variables[prefix .. ".spell_group_" .. gi])
        gi = gi + 1
    end

    -- Normalize the "wait to select" flag. It is stored as the string "yes", but
    -- Wesnoth coerces boolean-like attribute values ("yes"/"no") to Lua booleans
    -- on read, so wml.variables returns `true` here, not "yes". Collapse both forms
    -- to a consistent "yes"/nil so downstream `== "yes"` checks (open_for_unit) work.
    local wts = wml.variables[prefix .. ".wait_to_select_spells"]
    local wait_to_select = (wts == "yes" or wts == true) and "yes" or nil

    return {
        id            = unit_id,
        title_select  = wml.variables[prefix .. ".u_title_select"],
        title_cast    = wml.variables[prefix .. ".u_title_cast"],
        description   = wml.variables[prefix .. ".u_description"],

        unlocked      = unlocked_list,
        unlocked_set  = list_to_set(unlocked_list), -- O(1) lookup

        equipped      = equipped_list,
        equipped_set  = list_to_set(equipped_list), -- O(1) lookup

        groups        = groups, -- groups[i] = { spell_id, ... }

        spellcasting_disabled = wml.variables[prefix .. ".utils_spellcasting_allowed"] == "disabled",
        advancement_disabled  = wml.variables[prefix .. ".utils_advancement_allowed"]  == "disabled",
        spellcasted_this_turn = wml.variables[prefix .. ".spellcasted_this_turn"],
        polymorphed           = wml.variables[prefix .. ".polymorphed"],
        wait_to_select        = wait_to_select,

        -- Upgrade: free spell reselect at any time.
        reselect_free   = wml.variables[prefix .. ".reselect_free"] == true,
        -- Upgrade: multi-cast (how many spells can be cast per turn).
        max_casts       = tonumber(wml.variables[prefix .. ".max_casts"]) or 1,
        casts_this_turn = tonumber(wml.variables[prefix .. ".casts_this_turn"]) or 0,
        -- Upgrade: free assign (pick any spell into any slot from a picker grid).
        free_assign     = wml.variables[prefix .. ".free_assign"] == true,
        -- Upgrade: free pick — same picker UI as free assign, but the grid is
        -- restricted to the caster's UNLOCKED spells only.
        free_unlocked   = wml.variables[prefix .. ".free_unlocked"] == true,
    }
end

-- Writes a caster data table back to WML variables.
function CasterState.save(data)
    local prefix = "caster_" .. data.id

    wml.variables[prefix]                  = true
    wml.variables[prefix .. ".u_title_select"] = data.title_select
    wml.variables[prefix .. ".u_title_cast"]   = data.title_cast
    wml.variables[prefix .. ".u_description"]  = data.description
    wml.variables[prefix .. ".spell_unlocked"] = table.concat(data.unlocked, ",")
    wml.variables[prefix .. ".spell_equipped"] = table.concat(data.equipped, ",")

    -- Write every group, and clear any stale group variables left over from a
    -- previous (larger) group count. Scans until both data and WML run out.
    local gi = 1
    while data.groups[gi] or wml.variables[prefix .. ".spell_group_" .. gi] do
        local key = prefix .. ".spell_group_" .. gi
        if data.groups[gi] then
            wml.variables[key] = table.concat(data.groups[gi], ",")
        else
            wml.variables[key] = nil
        end
        gi = gi + 1
    end

    wml.variables[prefix .. ".utils_spellcasting_allowed"] = data.spellcasting_disabled and "disabled" or nil
    wml.variables[prefix .. ".utils_advancement_allowed"]  = data.advancement_disabled  and "disabled" or nil
    wml.variables[prefix .. ".spellcasted_this_turn"]      = data.spellcasted_this_turn
    wml.variables[prefix .. ".polymorphed"]                = data.polymorphed
    wml.variables[prefix .. ".wait_to_select_spells"]      = data.wait_to_select

    wml.variables[prefix .. ".reselect_free"]   = data.reselect_free and true or nil
    wml.variables[prefix .. ".max_casts"]       = (data.max_casts ~= nil and data.max_casts > 1) and data.max_casts or nil
    wml.variables[prefix .. ".casts_this_turn"] = (data.casts_this_turn ~= nil and data.casts_this_turn > 0) and data.casts_this_turn or nil
    wml.variables[prefix .. ".free_assign"]     = data.free_assign and true or nil
    wml.variables[prefix .. ".free_unlocked"]   = data.free_unlocked and true or nil
end

-- Removes all WML variables for this caster.
function CasterState.delete(unit_id)
    wml.variables["caster_" .. unit_id] = nil
end

-- Builds a new caster data table from a unit and an [assign_caster] config.
-- Does not write to WML — caller must call CasterState.save() afterwards.
function CasterState.from_config(unit, cfg)
    local pronoun = (unit.gender == "male") and "he" or "she"
    local default_desc = unit.name
        .. " knows many useful spells, and will learn more as " .. pronoun
        .. " levels-up automatically throughout the campaign. " .. unit.name
        .. " does not use XP to level-up. Instead,\n" .. pronoun
        .. " uses XP to cast certain spells. If you select spells that cost XP,"
        .. " <b>double-click on " .. unit.name .. " to cast them</b>."

    local groups = {}
    local gi = 1
    while cfg["spell_group_" .. gi] do
        groups[gi] = parse_list(cfg["spell_group_" .. gi])
        gi = gi + 1
    end

    local unlocked_list = parse_list(cfg.unlocked_spells or "")
    local equipped_list = parse_list(cfg.equipped_spells or "")

    return {
        id            = unit.id,
        title_select  = cfg.title_select or ("Select " .. unit.name .. "'s Spells"),
        title_cast    = cfg.title_cast   or ("Cast "   .. unit.name .. "'s Spells"),
        description   = cfg.description  or default_desc,

        unlocked      = unlocked_list,
        unlocked_set  = list_to_set(unlocked_list),

        equipped      = equipped_list,
        equipped_set  = list_to_set(equipped_list),

        groups        = groups,

        spellcasting_disabled = (cfg.spellcasting_allowed == false),
        advancement_disabled  = false,
        spellcasted_this_turn = nil,
        polymorphed           = nil,
        wait_to_select        = nil,

        reselect_free   = false,
        max_casts       = 1,
        casts_this_turn = 0,
        free_assign     = (cfg.free_assign == true),
        free_unlocked   = (cfg.free_unlocked == true),
    }
end

return CasterState
