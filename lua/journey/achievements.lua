--
-- Wesnoth Journey Log module (back-end)
--
-- codename Naia - Project Ethea phase 1 campaigns shared library
-- Copyright (C) 2026 by Iris Morelle <iris@irydacea.me>
--
-- See COPYING for usage terms.
--
--
--                        *** VERY IMPORTANT NOTE ***
--
-- (Yes, you must read ALL of this if you plan to reuse this code in your own
-- content somehow.)
--
-- This module exists primarily to address a massive shortcoming in Wesnoth
-- 1.18's achievement system regarding progression: achievements which require
-- a certain number goal to be hit can be progressed to 100% during any number
-- of playthroughs, rather than on a single playthrough. For example, an
-- achievement that involves killing 100 units can be fulfilled by repeatedly
-- reloading a single save to kill the same singular unit.
--
-- Another big shortcoming of the achievement system is that while there are
-- APIs to interact with individual achievements, there is no way to enumerate
-- all of them -- we MUST have prior knowledge of achievements to do anything
-- meaningful with them.
--
-- The system implemented here for progressive saves makes it so progress is
-- tracked exclusively in the game state via WML variables until the
-- achievement reaches full progress and is marked as complete; in that case,
-- the game's own achievement table is updated accordingly and any local
-- progress carried by existing saves is completely ignored.
--
-- We patch wesnoth.achievements.progress in order to make this as seamless as
-- possible, without requiring extensive code modifications to e.g. Naia's
-- ACHIEVEMENT:PROGRESS macro. A couple of concerns to be had here:
--
--  * By making achievement information local to saves *depending* on the
--    circumstances, a replay may trigger OOS if the global state of an
--    achievement has changed such that the replay's achievement progress no
--    longer matters.
--
--  * This patch is very much singleplayer-only. I cannot even begint to
--    fathom what would happen if you applied it to multiplayer content, so I
--    strongly advise that you don't. I for one am not planning to use Naia to
--    develop multiplayer content any time soon, and even if I did I'd simply
--    not have achievements, or implement a mechanism to disable this whole
--    system and just roll with Wesnoth's crummy implementation instead.
--

-- Contains achievement group ids mapped to tables; these in turn contain the
-- original achievement ids.
local groups = {}

-- This exists solely because it is possible for the achievements table to not
-- be empty yet contain zero achievements if filled with empty achievement
-- groups.
local have_achievements = false

local ACH_WML_STORE = "__naia_achievements"

function journeylog.have_achievements()
	return have_achievements
end

local function _local_achievement_exists(group_id, ach_id)
	if groups[group_id] then
		for _, id in ipairs(groups[group_id].achievements) do
			if id == ach_id then
				return true
			end
		end
	end

	return false
end

local _WACH_progress = wesnoth.achievements.progress

-- Retrieves the engine version of an achievement's progress state.
local function _eng_achievement_progress(group_id, ach_id)
	return _WACH_progress(group_id, ach_id, 0, 0)
end

--local ACH_CURRENT_PROGRESS = 0
local ACH_MAX_PROGRESS     = 1

-- Retrieves OUR version of an achievement's progress state.
local function _local_achievement_progress(group_id, ach_id, current_or_max)
	if groups[group_id] then
		if _local_achievement_exists(group_id, ach_id) then
			if groups[group_id].progression[ach_id] then
				if current_or_max == ACH_MAX_PROGRESS then
					return groups[group_id].progression[ach_id].max_progress
				else
					return groups[group_id].progression[ach_id].progress
				end
			else
				return 0
			end
		else
			return 0
		end
	else
		return 0
	end
end

local function register_achievement_group(cfg)
	local id = cfg.content_for
	local name = cfg.display_name

	if groups[id] == nil then
		groups[id] = {
			name         = name,
			achievements = {},
			progression  = {},
		}
	end

	for ach in wml.child_range(cfg, "achievement") do
		have_achievements = true
		table.insert(groups[id].achievements, ach.id)

		-- We tend to get an empty string here due to the way Naia's macros
		-- make max_progress a permanent yet optional value. Sigh.
		local max_progress = tonumber(ach.max_progress or 0) or 0

		if max_progress > 0 then
			-- Figure out the current progress by making an engine call
			local live_ach_progress = _eng_achievement_progress(id, ach.id)
			local progress = 0

			if live_ach_progress == -1 or
			   live_ach_progress >= max_progress
			then
				-- Only take the live achievement into account if its progress
				-- is complete. Wesnoth's system can be abused via save
				-- reloading, therefore we don't care about any other values
				-- and expect the player to start at 0 at the beginning of
				-- each playthrough until they complete it for the first time,
				-- which causes the live achievement to be marked as complete
				-- for good!
				progress = max_progress
			end

			groups[id].progression[ach.id] = {
				progress     = progress,
				max_progress = max_progress
			}
		end
	end
end

