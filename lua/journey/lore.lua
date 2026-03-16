--
-- Wesnoth Journey Log module (back-end)
--
-- codename Naia - Project Ethea phase 1 campaigns shared library
-- Copyright (C) 2025 - 2026 by Iris Morelle <iris@irydacea.me>
--
-- See COPYING for usage terms.
--

-- #textdomain wesnoth-Naia
local _ = wesnoth.textdomain "wesnoth-Naia"

-- CURRENT TODO:
--
-- * public API for character and world entries that can be used by the
--   gui to retrieve information easily, including entry ids

-- Raw collection of world encyclopedia entries.
local world_info = {}

-- Index of world encyclopedia entry ids in order to preserve the original
-- definition order for UI display purposes.
local world_index = {}

-- Raw collection of character profiles.
local chara_profiles = {}

-- Index of character ids in order to preserve the original definition order
-- for UI display purposes.
local chara_index = {}

-- Raw collection of story recap text.
local recap_data = {}

-- Index of recap entry ids in order to preserve the original definition order
-- for UI display purposes.
local recap_index = {}

-- Public UI-ready cache containing the built profiles and encyclopedia entries
-- in order to avoid unnecessary data grinding whenever the lore UI is
-- displayed. This version has been built after processing entry unlock
-- triggers such as characters seen and milestones unlocked.
local lore_cache = {
	profiles = {},
	world = {},
	recaps = {},
}

local fragment_placeholder = ("<i>%s</i>"):format( _ "(records not found yet)")

-- Character attributes that should be overridden by additional_info.
local chara_override_attributes = {
	"rank",
	"name",
	"additional_titles",
	"affiliation",
	"race",
	"age",
	"status",
	"gender",
	"portrait",
	"help_unit_type",
}

-- Character attributes that should be extended by additional_info.
local chara_extend_attributes = {
	"description",
}

-- Prebaked merge to make things easier later.
-- (NOTE: id is not included here or in the others because it requires special
-- treatment to avoid shenanigans)
local chara_all_attributes = array_join(chara_extend_attributes, chara_override_attributes)

-- World lore entry attributes that should be overridden by additional_info.
local lore_override_attributes = {
	"title",
	"source",
}

-- World lore entry attributes that should be extended by additional_info.
local lore_extend_attributes = {
	"text",
}

-- Prebaked merge to make things easier later.
-- (NOTE: id is not included here or in the others because it requires special
-- treatment to avoid shenanigans)
local lore_all_attributes = array_join(lore_extend_attributes, lore_override_attributes)

-- NOTE:
-- * Currently we internally use storage that replicates the [character_profile]
--   and [entry] tag's structure. This is subject to change.
-- * When merging, attributes that are missing in additional_info are ignored.
-- * When merging, attributes missing in dest but not in additional_info come
--   into existence in the former.

local function clone_attributes_p(source, include_milestone_info, all_attrs)
	local dest = {}
	local attrs = all_attrs
	if include_milestone_info == nil or include_milestone_info then
		attrs = array_join(attrs, { "requires_milestone" })
	end

	for _, attr in ipairs(attrs) do
		dest[attr] = source[attr]
	end

	return dest
end

local function merge_additional_info_p(dest, additional_info, override_attrs, extend_attrs)

	for _, attr in ipairs(override_attrs) do
		if additional_info[attr] ~= nil then
			dest[attr] = additional_info[attr]
		end
	end
	for _, attr in ipairs(extend_attrs) do
		if additional_info[attr] ~= nil then
			dest[attr] = ("%s\n\n%s"):format(dest[attr], additional_info[attr])
		end
	end
end

local function clone_chara_attributes(source, include_milestone_info)
	return clone_attributes_p(source, include_milestone_info, chara_all_attributes)
end

local function merge_chara_additional_info(dest, additional_info)
	return merge_additional_info_p(dest, additional_info, chara_override_attributes, chara_extend_attributes)
end

local function clone_lore_attributes(source, include_milestone_info)
	return clone_attributes_p(source, include_milestone_info, lore_all_attributes)
end

local function merge_lore_additional_info(dest, additional_info)
	return merge_additional_info_p(dest, additional_info, lore_override_attributes, lore_extend_attributes)
end

local function retrieve_lore_fragment_text_priv(entry_id, fragment_id)
	if entry_id == nil or fragment_id == nil or not world_info[entry_id] then
		return nil
	end

	for _, fragment in ipairs(world_info[entry_id].fragments) do
		if fragment.id == fragment_id then
			return fragment.text
		end
	end

	return nil
