local _ = wesnoth.textdomain "wesnoth-ctl"
local _w = wesnoth.textdomain "wesnoth"

-- metatable for GUI tags
local T = wml.tag

local CTL_TRACKER_URL = "https://github.com/mavpii/Chasing_the_Light/issues"
local CTL_EXPERIMENTAL_SERIES = "1.19.x"
local CTL_NOTICE_FLAG = "ctl_experimental_port_notice_shown"


--###########################################################################################################################################################
--                                                              EXPERIMENTAL PORT NOTICE
--###########################################################################################################################################################
local function host_is_experimental()
	local version = wesnoth.current_version()
	return version[1] == 1 and version[2] == 19
end


local function show_experimental_port_notice()
	local message = tostring(_"This is an experimental port of Chasing the Light to Wesnoth %s.\nYou are advised not to play this port. Please use the Wesnoth 1.18 version of the campaign from the add-ons server instead.\nIf you choose to continue, you must report any issues to the author on the project’s issue tracker:")
	message = message:format(CTL_EXPERIMENTAL_SERIES)

	--###############################
	-- DEFINE GRID
	--###############################
	local grid = T.grid{
		-------------------------
		-- TITLE
		-------------------------
		T.row{ T.column{
			horizontal_alignment="left",
			border="all", border_size=5,
			T.label{  definition="title",  label=_"Notice",  wrap=true  }
		}},
		-------------------------
		-- INFO
		-------------------------
		T.row{ T.column{
			horizontal_grow=true,
			border="all", border_size=5,
			T.label{  label=message,  wrap=true  }
		}},
		T.row{ T.column{
			horizontal_grow=true,
			border="all", border_size=5,
			T.label{  label=CTL_TRACKER_URL,  link_aware=true,  wrap=true  }
		}},
		-------------------------
		-- BUTTONS
		-------------------------
		T.row{ T.column{
			horizontal_grow=true,
			T.grid{ T.row{
				T.column{
					horizontal_alignment="right",
					border="all", border_size=5,
					grow_factor=1,
					T.button{  id="ok",  label=_w"Continue",  return_value=1  }
				},
				T.column{
					horizontal_alignment="right",
					border="all", border_size=5,
					T.button{  id="quit",  label=_w"Quit",  return_value=2  }
				},
			}}
		}},
	}

	--###############################
	-- CREATE DIALOG
	--###############################
	local button = 1

	wesnoth.sync.run_unsynced(function()
		button = gui.show_dialog({
			maximum_width=640,
			T.helptip{ id="tooltip_large" }, -- mandatory field
			T.tooltip{ id="tooltip_large" }, -- mandatory field
			grid
		})
	end)

	if button == 2 then
		wesnoth.wml_actions.endlevel{
			result="defeat",
			linger_mode=false,
			carryover_report=false,
		}
	end
end


--###########################################################################################################################################################
--                                                                      "MAIN"
--###########################################################################################################################################################
on_event("preload", function()
	if not host_is_experimental() or wml.variables[CTL_NOTICE_FLAG] then
		return
	end

	wml.variables[CTL_NOTICE_FLAG] = true
	show_experimental_port_notice()
end)
