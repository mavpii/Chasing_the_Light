--
-- Wesnoth Journey Log module (read-only achievements)
--

local groups = {}
local have_achievements = false

function journeylog.have_achievements()
    return have_achievements
end

-- Реєстрація груп і ID досягнень (без прогресу!)
local function register_achievement_group(cfg)
    local id = cfg.content_for
    local name = cfg.display_name

    if groups[id] == nil then
        groups[id] = {
            name = name,
            achievements = {}
        }
    end

    for ach in wml.child_range(cfg, "achievement") do
        have_achievements = true
        table.insert(groups[id].achievements, ach.id)
    end
end

function journeylog.register_achievements(cfg)
    for group_cfg in wml.child_range(cfg, "achievement_group") do
        register_achievement_group(group_cfg)
    end
end

-- Отримання одного досягнення (тільки через рушій!)
local function enumerate_achievement_impl(group_id, achievement_id)
    local cfg = wesnoth.achievements.get(group_id, achievement_id)
    local completed = wesnoth.achievements.has(group_id, achievement_id)

    local progress = nil
    if (tonumber(cfg.max_progress or 0) or 0) > 0 then
        -- ВАЖЛИВО: це рідний виклик рушія
        progress = wesnoth.achievements.progress(group_id, achievement_id, 0, 0)
    end

    local function maybe_complete(attr)
        if completed then
            return cfg[attr .. "_completed"]
        else
            return cfg[attr]
        end
    end

    local name = maybe_complete("name") or "<unknown>"
    local description = maybe_complete("description") or "<unknown>"
    local icon = maybe_complete("icon")

    if not icon or icon == "" or icon == "~GS()" then
        icon = "attacks/blank-attack.png"
    end

    return {
        id               = achievement_id,
        name             = name,
        description      = description,
        icon             = icon,
        hidden           = cfg.hidden or false,
        current_progress = progress,
        max_progress     = cfg.max_progress,
        completed        = completed,
    }
end

-- Публічний список всіх досягнень
function journeylog.enumerate_achievements()
    local res = {}

    for group_id, group in pairs(groups) do
        for _, ach_id in ipairs(group.achievements) do
            table.insert(res, enumerate_achievement_impl(group_id, ach_id))
        end
    end

    return res
end