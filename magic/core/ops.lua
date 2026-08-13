-- ops.lua
-- Magic System — Layer 2: Operations
-- Pure functions that operate on caster data tables loaded by state.lua.
-- No WML access, no side effects, no unit lookups.
-- Every function takes a data table (from CasterState.load) and mutates it in place.
-- Caller is responsible for calling CasterState.save() afterwards.

local CasterOps = {}

-- Splits a comma-separated WML list into trimmed, non-empty ids.
-- Trimming is essential: scenario configs write lists with spaces after
-- commas ("a, b, c"), and untrimmed ids never match the clean catalogue ids.
local function parse_list(str)
    local t = {}
    for raw in (str or ""):gmatch("[^,]+") do
        local item = raw:match("^%s*(.-)%s*$")
        if item ~= "" then table.insert(t, item) end
    end
    return t
end

---------------------------------------------------------------------------
-- Spell group queries
---------------------------------------------------------------------------

-- Returns the group index that contains spell_id, or nil.
function CasterOps.find_group(data, spell_id)
    for i, group in pairs(data.groups) do
        for _, s in ipairs(group) do
            if s == spell_id then return i end
        end
    end
    return nil
end

-- Returns true if spell_id is in any of the caster's groups.
function CasterOps.in_groups(data, spell_id)
    return CasterOps.find_group(data, spell_id) ~= nil
end

---------------------------------------------------------------------------
-- Unlock / Lock
---------------------------------------------------------------------------

-- Unlocks a spell. Idempotent.
function CasterOps.unlock(data, spell_id)
    if not data.unlocked_set[spell_id] then
        table.insert(data.unlocked, spell_id)
        data.unlocked_set[spell_id] = true
    end
end

-- Locks a spell and unequips it if currently equipped. Idempotent.
function CasterOps.lock(data, spell_id)
    if not data.unlocked_set[spell_id] then return end

    for i = #data.unlocked, 1, -1 do
        if data.unlocked[i] == spell_id then
            table.remove(data.unlocked, i)
        end
    end
    data.unlocked_set[spell_id] = nil

    CasterOps.unequip(data, spell_id)
end

---------------------------------------------------------------------------
-- Equip / Unequip
---------------------------------------------------------------------------

-- Equips a spell, replacing whatever was previously equipped from the same group.
-- Does nothing if spell_id is not in any group.
function CasterOps.equip(data, spell_id)
    local group_idx = CasterOps.find_group(data, spell_id)
    if not group_idx then return end

    -- Build a fast lookup set for the target group.
    local same_group = {}
    for _, s in ipairs(data.groups[group_idx]) do same_group[s] = true end

    -- Remove any spell from the same group, then append the new one.
    local new_equipped = {}
    for _, s in ipairs(data.equipped) do
        if not same_group[s] then table.insert(new_equipped, s) end
    end
    table.insert(new_equipped, spell_id)

    data.equipped = new_equipped
    data.equipped_set = {}
    for _, s in ipairs(data.equipped) do data.equipped_set[s] = true end
end

-- Unequips a spell. Idempotent.
function CasterOps.unequip(data, spell_id)
    if not data.equipped_set[spell_id] then return end

    local new_equipped = {}
    for _, s in ipairs(data.equipped) do
        if s ~= spell_id then table.insert(new_equipped, s) end
    end
    data.equipped     = new_equipped
    data.equipped_set[spell_id] = nil
end

---------------------------------------------------------------------------
-- Queries (read-only)
---------------------------------------------------------------------------

function CasterOps.is_equipped(data, spell_id)
    return data.equipped_set[spell_id] == true
end

function CasterOps.is_unlocked(data, spell_id)
    return data.unlocked_set[spell_id] == true
end

---------------------------------------------------------------------------
-- Flags
---------------------------------------------------------------------------

function CasterOps.set_spellcasting(data, enabled)
    data.spellcasting_disabled = not enabled
end

function CasterOps.set_advancement(data, enabled)
    data.advancement_disabled = not enabled
end

-- Enable or disable free spell reselect at any time.
function CasterOps.set_reselect(data, enabled)
    data.reselect_free = enabled == true
end

-- Set maximum spell casts per turn (minimum 1).
function CasterOps.set_max_casts(data, n)
    data.max_casts = math.max(1, math.floor(tonumber(n) or 1))
end

-- Gives back casts already spent this turn. With no amount, fully restores
-- (back to 0 spent). With an amount, gives back only that many -- floored at
-- 0 spent, so it can never grant casts beyond what was actually used.
function CasterOps.restore_casts(data, amount)
    if amount == nil then
        data.casts_this_turn = 0
        return
    end
    local n = math.max(0, math.floor(tonumber(amount) or 0))
    data.casts_this_turn = math.max(0, (data.casts_this_turn or 0) - n)
end

-- Enable or disable free-assign mode (any spell into any slot).
function CasterOps.set_free_assign(data, enabled)
    data.free_assign = enabled == true
end

-- Enable or disable free-pick mode: same picker UI as free-assign, but the grid
-- is restricted to spells the caster has already unlocked.
function CasterOps.set_free_unlocked(data, enabled)
    data.free_unlocked = enabled == true
end

-- Fixes how many slots the free-assign / free-pick picker offers. nil or 0 goes
-- back to deriving the count from the caster's groups (the default).
function CasterOps.set_free_slots(data, n)
    local v = math.floor(tonumber(n) or 0)
    data.free_slots = v > 0 and v or nil
end

-- Enable or disable free casting: spells cost nothing and are never blocked for
-- lack of XP/HP/gold/attacks.
function CasterOps.set_free_casting(data, enabled)
    data.free_casting = enabled == true
