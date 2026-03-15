--
-- Persistent WML variables library
--
-- codename Naia - Project Ethea phase 1 campaigns shared library
-- Copyright (C) 2012 - 2026 by Iris Morelle <iris@irydacea.me>
--
-- See COPYING for usage terms.
--

local T = wml.tag

local PERSISTENT_NS_NAIA = "Project_Ethea.Naia"

local PERSISTENT_GTABLE = "global_table"
local GTABLE            = "__naia_gtable"

---
-- Returns whether a table is empty or not.
---
function table_empty(table_v, include_nil)
	for val in pairs(table_v) do
		if val ~= nil or include_nil == true then
			return false
		end
	end

	return true
end

---
-- Returns a sorted list of keys for a table.
---
function table_keys(table_v)
	local keys = {}
	for key, v in pairs(table_v) do
		table.insert(keys, key)
	end
	table.sort(keys)
	return keys
end

---
-- Returns a table that contains the elements of both tables.
--
-- If table_b has items with the same keys as those of table_a then they will
-- overwrite the latter's items in the result table.
---
function table_merge(table_a, table_b)
	local keys_a, keys_b = table_keys(table_a), table_keys(table_b)
	local result = {}

	for _, key in ipairs(keys_a) do
		result[key] = table_a[key]
	end

	for _, key in ipairs(keys_b) do
		result[key] = table_b[key]
	end

	return result
end

function array_join(table_a, table_b)
        	local result = {}
        
        	for _, element in ipairs(table_a) do
        		table.insert(result, element)
        	end
        
        	for _, element in ipairs(table_b) do
        		table.insert(result, element)
        	end
        
        	return result
        end

local function gtable_get(key)
	return wml.variables[("%s.%s"):format(GTABLE, key)]
end

local function gtable_set(key, value)
	wml.variables[("%s.%s"):format(GTABLE, key)] = value
end

function wesnoth.wml_actions.global_table(cfg)
	local namespace = cfg.namespace or PERSISTENT_NS_NAIA

	-- Open global table

	wesnoth.wml_actions.get_global_variable {
		namespace   = namespace,
		from_global = PERSISTENT_GTABLE,
		to_local    = GTABLE,
	}

	-- Force the global table to exist if this is a fresh persistent store

	if type(wml.variables[GTABLE]) ~= "table" then
		wml.variables[GTABLE] = nil
		wml.variables[GTABLE] = {}
	end

	gtable_set("_gtable_start", 1)

	--wesnoth.wml_actions.inspect {}

	-- Perform global table actions

	local cmds = wml.shallow_literal(cfg)

	for i = 1, #cmds do
		local t = cmds[i]
		local cmd_id = t[1]
		local cmd_cfg = t[2]

		local key = cmd_cfg.key or wml.error("[global_table] Missing required key= attribute in subcommand")

		if cmd_id == "read" then
			wml.variables[key] = gtable_get(key)
		elseif cmd_id == "write" then
			gtable_set(key, wml.variables[key])
		elseif cmd_id == "delete" then
			gtable_set(key, nil)
		end
	end

	-- Flush and close global table	

	wesnoth.wml_actions.set_global_variable {
		namespace  = namespace,
		to_global  = PERSISTENT_GTABLE,
		from_local = GTABLE,
		immediate  = true,
	}

	wml.variables[GTABLE] = nil
end


--
-- Generates a "hash" of an event context that can be used to identify it in
-- an opaque yet WML-friendly fashion.
--
local function evctx_id_cleanname(name)
	return name:gsub("[^0-9A-Za-z]", "")
end

function event_context_id()
	local hash = ""
	local ctx = wesnoth.current.event_context

	-- The resulting "hash" can only contain characters which are valid in WML
	-- identifiers, which limits our universe considerably.
	--
	-- A full hash will look like this, with elements which are empty or zero
	-- being omitted from the output:
	--
	--   N<event dispatch name><trail>
	--   I<event handler id><trail>
	--   X<x1>Y<y1>
	--   U<x2>V<y2>
	--
	-- For the event name and id, the <trail> component is the total count of
	-- whitespace or underscore characters, which are removed from the
	-- identifier since: a) underscore and whitespace are considered equivalent
	-- in event dispatch names; b) whitespace is illegal in WML identifiers.

	local id, id_trail = evctx_id_cleanname(ctx.id)
	local name, name_trail = evctx_id_cleanname(ctx.name)

	if id and id ~= "" then
		hash = ("N%s%dI%s%d"):format(name, name_trail, id, id_trail)
	else
		hash = ("N%s%d"):format(name, name_trail)
	end

	if ctx.x1 or ctx.y1 then
		hash = hash .. ("X%dY%d"):format(ctx.x1, ctx.y1)
	end

	if ctx.x2 or ctx.y2 then
		hash = hash .. ("U%dV%d"):format(ctx.x2, ctx.y2)
	end

	return hash
end
