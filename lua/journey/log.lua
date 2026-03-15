--
-- Wesnoth Journey Log module (back-end) - Scenario log API
--
-- codename Naia - Project Ethea phase 1 campaigns shared library
-- Copyright (C) 2024 - 2026 by Iris Morelle <iris@irydacea.me>
--
-- See COPYING for usage terms.
--

--
-- Retrieves the scenario log for the specified campaign/scenario id pair.
--
function journeylog.read_scenario(campaign_id, scenario_id)
	local var_path = ("%s.%s.%s"):format(JOURNEYLOG_TABLE, campaign_id, scenario_id)
	local scenario_ct = wml.variables[var_path]

	if not scenario_ct then
		return nil
	end

	local scenario_log = {}

	-- We split the scenario log into groups for each event handler. We assume
	-- that messages from event handlers with identical context hashes should
	-- be grouped together as if they were part of a single sequence.

	for i, cfg in ipairs(scenario_ct) do
		local messages = {}
		local event_hash = cfg[1]
		local event_name = cfg[2].event_name or "<unknown>"

		for message in wml.child_range(cfg[2], "message") do
			-- Just copy the WML contents, we don't do anything fancier here
			-- (yet).
			table.insert(messages, {
				is_narrator = message.is_narrator,
				speaker = message.speaker,
				message = message.message,
				image = message.image,
				choice = message.choice,
			})
		end

		table.insert(scenario_log, {
			event = event_name,
			messages = messages
		})
	end

	return scenario_log
end

--
-- Implementation details
--

local function journeylog_var_init()
	local entry_path = ("%s.%s.%s.%s"):format(JOURNEYLOG_TABLE, wesnoth.scenario.campaign.id, wesnoth.scenario.id, event_context_id())
	return entry_path
end

local function journeylog_record_message(params_cfg, choice_text)
	local event_path = journeylog_var_init()
	local recorded_num = wml.variables[event_path .. ".message.length"] or 0

	local record_path = ("%s.message[%d]"):format(event_path, recorded_num)

	-- Stamp the event name into the message block for use by the UI
	if not wml.variables[event_path] then
		wml.variables[event_path] = { event_name = wesnoth.current.event_context.name }
	end

	wml.variables[record_path] = {
		is_narrator = not params_cfg.title or nil,
		speaker = params_cfg.title,
		message = params_cfg.message,
		image = params_cfg.portrait,
		choice = choice_text,
	}
end

--
-- Wesnoth engine call hooks
--

local ENG_gui_show_narration = gui.show_narration
local ENG_wesnoth_interface_is_skipping_messages = wesnoth.interface.is_skipping_messages

wesnoth.interface.is_skipping_messages = function(i_am_naia)
	-- We pretend the user is never skipping messages when called by functions
	-- outside JourneyLog so that we can always capture the message that would
	-- be shown by gui.show_narration for safekeeping. The only exception is
	-- Naia, which needs to query the actual skipping state in order to adjust
	-- the behaviour of various functions including visual effects.
	if i_am_naia ~= 0x4149414E then
		return false
	end

	-- Secret handshake from Naia!
	return ENG_wesnoth_interface_is_skipping_messages()
end

gui.show_narration = function(msg_cfg, options, text_input)

	local res, user_text = -1, nil

	if not ENG_wesnoth_interface_is_skipping_messages() or text_input ~= nil or #options > 0 then
		-- We capture the engine's results since these will be used by our caller to
		-- act upon the user's choice, including enabling skip mode. If user input is
		-- involved, we need to record it in JourneyLog as well.
		res, user_text = ENG_gui_show_narration(msg_cfg, options, text_input)
	else
	end

	if user_text ~= nil then
		journeylog_record_message(msg_cfg, user_text)
	elseif #options > 0 and res > 0 then
		journeylog_record_message(msg_cfg, options[res].label)
	else
		journeylog_record_message(msg_cfg)
	end

	return res, user_text
end
