local _ = wesnoth.textdomain "wesnoth-ctl"

-- https://wiki.wesnoth.org/LuaAPI/types/widget

-- metatable for GUI tags
local T = wml.tag
























--###########################################################################################################################################################
--                                                                 SCENARIO PREVIEW
--###########################################################################################################################################################
function change_location(cfg)
	local tutor_title = cfg.title
	local tutor_message = cfg.message
	local tutor_image = cfg.image

	--###############################
	-- DEFINE GRID
	--###############################
	local grid = T.grid{ T.row{
		T.column{ T.label{  use_markup=true,  label="<span size='40000'> </span>"  }},
		T.column{ border="right,left,bottom", border_size=18, T.grid{
			-------------------------
			-- TITLE
			-------------------------
			T.row{ T.column{ T.image{  label="icons/banner3_popup.png"  }}},
			T.row{ T.column{ T.label{  use_markup=true,  label="<span size='8000'> </span>"  }}},
			T.row{ T.column{
				horizontal_alignment="center",
				T.label{  definition="title",  label=tutor_title,  }
			}},
			T.row{ T.column{ T.label{  use_markup=true,  label="<span size='15000'> </span>"  }}},
			-------------------------
			-- INFO
			-------------------------
			T.row{ T.column{ T.grid{ T.row{
			    T.column{
					T.image{  label=tutor_image  }
				},
				T.column{ T.label{  use_markup=true,  label="<span size='80000'> </span>"  }},
				T.column{
					horizontal_alignment="left",
					T.label{
						use_markup=true,
						label=tutor_message,
					}
				},
				
			}}}},
			T.row{ T.column{ T.label{  use_markup=true,  label="<span size='15000'> </span>"  }}},
			T.row{ T.column {T.image{  label="icons/banner2_popup.png"  }}},
			T.row{ T.column{ T.label{  use_markup=true,  label="<span size='15000'> </span>"  }}},
			-------------------------
			-- BUTTONS
			-------------------------
			T.row{T.column{ T.grid{ T.row{
				T.column{ T.button{
					return_value=1, use_markup=true,
					label=_"Yes, I'll come in now",
				}},
				T.column{ T.label{  use_markup=true,  label="<span size='15000'>     </span>"  }},
				T.column{ T.button{
					return_value=2, use_markup=true,
					label=_"No, maybe later",
				}},
			}}}},
		}},
		T.column{ T.label{  use_markup=true,  label="<span size='40000'> </span>"  }},
	}}

	--###############################
	-- CREATE DIALOG
	--###############################
	local result = wesnoth.sync.evaluate_single(function()
		local button = gui.show_dialog({
			definition="menu",
			T.helptip{ id="tooltip_large" }, -- mandatory field
			T.tooltip{ id="tooltip_large" }, -- mandatory field
			grid
		})
		if (button==1) then wml.variables['s9_change_location']=true end
		if (button==2) then wml.variables['s9_change_location']=false end
		return { button=button }
	end)
end



function change_location_fake(cfg)
	local tutor_title = cfg.title
	local tutor_message = cfg.message
	local tutor_image = cfg.image

	--###############################
	-- DEFINE GRID
	--###############################
	local grid = T.grid{ T.row{
		T.column{ T.label{  use_markup=true,  label="<span size='40000'> </span>"  }},
		T.column{ border="right,left,bottom", border_size=18, T.grid{
			-------------------------
			-- TITLE
			-------------------------
			T.row{ T.column{ T.image{  label="icons/banner3_popup.png"  }}},
			T.row{ T.column{ T.label{  use_markup=true,  label="<span size='8000'> </span>"  }}},
			T.row{ T.column{
				horizontal_alignment="center",
				T.label{  definition="title",  label=tutor_title,  }
			}},
			T.row{ T.column{ T.label{  use_markup=true,  label="<span size='15000'> </span>"  }}},
			-------------------------
			-- INFO
			-------------------------
			T.row{ T.column{ T.grid{ T.row{
			    T.column{
					T.image{  label=tutor_image  }
				},
				T.column{ T.label{  use_markup=true,  label="<span size='80000'> </span>"  }},
				T.column{
					horizontal_alignment="left",
					T.label{
						use_markup=true,
						label=tutor_message,
					}
				},
				
			}}}},
			T.row{ T.column{ T.label{  use_markup=true,  label="<span size='15000'> </span>"  }}},
			T.row{ T.column {T.image{  label="icons/banner2_popup.png"  }}},
			T.row{ T.column{ T.label{  use_markup=true,  label="<span size='15000'> </span>"  }}},
			-------------------------
			-- BUTTONS
			-------------------------
			T.row{T.column{ T.grid{ T.row{
				T.column{ T.button{
					return_value=2, use_markup=true,
					label=_"Close",
				}},
			}}}},
		}},
		T.column{ T.label{  use_markup=true,  label="<span size='40000'> </span>"  }},
	}}

	--###############################
	-- CREATE DIALOG
	--###############################
	local result = wesnoth.sync.evaluate_single(function()
		local button = gui.show_dialog({
			definition="menu",
			T.helptip{ id="tooltip_large" }, -- mandatory field
			T.tooltip{ id="tooltip_large" }, -- mandatory field
			grid
		})
		return { button=button }
	end)
end


















--###########################################################################################################################################################
--                                                                      "MAIN"
--###########################################################################################################################################################
-------------------------
-- DEFINE WML TAGS
-------------------------
function wesnoth.wml_actions.change_location(cfg)
    if not cfg.fake then
	    change_location(cfg)
	else 
	    change_location_fake(cfg)
	end
end