local function deserialize_ach_prog_state()
	if wml.variables[ACH_WML_STORE] == nil then
		return
	end

	local cfg = wml.variables[ACH_WML_STORE]

	for group_cfg in wml.child_range(cfg, "group") do
		local group_id = group_cfg.id
		if groups[group_id] == nil then
			goto skip_group
		end
		for prog_cfg in wml.child_range(group_cfg, "progress") do
			if _eng_achievement_progress(group_id, prog_cfg.id) == -1 then
				goto skip_prog
			end
			if groups[group_id].progression[prog_cfg.id] == nil then
				goto skip_prog
			end
			groups[group_id].progression[prog_cfg.id].progress = mathx.clamp(prog_cfg.progress, 0, groups[group_id].progression[prog_cfg.id].max_progress)
			::skip_prog::
		end
		::skip_group::
	end
end

local function serialize_ach_prog_state()
	-- Magic the WML container into existence or clear if it exists already
	wml.variables[ACH_WML_STORE] = { version = 1 }

	local group_num = 0
	for group_id, group in pairs(groups) do
		local group_prefix = ("%s.group[%d]"):format(ACH_WML_STORE, group_num)
		wml.variables[group_prefix .. ".id"] = group_id
		for ach_id, prog_info in pairs(group.progression) do
			if prog_info.progress >= prog_info.max_progress then
				-- Don't serialize the achievement progress if it should
				-- already be complete in the engine achievement table. We
				-- avoid carrying unnecessary weight in saves this way.
				goto skip_prog
			end

			local prefix = group_prefix .. ".progress"
			local append_index = wml.variables[prefix .. ".length"]

			wml.variables[("%s[%d]"):format(prefix, append_index)] = {
				id       = ach_id,
				progress = prog_info.progress
			}

			::skip_prog::
		end
		group_num = group_num + 1
	end
end

function journeylog.register_achievements(cfg)
	for group_cfg in wml.child_range(cfg, "achievement_group") do
		register_achievement_group(group_cfg)
	end

	-- Now we can read save data
	deserialize_ach_prog_state()
end

--
-- Playthrough-local substitute for wesnoth.achievements.progress.
--
-- This works similarly to the engine function, except that it only makes a
-- persistent record if the achievement would be marked as complete this way.
--
function journeylog.progress_achievement(group_id, achievement_id, amount, limit)
	local local_progress = _local_achievement_progress(group_id, achievement_id)
	local max_progress = _local_achievement_progress(group_id, achievement_id, ACH_MAX_PROGRESS)

	if local_progress >= max_progress or local_progress == -1 then
		-- Nothing to do here
		return -1
	end

	if (amount or 0) < 1 then
		return local_progress
	end

	if (limit or 0) < 1 then
		limit = max_progress
	end

	local_progress = math.min(local_progress + amount, limit)

	if local_progress >= max_progress then
		-- This SHOULD set the same state unless the engine and Naia have a
		-- different notion each of the achievement table somehow, which would
		-- be Really Bad(tm).
		-- This call also takes care of notifying the player if needed.
		_WACH_progress(group_id, achievement_id, amount, limit)
		local_progress = -1
	end

	-- Couple of sanity checks before we proceed. We mimic the engine error
	-- messages here (as of 1.18, see scripting/game_lua_kernel.cpp)
	if groups[group_id] == nil then
		wml.error(("Achievement group %s not found"):format(group_id))
	end
	if not _local_achievement_exists(group_id, achievement_id) then
		wml.error(("Achievement %s not found for achievement group %s"):format(achievement_id, group_id))
	end
	if groups[group_id].progression[achievement_id] == nil then
		wml.error(("Corrupt local achievement status for %s in group %s"):format(achievement_id, group_id))
	end

	groups[group_id].progression[achievement_id].progress = local_progress

	-- Save state (the whole point of this mess)
	serialize_ach_prog_state()
end

-- Force a drop-in patch
wesnoth.achievements.progress = journeylog.progress_achievement

local function enumerate_achievement_impl(group_id, achievement_id)
	local cfg = wesnoth.achievements.get(group_id, achievement_id)
	local have_achieve = wesnoth.achievements.has(group_id, achievement_id)
	local progress = nil
	if (tonumber(cfg.max_progress or 0) or 0) > 0 then
		progress = _local_achievement_progress(group_id, achievement_id)
	end

	local function maybe_complete(attr_name)
		if have_achieve then
			return cfg[attr_name .. "_completed"]
		else
			return cfg[attr_name]
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
		completed        = have_achieve,
	}
end

function journeylog.enumerate_achievements()
	-- TODO FIXME we currently merge everything into one big list. This is not
	-- exactly ideal, but it'll do for the sake of shipping an achievements UI
	-- in version 1.0.
	local res = {}

	for group_id, group in pairs(groups) do
		for _, ach_id in ipairs(group.achievements) do
			table.insert(res, enumerate_achievement_impl(group_id, ach_id))
		end
	end

	return res
end
