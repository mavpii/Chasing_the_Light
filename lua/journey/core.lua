--
-- Wesnoth Journey Log module (back-end) - Core API
--
-- codename Naia - Project Ethea phase 1 campaigns shared library
-- Copyright (C) 2024 - 2026 by Iris Morelle <iris@irydacea.me>
--
-- See COPYING for usage terms.
--

journeylog = {}

JOURNEYLOG_TABLE = "__naia_journeylog"

local journeylog_campaign_info = {}

-- Ensure the JourneyLog table is initialised when starting a scenario. It is
-- harmless to allow this to run on each reload, plus has the added benefit of
-- updating the campaign or scenario name translatables if they have changed.
on_event("preload", function()
	wml.variables[("%s.%s.name"):format(JOURNEYLOG_TABLE, wesnoth.scenario.campaign.id)] = wesnoth.scenario.campaign.name
	wml.variables[("%s.%s.%s.name"):format(JOURNEYLOG_TABLE, wesnoth.scenario.campaign.id, wesnoth.scenario.id)] = wesnoth.scenario.name
end)

--
-- Registers the specified campaign.
--
-- If mnemonic or label are not proivded, they will be copied from the current
-- campaign if its id matches campaign_id.
--
-- Arguments:
--
--   campaign_id             This is the campaign's internal identifier.
--   label                   This is the campaign's user-friendly name used in
--                           the user interface.
--   mnemonic                This is the campaign's abbreviation/mnemonic.
--
function journeylog.register_campaign(campaign_id, label, mnemonic)
	if journeylog_campaign_info[campaign_id] ~= nil then
		-- Already registered
		return
	end

	local baseline = {
		abbreviation = nil,
		name = nil
	}

	if wesnoth.scenario.campaign ~= nil and wesnoth.scenario.campaign.id == campaign_id then
		baseline = wesnoth.scenario.campaign
	end

	local entry = {
		mnemonic = mnemonic or baseline.abbrev,
		label    = label or baseline.name,
	}

	if not entry.mnemonic or not entry.label then
	end

	journeylog_campaign_info[campaign_id] = entry
end

--
-- Registers the specified scenario.
--
-- Arguments:
--
--   campaign_id             This is the parent campaign's internal identifier.
--                           If nil, the current campaign's id is used if
--                           available.
--   scenario_id             This is the scenario's internal identifier.
--   label                   This is the scenarios's regular user-friendly name
--                           seen in most user interfaces as well as save
--                           files.
--   mnemonic                This is the scenario's abbreviation/mnemonic used
--                           in certain user interfaces.
--   hidden                  Specifies whether the scenario should be hidden
--                           from listings in the JourneyLog user interface.
--                           Use this for cutscene and technical scenarios.
--
function journeylog.register_scenario(campaign_id, scenario_id, label, mnemonic, hidden)
	local real_cid = campaign_id

	if not real_cid then
		if not wesnoth.scenario.campaign then
			wml.error("journeylog.register_scenario(): No campaign id provided and not running in a campaign scenario context")
		end

		real_cid = wesnoth.scenario.campaign.id
	end

	journeylog.register_campaign(real_cid)

	journeylog_campaign_info[real_cid][scenario_id] = {
		mnemonic = mnemonic,
		label    = label,
		hidden   = hidden
	}
end

--
-- Scenario initialization-time wrapper for journeylog.register_scenario.
--
-- WML arguments:
--
--   id                      This is the scenario's internal identifier.
--   name                    This is the scenarios's regular user-friendly name
--                           seen in most user interfaces as well as save
--                           files.
--   abbrev                  This is the scenario's abbreviation/mnemonic used
--                           in certain user interfaces.
--   hidden                  Specifies whether the scenario should be hidden
--                           from listings in the JourneyLog user interface.
--                           Use this for cutscene and technical scenarios.
--
function journeylog.register_scenario_wml(wml_args)
	journeylog.register_scenario(nil, wml_args.id, wml_args.title, wml_args.abbrev, wml_args.hidden)
end

function journeylog.register_campaign_mnemonic(campaign_id, mnemonic)
	journeylog_campaign_mn[campaign_id] = mnemonic
end

local function _enumerate_impl_common(wml_container)
	local enum = {}

	for i, cfg in ipairs(wml_container) do
		table.insert(enum, {
			-- index 1 holds the WML child's tag name
			id = cfg[1],
			-- .name has a user-friendly name per convention
			name = cfg[2].name or cfg[1]
		})
	end

	return enum
end

function journeylog.enumerate_campaigns()
	local journeylog_table = wml.variables[JOURNEYLOG_TABLE]
	return _enumerate_impl_common(journeylog_table)
end

function journeylog.enumerate_scenarios(campaign_id)
	local scenario_table = wml.variables[("%s.%s"):format(JOURNEYLOG_TABLE, campaign_id)]
	return _enumerate_impl_common(scenario_table)
end

function journeylog.retrieve_scenario_info(scenario_id, campaign_id, strict)
	if scenario_id == nil then
		scenario_id = wesnoth.scenario.id or
			wml.error("bad gamestate, no scenario id")
	end

	if campaign_id == nil then
		campaign_id = wesnoth.scenario.campaign.id or
			wml.error("bad gamestate, no campaign id")
	end

	if not journeylog_campaign_info[campaign_id] then
		return nil
	end

	local info = journeylog_campaign_info[campaign_id][scenario_id]

	if not info then
		if strict == nil or strict then
		end
		return nil
	end

	-- NOTE: this may not remain a trivial piecewise copy forever
	return {
		mnemonic = info.mnemonic,
		label    = info.label,
		hidden   = info.hidden
	}
end