end

-- Enable or disable normal unit advancement for this caster. Casters are frozen
-- one XP below their advancement threshold by default (XP is spell fuel, not
-- levels); enabling this lets the unit level up like any other.
function CasterOps.set_leveling(data, enabled)
    data.levels_normally = enabled == true
end

-- Free-assign: rebuild the caster's slots from an ordered list of spell ids
-- (one id per slot). Each slot becomes a one-spell group containing the chosen
-- spell, the spell is unlocked (so it is castable), and the equipped list is
-- rebuilt to match. This keeps cast mode and refresh_skills working unchanged,
-- since they read groups/equipped/unlocked exactly as before.
function CasterOps.assign_free(data, slot_spells)
    -- Preserve the original multi-spell group pools the FIRST time free mode
    -- rebuilds them into one-spell slots, so leaving free mode can restore the
    -- full per-group menus instead of leaving only the chosen spells behind.
    if data.groups_backup == nil then
        local backup = {}
        for i, g in pairs(data.groups) do
            local copy = {}
            for _, s in ipairs(g) do copy[#copy + 1] = s end
            backup[i] = copy
        end
        data.groups_backup = backup
    end

    data.groups       = {}
    data.equipped     = {}
    data.equipped_set = {}
    for i, spell_id in ipairs(slot_spells) do
        if spell_id and spell_id ~= "" then
            data.groups[i] = { spell_id }
            CasterOps.unlock(data, spell_id)
            if not data.equipped_set[spell_id] then
                table.insert(data.equipped, spell_id)
                data.equipped_set[spell_id] = true
            end
        end
    end
end

-- Restores the original group pools saved by assign_free (when the caster first
-- entered free mode) and rebuilds a valid equipped list from them. Returns true if
-- a restore actually happened. Called when leaving free mode so the normal
-- per-group selection menus come back with all their options.
function CasterOps.restore_groups(data)
    if data.groups_backup == nil then return false end

    data.groups        = data.groups_backup
    data.groups_backup = nil

    -- Re-derive equipped from the restored groups: prefer a spell that is still
    -- equipped, else the first unlocked spell in the group. This keeps cast mode
    -- and the selection defaults valid after the one-spell free groups are dropped.
    local new_eq, new_set = {}, {}
    for _, g in pairs(data.groups) do
        local chosen
        for _, s in ipairs(g) do
            if data.equipped_set[s] then chosen = s; break end
        end
        if not chosen then
            for _, s in ipairs(g) do
                if data.unlocked_set[s] then chosen = s; break end
            end
        end
        if chosen and not new_set[chosen] then
            new_eq[#new_eq + 1] = chosen
            new_set[chosen] = true
        end
    end
    data.equipped     = new_eq
    data.equipped_set = new_set
    return true
end

-- Returns true when the caster still has casts left this turn.
function CasterOps.can_cast(data)
    return (data.casts_this_turn or 0) < (data.max_casts or 1)
end

-- Records that spell_id was cast on `turn` (AI repeat-avoidance scoring only).
function CasterOps.record_cast(data, spell_id, turn)
    data.spell_last_cast = data.spell_last_cast or {}
    data.spell_last_cast[spell_id] = turn
end

-- Utility multiplier in [min_factor, 1]: min_factor the same turn it was cast,
-- ramping linearly back to 1 over `window` turns. 1 if never cast / outside window.
function CasterOps.repeat_factor(data, spell_id, turn, window, min_factor)
    local last = data.spell_last_cast and data.spell_last_cast[spell_id]
    if not last then return 1 end
    local age = turn - last
    if age >= window then return 1 end
    return min_factor + (1 - min_factor) * (age / window)
end

---------------------------------------------------------------------------
-- Bulk update (used by modify_caster)
---------------------------------------------------------------------------

-- Applies non-nil fields from cfg onto an existing data table.
-- Mirrors the logic of assign_caster but only overwrites what is provided.
function CasterOps.apply_config(data, cfg)
    if cfg.title_select then data.title_select = cfg.title_select end
    if cfg.title_cast   then data.title_cast   = cfg.title_cast   end
    if cfg.description  then data.description  = cfg.description  end

    if cfg.unlocked_spells then
        local list = parse_list(cfg.unlocked_spells)
        data.unlocked     = list
        data.unlocked_set = {}
        for _, s in ipairs(list) do data.unlocked_set[s] = true end
    end

    if cfg.equipped_spells then
        local list = parse_list(cfg.equipped_spells)
        data.equipped     = list
        data.equipped_set = {}
        for _, s in ipairs(list) do data.equipped_set[s] = true end
    end

    local gi = 1
    while cfg["spell_group_" .. gi] do
        data.groups[gi] = parse_list(cfg["spell_group_" .. gi])
        gi = gi + 1
    end

    if cfg.spellcasting_allowed ~= nil then
        data.spellcasting_disabled = (cfg.spellcasting_allowed == false)
    end

    if cfg.free_assign ~= nil then
        data.free_assign = (cfg.free_assign == true)
    end

    if cfg.free_unlocked ~= nil then
        data.free_unlocked = (cfg.free_unlocked == true)
    end

    if cfg.free_slots ~= nil then
        CasterOps.set_free_slots(data, cfg.free_slots)
    end

    if cfg.free_casting ~= nil then
        data.free_casting = (cfg.free_casting == true)
    end

    if cfg.levels_normally ~= nil then
        data.levels_normally = (cfg.levels_normally == true)
    end
end

return CasterOps
