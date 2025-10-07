local _ = wesnoth.textdomain "wesnoth-ctl"

function wesnoth.interface.game_display.stormvale_quests()
	local val = wml.variables["stormvale_quests_completed"] or 0
	local val2 = wml.variables["stormvale_quests_max"] or 0
	local str = val.."/"..val2

	return { { 'element', {
		text = str
	} } }

end