end

--
-- Processes character profile information from WML.
--
-- The specified WML argument must contain an array of [character_profile]
-- tags to process.
--
function journeylog.register_character_profiles(cfg)
	--windent()

	if not cfg then
		wml.error("journeylog.register_character_profiles(): WML must not be nil")
	end

	for profile in wml.child_range(cfg, "character_profile") do
		if profile.id == nil then
			wml.error("journeylog.register_character_profiles(): Missing [character_profile] id")
		end

		if chara_profiles[profile.id] ~= nil then
		end

		local additional_info = {}

		for extra in wml.child_range(profile, "additional_info") do
			if extra.requires_milestone == nil then
				wml.error("journeylog.register_character_profiles(): Missing [additional_info] requires_milestone")
			end

			table.insert(additional_info, clone_chara_attributes(extra))
		end

		if chara_profiles[profile.id] == nil then
			table.insert(chara_index, profile.id)
		end

		chara_profiles[profile.id] = table_merge(clone_chara_attributes(profile), {
			id = profile.id,
			additional_info = additional_info,
		})
	end

	--wunindent()

	journeylog.rebuild_lore("chara")
end

--
-- Processes world encyclopedia entries from WML.
--
-- The specified WML argument must contain an array of [entry] tags to process.
--
function journeylog.register_world_lore_entries(cfg)
	--windent()

	if not cfg then
		wml.error("journeylog.register_world_lore_entries(): WML must not be nil")
	end

	for entry in wml.child_range(cfg, "world_entry") do
		if entry.id == nil then
			wml.error("journeylog.register_world_lore_entries(): Missing [entry] id")
		end

		local fragments, additional_info = {}, {}

		for frag in wml.child_range(entry, "fragment") do
			if frag.id == nil then
			end

			table.insert(fragments, {
				id = frag.id,
				text = frag.text,
			})
		end

		for extra in wml.child_range(entry, "additional_info") do
			if extra.requires_milestone == nil then
				wml.error("journeylog.register_world_lore_entries(): Missing [additional_info] requires_milestone")
			end

			table.insert(additional_info, clone_lore_attributes(extra))
		end

		if world_info[entry.id] == nil then
			table.insert(world_index, entry.id)
		end

		world_info[entry.id] = table_merge(clone_lore_attributes(entry), {
			id              = entry.id,
			additional_info = additional_info,
			fragments       = fragments,
		})
	end

	--wunindent()

	journeylog.rebuild_lore("world")
end

--
-- Processes story recap entries from WML.
--
-- The specified WML argument must contain an array of [story_recap] tags to
-- process.
--
function journeylog.register_recap_entries(cfg)
	--windent()

	if not cfg then
		wml.error("journeylog.register_recap_entries(): WML must not be nil")
	end

	for entry in wml.child_range(cfg, "story_recap") do
		if entry.id == nil then
			wml.error("journeylog.register_recap_entries(): Missing [story_recap] id")
		end

		local sections = {}

		for sec in wml.child_range(entry, "section") do
			table.insert(sections, {
				title = sec.title,
				text = sec.text,
				quote = sec.quote,
				quote_author = sec.quote_author,
			})
		end

		if recap_data[entry.id] == nil then
			table.insert(recap_index, entry.id)
		end

		recap_data[entry.id] = {
			title = entry.title,
			text = entry.text,
			sections = sections,
		}
	end

	--wunindent()

	journeylog.rebuild_lore("recap")
end

