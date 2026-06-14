-- ops.lua
-- Magic System — Layer 2: Operations
-- Pure functions that operate on caster data tables loaded by state.lua.
-- No WML access, no side effects, no unit lookups.
-- Every function takes a data table (from CasterState.load) and mutates it in place.
-- Caller is responsible for calling CasterState.save() afterwards.

local CasterOps = {}

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

-- Returns true when the caster still has casts left this turn.
function CasterOps.can_cast(data)
    return (data.casts_this_turn or 0) < (data.max_casts or 1)
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
        local list = {}
        for s in cfg.unlocked_spells:gmatch("[^,]+") do table.insert(list, s) end
        data.unlocked     = list
        data.unlocked_set = {}
        for _, s in ipairs(list) do data.unlocked_set[s] = true end
    end

    if cfg.equipped_spells then
        local list = {}
        for s in cfg.equipped_spells:gmatch("[^,]+") do table.insert(list, s) end
        data.equipped     = list
        data.equipped_set = {}
        for _, s in ipairs(list) do data.equipped_set[s] = true end
    end

    for i = 1, 10 do
        if cfg["spell_group_" .. i] then
            local group = {}
            for s in cfg["spell_group_" .. i]:gmatch("[^,]+") do
                table.insert(group, s)
            end
            data.groups[i] = group
        end
    end

    if cfg.spellcasting_allowed ~= nil then
        data.spellcasting_disabled = (cfg.spellcasting_allowed == false)
    end
end

return CasterOps
