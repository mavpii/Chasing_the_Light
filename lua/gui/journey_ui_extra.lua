--
-- Wesnoth Journey Log module (front-end)
--
-- codename Naia - Project Ethea phase 1 campaigns shared library
-- Copyright (C) 2026 by Iris Morelle <iris@irydacea.me>
--
-- See COPYING for usage terms.
--

local T = wml.tag

-- #textdomain wesnoth-Naia
local _ = wesnoth.textdomain "wesnoth-Naia"

local journeylog_mini_dlg = {
	definition = "message",
	click_dismiss = true,
	maximum_width = 800,
	maximum_height = 800,

	T.helptip { id = "tooltip" },
	T.tooltip { id = "tooltip" },

	T.grid {
		T.row {
			T.column {
				border = "all",
				border_size = 5,
				horizontal_alignment = "center",
				vertical_alignment = "top",
				T.image {
					id = "image"
				}
			},
			T.column {
				vertical_alignment = "top",
				horizontal_alignment = "left",
				T.grid {
					T.row {
						T.column {
							horizontal_grow = true,
							border = "all",
							border_size = 5,
							T.label {
								id = "caption",
								definition = "title"
							}
						}
					},
					T.row {
						T.column {
							horizontal_grow = true,
							border = "top,bottom",
							border_size = 5,
							T.spacer {}
						}
					},
					T.row {
						T.column {
							horizontal_grow = true,
							border = "all",
							border_size = 5,
							T.scrollbar_panel {
								definition = "naia_journeylog_scrollbar_panel",
								T.definition {
									T.row {
										T.column {
											T.label {
												id = "message",
												definition = "naia_journeylog_page",
												wrap = true
											}
										}
									}
								}
							}
						}
					}
				}
			}
		}
	}
}

--
-- Displays a minimal version of the JourneyLog user interface.
--
-- (Internal use only, meant for [show_world_lore]).)
--
function _journeylog_mini_ui(caption, text, image)
	local function preshow(self)
		self.message.marked_up_text = transform_markup(text) or _ "<missing entry>"

		if caption ~= nil and tostring(caption):len() > 0 then
			self.caption.label = caption or ""
		else
			self.caption.visible = false
		end

		if image ~= nil and tostring(image):len() > 0 then
			self.image.label = image
		else
			self.image.visible = false
		end
	end

	gui.show_dialog(journeylog_mini_dlg, preshow, nil)
end