--
-- Refreshes the internal lore library cache.
--
function journeylog.rebuild_lore(target)
	--windent()

	local profile_cache = {}
	local world_cache = {}
	local recap_cache = {}

	if not target or target == "chara" then
		for i, id in ipairs(chara_index) do
			local profile = chara_profiles[id]

			if profile == nil then
				wml.error("journeylog.rebuild_lore(): character index corrupted")
				return
			end

			if journeylog.has_milestone(profile.requires_milestone) then
				local cached_profile = clone_chara_attributes(profile, false)

				cached_profile.id = id

				-- Process additional information; everything replaces existing
				-- information except for the description, which gets extended
				-- with additional text instead.
				if profile.additional_info ~= nil and #profile.additional_info > 0 then
					for _, extra in ipairs(profile.additional_info) do
						if journeylog.has_milestone(extra.requires_milestone) then
							merge_chara_additional_info(cached_profile, extra)
						end
					end
				end

				-- Unranked items are understood to be rank #1001 and above.
				if cached_profile.rank == nil then
					cached_profile.rank = 1000 + i
				end

				table.insert(profile_cache, cached_profile)
			end
		end
	end

	-- Too lazy to optimize this and we're never going to have enough
	-- characters for this to matter
	table.sort(profile_cache, function(a, b) return a.rank < b.rank end)

	if not target or target == "world" then
		for _, id in ipairs(world_index) do
			local entry = world_info[id]

			if entry == nil then
				wml.error("journeylog.rebuild_lore(): world lore index corrupted")
				return
			end

			if journeylog.has_milestone(entry.requires_milestone) then
				local cached_entry = clone_lore_attributes(entry, false)
				local should_include = true

				cached_entry.id = id

				-- Process fragments; missing fragments are replacedd with a
				-- hardcoded (albeit translatable) placeholder.
				if #entry.fragments > 0 then
					local parts = {}
					local lead = tostring(cached_entry.text or "")
					local last_placeholder = 0

					if #lead > 0 then
						table.insert(parts, lead)
					end

					should_include = false

					for _, frag in ipairs(entry.fragments) do
						if frag.id ~= nil and journeylog.has_lore_fragment(id, frag.id) then
							table.insert(parts, tostring(frag.text))
							should_include = true
						elseif last_placeholder == 0 or last_placeholder ~= #parts then
							table.insert(parts, fragment_placeholder)
							last_placeholder = #parts
						end
					end

					cached_entry.text = stringx.join(parts, "\n\n")
				end

				-- Process additional information; everything replaces existing
				-- information except for the description, which gets extended
				-- with additional text instead.
				if entry.additional_info ~= nil and #entry.additional_info > 0 then
					for _, extra in ipairs(entry.additional_info) do
						if journeylog.has_milestone(extra.requires_milestone) then
							merge_lore_additional_info(cached_entry, extra)
						end
					end
				end

				if should_include then
					table.insert(world_cache, cached_entry)
				end
			end
		end
	end

	if not target or target == "recap" then
		-- NOTE: currently, story recaps do not support any state, so we just
		-- cram them all into the cache unmodified
		for _, id in ipairs(recap_index) do
			local entry = recap_data[id]

			if entry == nil then
				wml.error("journeylog.rebuild_lore(): recap index corrupted")
				return
			end

			local sections = {}

			for i, section in ipairs(entry.sections) do
				table.insert(sections, {
					title = section.title,
					text = section.text,
					quote = section.quote,
					quote_author = section.quote_author,
				})
			end

			table.insert(recap_cache, {
				id = id,
				title = entry.title,
				text = entry.text,
				sections = sections,
			})
		end
	end

	--wunindent()

	-- Update table references

	if not target or target == "chara" then
		lore_cache.profiles = profile_cache
	end

	if not target or target == "world" then
		lore_cache.world = world_cache
	end

	if not target or target == "recap" then
		lore_cache.recaps = recap_cache
	end
end

--
-- Retrieves character profiles for UI display.
--
-- Profile entries are structured thus:
--
--   id                      The character entry's internal id.
--   name                    Name of the character.
--   additional_titles       Additional titles the character has.
--   affiliation             Affiliations (to groups, orgs, etc.) the character has.
--   race                    Race/species of the character.
--   gender                  Gender of the character.
--   portrait                Portrait image.
--   status                  Character's living status - one of "dead",
--                           "missing", or nil (living).
--   description             Character's detailed bio/description.
--
function journeylog.retrieve_character_profiles()
	return lore_cache.profiles
end

--
-- Retrieves world encyclopedia entries for UI display.
--
-- Encyclopedia entries are structured thus:
--
--   id                      The entry's internal id.
--   name                    Name of the entry.
--   description             Text of the entry.
--
function journeylog.retrieve_world_lore()
	return lore_cache.world
end

--
-- Retrieves story recap entries for UI display.
--
-- Recap entries are structured thus:
--
--   id                      The entry's internal id.
--   title                   Title for the entry.
--   text                    Text (or prologue if there are separate sections)
--                           for the entry.
--   sections                Sub-sections grouped under the same entry, in
--                           their intended display order.
--
-- Subsections of a recap are represented as tables containing the following
-- attributes:
--
--   title                   Section title.
--   quote                   Preceding quote at the beginning.
--   quote_author            Attribution for the preceding quote.
--   text                    Section body.
--
function journeylog.retrieve_story_recaps()
	return lore_cache.recaps
end

local function retrieve_lore_for_wml_internal(collection, fragment, entry_id)
	if collection ~= "world" and collection ~= "character" then
		return nil
	end

	local data = {
		text          = "",
		title         = "",
		fragments     = {},
	}

	if fragment ~= nil and fragment ~= "" then
		data.text = retrieve_lore_fragment_text_priv(entry_id, fragment)

		if not data.text then
			wml.error(("[xxxxx_world_lore] entry/fragment pair %s.%s not found or empty"):format(entry, fragment))
		end
	else
		local entry = world_info[entry_id]

		if not entry then
			wml.error(("[xxxxx_world_lore] entry %s not found or empty"):format(entry_id))
		end

		data.text = entry.text

		if #entry.fragments > 0 then
			for _, fragment in ipairs(entry.fragments) do
				table.insert(data.fragments, {
					id   = fragment.id,
					text = fragment.text,
				})
			end
		end
	end

	data.title = world_info[entry_id].title

	return data
end

--
-- Stores a journeylog lore entry text into a WML variable.
--
-- NOTE: This currently does not use the progression/unlock mechanism, which
-- means that any milestone-dependent info is never retrieved (FIXME).
--
-- [store_lore]
--     # WML variable name used to store data. If an entry only has plain
--     # text, then the text will be stored straight into a scalar with this
--     # name. If the entry contains [fragment]s, then the lead text will be
--     # stored into <variable>.text, and the individual fragments' own text
--     # will be in <variable>.fragment[n].text.
--     variable="lore"
--
--     # Id of the lore entry.
--     entry="entry id"
--
--     # Fragment id. If specified, then the contents of one single fragment
--     # will be stored into the <variable> scalar.
--     fragment="fragment id"
--
--     # Specify whether to retrieve world lore (default) or character lore.
--     collection="world"
-- [/store_world_lore]
--
function wesnoth.wml_actions.store_world_lore(cfg)
	local variable = cfg.variable or "lore"
	local collection = cfg.collection or "world"
	local fragment = cfg.fragment
	local entry = cfg.entry or
		wml.error("[store_world_lore] entry= required")

	if collection ~= "world" and collection ~= "character" then
		wml.error("[store_world_lore] collection= must be either 'world' or 'character'")
	end

	local data = retrieve_lore_for_wml_internal(collection, fragment, entry)

	if #data.fragments == 0 then
		-- Scalar (FIXME we may want to change this in order to be able to
		-- retrieve titles)
		wml.variables[variable] = data.text
	else
		-- Full table with fragments
		wml.variables[variable] = { text = data.text }
		for i, fragment in ipairs(data.fragments) do
			local path = ("%s.fragment[%d]"):format(variable, i - 1)
			wml.variables[path .. ".id"]   = fragment.id
			wml.variables[path .. ".text"] = fragment.text
		end
	end
end

--
-- Displays a single lore entry.
--
-- NOTE: This currently does not use the progression/unlock mechanism, which
-- means that any milestone-dependent info is never retrieved (FIXME).
--
-- Usage:
--
-- [show_world_lore]
--     entry="entry id"
--
--     # Fragment id. If specified, then the contents of one single fragment
--     # will be shown.
--     fragment="fragment id"
--
--     # Specify whether to retrieve world lore (default) or character lore.
--     collection="world"
-- [/show_world_lore]
--
function wesnoth.wml_actions.show_world_lore(cfg)
	-- FIXME: This entire function depends on UI functionality even though
	-- this isn't a UI module. Oops.
	local collection = cfg.collection or "world"
	local fragment = cfg.fragment
	local entry = cfg.entry or
		wml.error("[store_world_lore] entry= required")
	local image = cfg.image

	if collection ~= "world" and collection ~= "character" then
		wml.error("[store_world_lore] collection= must be either 'world' or 'character'")
	end

	local data = retrieve_lore_for_wml_internal(collection, fragment, entry)
	local text = data.text

	-- Join fragments
	if #data.fragments > 0 then
		for _, fragment in ipairs(data.fragments) do
			text = text .. "\n\n" .. fragment.text
		end
	end

	_journeylog_mini_ui(data.title, text, image)
end
