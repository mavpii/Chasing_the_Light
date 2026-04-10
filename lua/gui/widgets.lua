--
-- GUI2 widget definitions used by Naia GUI elements
--
-- codename Naia - Project Ethea phase 1 campaigns shared library
-- Copyright (C) 2020 - 2026 by Iris Morelle <iris@irydacea.me>
--
-- See COPYING for usage terms.
--

local T = wml.tag

-- #textdomain wesnoth-ctl
local _ = wesnoth.textdomain "wesnoth-ctl"

-- Constants and helpers

local INTRO_TEXT_WIDTH = 600
local INTRO_TEXT_SIZE = 17
local INTRO_TEXT_COLOR = "186, 172, 125"
local INTRO_TEXT_COLOR_HOVER = "215, 215, 215"

local INTRO_CHECKBOX_WIDTH = 40
local INTRO_CHECKBOX_HEIGHT = 36
local INTRO_CHECKBOX_TEXT_OFFSET = 10 + INTRO_CHECKBOX_WIDTH
local INTRO_CHECKBOX_FILES = {
	unchecked          = "buttons/checkbox@2x.png",
	unchecked_hover    = "buttons/checkbox-active@2x.png",
	unchecked_disabled = "buttons/checkbox@2x.png~GS()",

	checked            = "buttons/checkbox-pressed@2x.png",
	checked_hover      = "buttons/checkbox-active-pressed@2x.png",
	checked_pressed    = "buttons/checkbox-active-pressed@2x.png",
	checked_disabled   = "buttons/checkbox-pressed@2x.png~GS()",
}

local JOURNEYLOG_BIO_PORTRAIT_SIZE = 200
local JOURNEYLOG_BIO_SMALL_PORTRAIT_SIZE = 128

local JOURNEYLOG_FRAME_PADDING = 3
local JOURNEYLOG_FRAME_DECO = "dialogs/multi_create/corner.png~O(0.50)"

local JOURNEYLOG_PANEL_PADDING = 3
local JOURNEYLOG_PANEL_BORDER_COLOR = "114, 79, 46, 127" -- GUI__BORDER_COLOR_DARK

local JOURNEYLOG_SCROLLBAR_THICKNESS = 7
local JOURNEYLOG_SCROLLBAR_POSITIONER_LENGTH = 11
local JOURNEYLOG_SCROLLBAR_GROOVE_COLOR = "0, 0, 0, 47"
local JOURNEYLOG_SCROLLBAR_GROOVE_COLOR_HOVER = "0, 0, 0, 127"
local JOURNEYLOG_SCROLLBAR_SLIDER_COLOR = "23, 50, 73, 200"
local JOURNEYLOG_SCROLLBAR_SLIDER_COLOR_HOVER = "33, 66, 93, 200"

local JOURNEYLOG_DIALOG_COLOR = "215, 215, 215" -- GUI__FONT_COLOR_ENABLED__DEFAULT
local JOURNEYLOG_SPEAKER_COLOR = "186, 172, 125" -- GUI__FONT_COLOR_ENABLED__TITLE

-- Special fixed-width label definitions are used in the JourneyLog UI in
-- order to keep the layout consistent between pages and view modes. These
-- constants are used to determine their sizes.
local JOURNEYLOG_PAGE_WIDTH = 650
-- Multiples of 5 in the following constants stem from the application of
-- margins (border/border_size) around the relevant cells.
local JOURNEYLOG_SPEAKER_WIDTH = 15 + JOURNEYLOG_BIO_SMALL_PORTRAIT_SIZE
local JOURNEYLOG_MESSAGE_WIDTH = JOURNEYLOG_PAGE_WIDTH - JOURNEYLOG_SPEAKER_WIDTH - 10

--
-- Helper to avoid code duplication and odd semantics in GUI2 calls.
--
local function G_widget(widget_class, id, cfg)
	gui.add_widget_definition(widget_class, id, {
		-- id and description are duplicated in order to prevent a WML error:
		-- "In section '[styled_widget]' the mandatory key 'id/description' isn't set."
		id          = id,
		description = "a decade and a half later, gui2 still sucks",
		T.resolution(cfg)
	})
end

local function G_widget2(widget_class, id, resolutions)
	local cfg = {
		-- id and description are duplicated in order to prevent a WML error:
		-- "In section '[styled_widget]' the mandatory key 'id/description' isn't set."
		id          = id,
		description = "a decade and a half later, gui2 still sucks"
	}

	for i, res in ipairs(resolutions) do
		table.insert(cfg, T.resolution(res))
	end

	gui.add_widget_definition(widget_class, id, cfg)
end

--
-- Helper to build a full canvas by combining both WML tables and individual
-- WML nodes in the argument list.
--
local function C_vcanvas(...)
	local result = {}
	local args = {...}

	for i, item in ipairs(args) do
		if type(item) ~= "table" then
			wml.error("input does not look like WML")
		end
		-- If one of the arguments is the result of wml.tag, it should look
		-- like this: { 'tagname', { <contents> } }, which is a 2-item array.
		local is_single_wml_tag =
			#item == 2 and
			type(item[1]) == "string" and
			type(item[2]) == "table"

		if is_single_wml_tag then
			table.insert(result, item)
		else
			-- Append children to result
			for j, child in ipairs(item) do
				table.insert(result, child)
			end
		end
	end

	return T.draw(result)
end

--
-- Helper to build a round border around the canvas edges.
--
local function C_round_frame(params)
	local color = params.color or "0, 0, 0, 255"
	local thickness = params.thickness or 1
	return {
		T.line {
			x1 = 1,
			y1 = 0,
			x2 = "(width - 2)",
			y2 = 0,
			thickness = thickness,
			color = color
		},
		T.line {
			x1 = 0,
			y1 = 1,
			x2 = 0,
			y2 = "(height - 2)",
			thickness = thickness,
			color = color
		},
		T.line {
			x1 = 1,
			y1 = "(height - 1)",
			x2 = "(width - 2)",
			y2 = "(height - 1)",
			thickness = thickness,
			color = color
		},
		T.line {
			x1 = "(width - 1)",
			y1 = 1,
			x2 = "(width - 1)",
			y2 = "(height - 2)",
			thickness = thickness,
			color = color
		}
	}
end

local function C_line(x1, y1, x2, y2, color)
	return T.line {
		x1 = x1,
		y1 = y1,
		x2 = x2,
		y2 = y2,
		thickness = 1,
		color = color
	}
end

local function C_point(x1, y1, color)
	return C_line(x1, y1, x1, y1, color)
end

local FRAME_BORDER_BG = "1, 10, 16, 255"

--
-- Helper to generate a button frame in the Wesnoth 1.18 style.
-- (Based on GUI__BUTTON_NORMAL_FRAME.)
--
local function C_button_frame(params)
	local background_image_path = ("buttons/button_normal/%s"):format(params.background_image_path)
	local border_color          = params.border_color
	local border_color_dark     = params.border_color_dark
	local highlight_line_color  = params.highlight_line_color
	local ipf = params.ipf or ""

	return {
		T.image {
			x = 2,
			y = 2,
			w = "(width - 2)",
			h = "(height - 2)",
			name = ("%s.png%s"):format(background_image_path, ipf)
		},
		-- Dark background borders
		C_line(0,             1,              0,             "(height - 2)", FRAME_BORDER_BG),
		C_line(2,             1,              "(width - 2)", 1,              FRAME_BORDER_BG),
		C_line(1,             "(height - 1)", "(width - 2)", "(height - 1)", FRAME_BORDER_BG),
		C_line("(width - 2)", 1,              "(width - 2)", "(height - 1)", FRAME_BORDER_BG),
		-- Gold colored borders
		C_line(2,             0,              "(width - 2)", 0,              border_color),
		C_line("(width - 1)", 1,              "(width - 1)", "(height - 3)", border_color),
		C_line(1,             1,              1,             "(height - 3)", border_color_dark),
		C_line(2,             "(height - 2)", "(width - 2)", "(height - 2)", border_color_dark),
		-- Blue tint borders on the top and right
		C_line(3,             2,              "(width - 3)", 2,              highlight_line_color),
		C_line("(width - 3)", 2,              "(width - 3)", "(height - 4)", highlight_line_color),
		-- Round the corners
		C_point(2,             1,              border_color_dark),
		C_point(2,             "(height - 3)", border_color_dark),
		C_point("(width - 2)", 1,              border_color),
		C_point("(width - 2)", "(height - 3)", border_color)
	}
end

--
-- Helper to generate the horizontal scrollbar grid with an optional custom
-- scrollbar definition.
--
local function G_hscrollbar(definition, border, border_size)
	return T.grid {
		id = "_horizontal_scrollbar_grid",
		T.row {
			T.column {
				grow_factor = 1,
				horizontal_grow = true,
				border = border,
				border_size = border_size,
				T.horizontal_scrollbar {
					id = "_horizontal_scrollbar",
					definition = definition
				}
			}
		}
	}
end

--
-- Helper to generate the vertical scrollbar grid with an optional custom
-- scrollbar definition.
--
local function G_vscrollbar(definition, border, border_size)
	return T.grid {
		id = "_vertical_scrollbar_grid",
		T.row {
			grow_factor = 1,
			T.column {
				vertical_grow = true,
				border = border,
				border_size = border_size,
				T.vertical_scrollbar {
					id = "_vertical_scrollbar",
					definition = definition
				}
			}
		}
	}
end

-- Canvas definition WML

G_widget("window", "naia_campaign_intro", {
	-- Mystery magic numbers from _GUI_RESOLUTION_BORDERLESS_BASE, found
	-- in data/gui/widget/window_borderless.cfg on Wesnoth 1.18.
	left_border = 10,
	right_border = 13,
	top_border = 10,
	bottom_border = 13,

	-- We paint the whole screen black to hide the loading screen behind
	-- our dialog.
	T.background {
		T.draw {
			T.rectangle {
				x = 0,
				y = 0,
				w = "(width)",
				h = "(height)",
				fill_color = "0, 0, 0, 255"
			}
		}
	},
	T.foreground {
		T.draw {}
	},
	T.grid {
		T.row {
			grow_factor = 1,
			T.column {
				horizontal_alignment = "center",
				vertical_alignment = "center",
				T.scrollbar_panel {
					vertical_scrollbar_mode = "initial_auto",
					horizontal_scrollbar_mode = "initial_auto",
					T.definition {
						T.row {
							T.column {
								horizontal_grow = true,
								vertical_grow = true,
								T.grid {
									id = "_window_content_grid"
								}
							}
						}
					}
				}
			}
		},
		T.row {
			T.column {
				T.button {
					id = "click_dismiss",
					definition = "default",
					label = "Close"
				}
			}
		}
	}
})

local function intro_text_factory(width)
	return {
		min_width        = 0,
		min_height       = 0,
		default_width    = width,
		default_height   = 0,
		max_width        = width,
		max_height       = 0,
		text_font_family = "",
		text_font_size   = INTRO_TEXT_SIZE,
		text_font_style  = "",
		link_color       = "255, 255, 0",

		T.state_enabled {
			T.draw {
				T.text {
					x               = 0,
					y               = 0,
					w               = "(width)",
					h               = "(text_height)",
					maximum_width   = "(width)",
					font_family     = "",
					font_size       = INTRO_TEXT_SIZE,
					font_style      = "",
					color           = "([215, 215, 215, text_alpha])",
					text            = "(text)",
					text_markup     = "(text_markup)",
					text_alignment  = "(text_alignment)",
					text_link_aware = "(text_link_aware)",
					text_link_color = "(text_link_color)"
				}
			}
		},
		-- Never used
		T.state_disabled { T.draw {} }
	}
end

G_widget(
	"label",
	"naia_campaign_intro_text",
	intro_text_factory(INTRO_TEXT_WIDTH)
)

G_widget(
	"label",
	"naia_campaign_intro_option_label",
	intro_text_factory(INTRO_TEXT_WIDTH - 20 - INTRO_CHECKBOX_WIDTH)
)

local function intro_button_text(color)
	return T.text {
		x               = "(max((width - text_width) / 2, 0))",
		y               = "(max((height - text_height - 2) / 2, 0))",
		w               = "(width - 40)",
		h               = "(text_height)",
		maximum_width   = "(width - 40)",
		font_size       = 22,
		font_style      = "",
		color           = ("%s, 255"):format(color),
		text            = "(text)",
		text_markup     = false,
		text_alignment  = "left"
	}
end

local function intro_button_image(name)
	return T.image {
		x    = "(width - 40)",
		y    = "(max(pos, 0) where pos = floor((height - image_height) / 2))",
		w    = "(min(width, image_original_width))",
		h    = "(min(height, image_original_height))",
		name = ("icons/arrows/%s"):format(name)
	}
end

G_widget("button", "naia_campaign_intro_button", {
	min_width         = 250,
	min_height        = 50,
	default_width     = 250,
	default_height    = 50,
	max_width         = 0,
	max_height        = 50,
	text_extra_width  = 50,
	text_extra_height = 15,
	text_font_size    = 20,

	T.state_enabled {
		C_vcanvas(
			C_button_frame({
				background_image_path = "background",
				border_color          = "162, 127, 68, 255",   -- GUI__BORDER_COLOR
				border_color_dark     = "114, 79, 46, 255",    -- GUI__BORDER_COLOR_DARK
				highlight_line_color  = "21, 79, 109, 255"
			}),
			intro_button_text(INTRO_TEXT_COLOR),
			intro_button_image("short_arrow_ornate_right_30.png")
		)
	},
	T.state_focused {
		C_vcanvas(
			C_button_frame({
				background_image_path = "background-active",
				border_color          = "162, 127, 68, 255",   -- GUI__BORDER_COLOR
				border_color_dark     = "114, 79, 46, 255",    -- GUI__BORDER_COLOR_DARK
				highlight_line_color  = "12, 108, 157, 255"
			}),
			intro_button_text(INTRO_TEXT_COLOR),
			-- Pressed for active and active for pressed looks better
			intro_button_image("short_arrow_ornate_right_30-pressed.png")
		)
	},
	T.state_pressed {
		C_vcanvas(
			C_button_frame({
				background_image_path = "background-pressed",
				border_color          = "162, 127, 68, 255",   -- GUI__BORDER_COLOR
				border_color_dark     = "114, 79, 46, 255",    -- GUI__BORDER_COLOR_DARK
				highlight_line_color  = "1, 10, 16, 255"
			}),
			intro_button_text(INTRO_TEXT_COLOR),
			intro_button_image("short_arrow_ornate_right_30-active.png")
		)
	},
	T.state_disabled {
		C_vcanvas(
			C_button_frame({
				background_image_path = "background",
				border_color          = "128, 128, 128, 255",  -- GUI__FONT_COLOR_DISABLED__DEFAULT
				border_color_dark     = "89, 89, 89, 255",
				highlight_line_color  = "60, 60, 60, 255",
				ipf                   = "~GS()"
			}),
			intro_button_text("128, 128, 128"),
			intro_button_image("short_arrow_ornate_right_30.png~GS()")
		)
	}
})

--[[
local function naia_campaign_options_checkbox_text(params)
	if not params then
		params = {}
	end
	local color = params.color or INTRO_TEXT_COLOR
	return T.text {
		x         = INTRO_CHECKBOX_TEXT_OFFSET,
		y         = "(max((height - text_height - 2) / 2, 0))",
		w         = ("(if(width < x_offset, 0, width - x_offset) where x_offset = %d)"):format(INTRO_CHECKBOX_TEXT_OFFSET),
		h         = "(text_height)",
		maximum_width = ("(if(width < x_offset, 0, width - x_offset) where x_offset = %d)"):format(INTRO_CHECKBOX_TEXT_OFFSET),
		text_alignment = "left",
		font_size = INTRO_TEXT_SIZE,
		color     = ("%s, 255"):format(color),
		text      = "(text)"
	}
end
]]--

G_widget("toggle_button", "naia_campaign_options_checkbox", {
	min_width        = INTRO_CHECKBOX_WIDTH,
	min_height       = INTRO_CHECKBOX_HEIGHT,
	default_width    = INTRO_CHECKBOX_WIDTH,
	default_height   = INTRO_CHECKBOX_HEIGHT,
	max_width        = INTRO_TEXT_WIDTH,
	max_height       = 0,
	-- FIXME: we do not actually use the text in practice because
	-- toggle_button does not support setting the can_wrap internal property
	-- as of Wesnoth 1.18.
	--text_extra_width = INTRO_CHECKBOX_TEXT_OFFSET,
	text_extra_width = 0,
	text_font_size   = 17,

	-- Unchecked state
	T.state {
		T.enabled {
			T.draw {
				T.image {
					name = INTRO_CHECKBOX_FILES.unchecked
				},
				--naia_campaign_options_checkbox_text()
			}
		},
		T.disabled {
			T.draw {
				T.image {
					name = INTRO_CHECKBOX_FILES.unchecked_disabled
				},
				--naia_campaign_options_checkbox_text({ color = "0, 0, 0" })
			}
		},
		T.focused {
			T.draw {
				T.image {
					name = INTRO_CHECKBOX_FILES.unchecked_hover
				},
				--naia_campaign_options_checkbox_text()
			}
		}
	},
	-- Checked state
	T.state {
		T.enabled {
			T.draw {
				T.image {
					name = INTRO_CHECKBOX_FILES.checked
				},
				--naia_campaign_options_checkbox_text()
			}
		},
		T.disabled {
			T.draw {
				T.image {
					name = INTRO_CHECKBOX_FILES.checked_disabled
				},
				--naia_campaign_options_checkbox_text({ color = "0, 0, 0" })
			}
		},
		T.focused {
			T.draw {
				T.image {
					name = INTRO_CHECKBOX_FILES.checked_hover
				},
				--naia_campaign_options_checkbox_text()
			}
		}
	}

})

G_widget("window", "naia_journeylog", {
	-- Mystery magic numbers from _GUI_RESOLUTION_BORDERLESS_BASE, found
	-- in data/gui/widget/window_borderless.cfg on Wesnoth 1.18.
	left_border = 10,
	right_border = 13,
	top_border = 10,
	bottom_border = 13,

	T.background {
		T.draw {
			T.pre_commit {
				T.blur {
					depth = 8
				}
			},
			T.image {
				x = 0,
				y = 0,
				w = "(width)",
				h = "(height)",
				-- Brighten it up a bit
				name = "dialogs/translucent65-background.png~CS(20,22,26)",
				resize_mode = "tile_highres"
			},
			T.image {
				x = 0,
				y = 0,
				w = "(width)",
				h = "(height * 0.66)",
				name = "misc/journeylog-bg.png",
				resize_mode = "stretch"
			},
			T.image {
				x = JOURNEYLOG_FRAME_PADDING,
				y = JOURNEYLOG_FRAME_PADDING,
				w = "(image_width)",
				h = "(image_height)",
				name = JOURNEYLOG_FRAME_DECO .. "~ROTATE(90)"
			},
			T.image {
				x = ("(width - image_width - %d)"):format(JOURNEYLOG_FRAME_PADDING),
				y = ("(height - image_height - %d)"):format(JOURNEYLOG_FRAME_PADDING),
				w = "(image_width)",
				h = "(image_height)",
				name = JOURNEYLOG_FRAME_DECO .. "~ROTATE(-90)"
			},
			T.image {
				x = ("(width - image_width - %d)"):format(JOURNEYLOG_FRAME_PADDING),
				y = JOURNEYLOG_FRAME_PADDING,
				w = "(image_width)",
				h = "(image_height)",
				name = JOURNEYLOG_FRAME_DECO .. "~ROTATE(180)"
			},
			T.image {
				x = JOURNEYLOG_FRAME_PADDING,
				y = ("(height - image_height - %d)"):format(JOURNEYLOG_FRAME_PADDING),
				w = "(image_width)",
				h = "(image_height)",
				name = JOURNEYLOG_FRAME_DECO
			}
		}
	},
	T.foreground {
		T.draw {}
	},
	T.grid {
		T.row {
			grow_factor = 1,
			T.column {
				horizontal_grow = false, -- !!!
				vertical_grow = true,
				T.scrollbar_panel {
					definition = "naia_journeylog_scrollbar_panel",
					vertical_scrollbar_mode = "initial_auto",
					horizontal_scrollbar_mode = "initial_auto",
					T.definition {
						T.row {
							T.column {
								horizontal_grow = true,
								vertical_grow = true,
								T.grid {
									id = "_window_content_grid"
								}
							}
						}
					}
				}
			}
		},
		T.row {
			T.column {
				T.button {
					id = "click_dismiss",
					definition = "default",
					label = "Close"
				}
			}
		}
	}
})

G_widget("panel", "naia_journeylog_panel", {
	left_border   = JOURNEYLOG_PANEL_PADDING,
	right_border  = JOURNEYLOG_PANEL_PADDING,
	top_border    = JOURNEYLOG_PANEL_PADDING,
	bottom_border = JOURNEYLOG_PANEL_PADDING,

	T.background {
		C_vcanvas(
			T.rectangle {
				x = 1,
				y = 1,
				w = "(width - 2)",
				h = "(height - 2)",
				border_thickness = 1,
				border_color = "0, 0, 0, 255",
				fill_color = "0, 0, 0, 127" -- GUI__BACKGROUND_COLOR_ENABLED
			},
			C_round_frame({ color = JOURNEYLOG_PANEL_BORDER_COLOR })
		)
	},
	T.foreground {
		T.draw {}
	}
})

G_widget("panel", "naia_journeylog_panel_map", {
	left_border   = JOURNEYLOG_PANEL_PADDING,
	right_border  = JOURNEYLOG_PANEL_PADDING,
	top_border    = JOURNEYLOG_PANEL_PADDING,
	bottom_border = JOURNEYLOG_PANEL_PADDING,

	T.background {
		C_vcanvas(
		    T.rectangle {
				x = 1,
				y = 1,
				w = "(width - 2)",
				h = "(height - 2)",
				border_thickness = 1,
				border_color = "0, 0, 0, 255",
				fill_color = "0, 0, 0, 127" -- GUI__BACKGROUND_COLOR_ENABLED
			},
			T.image {
				x = 4,
				y = 4,
				w = "(width - 8)",
				h = "(height - 8)",
				border_thickness = 1,
				resize_mode="stretch",
				border_color = "0, 0, 0, 255",
				name = "maps/background.webp",
			},
            T.image {
	x = "((width - max(640, min(width - 8, (height - 8) * 4 / 3))) / 2)",
	y = "((height - max(480, min(height - 8, (width - 8) * 3 / 4))) / 2)",

	w = "(max(640, min(width - 8, (height - 8) * 4 / 3)))",
	h = "(max(480, min(height - 8, (width - 8) * 3 / 4)))",

	border_thickness = 1,
	resize_mode = "stretch",
	border_color = "0, 0, 0, 255",

	name = "story/map/green_isle_old_esten.webp",
},
			C_round_frame({ color = JOURNEYLOG_PANEL_BORDER_COLOR })
		)
	},
    T.foreground {
		C_vcanvas {}
	}
})

local function journeylog_bio_portrait_canvas_image(image_func, resize_mode)
	-- HACK:
	-- resize_mode is not a formula, so we cannot use a formula to define
	-- whether an image should be smoothly interpolated (portraits) or NN'd
	-- (sprites). HOWEVER, name IS a formula, so we render two variants of
	-- each image instead, with one being set to an empty pathname if it seems
	-- like the wrong variant for the image type in question.
	return T.image {
		name = string.format([[(
			if(resize_mode = 'scale' and is_portrait = 1,
				img_path,
				if(resize_mode = 'scale_sharp' and is_portrait = 0,
					img_path,
					''
				))
			where img_path = '[text]%s',
				  resize_mode = '%s',
				  is_portrait = (find_string(text, 'portraits/') = 0)
			)]], image_func, resize_mode),
		resize_mode = resize_mode,
		x = "(if(image_original_width < width, (width - image_original_width)/2, 0))",
		y = "(if(image_original_width < height, (height - image_original_height)/2, 0))",
		-- BIG TODO: scale images proportionally if they don't fit
		w = "(min(image_original_width, width) * image_original_width/image_original_height)",
		h = "(min(image_original_height, height))",
	}
end

local function journeylog_bio_portrait_canvas(params)
	local border = params.border or "114, 79, 46, 92"
	local bg = params.bg or "0, 0, 0, 127"
	local image_func = params.image_func or ""

	return C_vcanvas(
		T.rectangle {
			w = "(width)",
			h = "(height)",
			fill_color = bg
		},
		journeylog_bio_portrait_canvas_image(image_func, 'scale'),
		journeylog_bio_portrait_canvas_image(image_func, 'scale_sharp'),
		T.rectangle {
			x = 1,
			y = 1,
			w = "(width - 2)",
			h = "(height - 2)",
			border_thickness = 1,
			border_color = "0, 0, 0, 255",
		},
		C_round_frame({ color = border })
	)
end

local function journeylog_bio_portrait_widget_def(widget_size)
	return {
		min_width         = widget_size,
		min_height        = widget_size,
		default_width     = widget_size,
		default_height    = widget_size,
		max_width         = 0,
		max_height        = widget_size,

		text_extra_width  = 0,
		text_extra_height = 0,
		text_font_size    = 0,

		T.state_enabled {
			journeylog_bio_portrait_canvas({})
		},
		T.state_disabled {
			journeylog_bio_portrait_canvas({
				border = "79, 79, 79, 92",
				image_func =  "~GS()~O(0.6)"
			})
		},
		T.state_pressed {
			journeylog_bio_portrait_canvas({
				image_func = "~BLEND(0,0,0,0.08)"
			})
		},
		T.state_focused {
			journeylog_bio_portrait_canvas({
				border = "114, 79, 46, 110",
				bg = "18, 24, 40, 127",
				image_func = "~BLEND(255,255,255,0.02)"
			})
		}
	}
end

G_widget(
	"button",
	"naia_journeylog_image_viewer_button",
	journeylog_bio_portrait_widget_def(JOURNEYLOG_BIO_PORTRAIT_SIZE)
)

G_widget(
	"button",
	"naia_journeylog_image_viewer_button_small",
	journeylog_bio_portrait_widget_def(JOURNEYLOG_BIO_SMALL_PORTRAIT_SIZE)
)

local function journeylog_scroll_canvas(vertical, params)
	local groove_color = params.groove_color or JOURNEYLOG_SCROLLBAR_GROOVE_COLOR
	local slider_color = params.slider_color or JOURNEYLOG_SCROLLBAR_SLIDER_COLOR

	local x, y, w, h = 0, 0, "(width)", "(height)"
	local edge1 = { x1 = 0, y1 = 0, x2 = 0, y2 = 0, thickness = 1, color = slider_color }
	local edge2 = { x1 = 0, y1 = 0, x2 = 0, y2 = 0, thickness = 1, color = slider_color }

	if vertical then
		y = "(positioner_offset + 1)"
		h = "(max(0, positioner_length - 2))"

		edge1.x1 = 1
		edge1.x2 = "(width - 2)"
		edge1.y1 = "(positioner_offset)"
		edge1.y2 = edge1.y1

		edge2.x1 = edge1.x1
		edge2.x2 = edge1.x2
		edge2.y1 = "(positioner_offset + positioner_length - 1)"
		edge2.y2 = edge2.y1
	else
		x = "(positioner_offset + 1)"
		w = "(max(0, positioner_length - 2))"

		edge1.x1 = "(positioner_offset)"
		edge1.x2 = edge1.x1
		edge1.y1 = 1
		edge1.y2 = "(height - 2)"

		edge2.x1 = "(positioner_offset + positioner_length - 1)"
		edge2.x2 = edge2.x1
		edge2.y1 = edge1.y1
		edge2.y2 = edge1.y2
	end

	return T.draw {
		-- Groove
		T.rectangle {
			x = 0,
			y = 0,
			w = "(width)",
			h = "(height)",
			fill_color = groove_color
		},
		-- Positioner
		T.line(edge1),
		T.rectangle {
			x = x,
			y = y,
			w = w,
			h = h,
			fill_color = slider_color
		},
		T.line(edge2)
	}
end

local function journeylog_hscroll_canvas(params)
	return journeylog_scroll_canvas(false, params)
end

local function journeylog_vscroll_canvas(params)
	return journeylog_scroll_canvas(true, params)
end

G_widget("horizontal_scrollbar", "naia_journeylog_viewer_hscroll", {
	min_width         = 20,
	min_height        = JOURNEYLOG_SCROLLBAR_THICKNESS,
	default_width     = 20,
	default_height    = JOURNEYLOG_SCROLLBAR_THICKNESS,
	max_width         = 0,
	max_height        = JOURNEYLOG_SCROLLBAR_THICKNESS,
	left_offset       = 0,
	right_offset      = 0,
	minimum_positioner_length = JOURNEYLOG_SCROLLBAR_POSITIONER_LENGTH,

	T.state_enabled {
		journeylog_hscroll_canvas({})
	},
	T.state_disabled {
		T.draw {}
	},
	T.state_pressed {
		journeylog_hscroll_canvas({
			groove_color = JOURNEYLOG_SCROLLBAR_GROOVE_COLOR_HOVER,
			slider_color = JOURNEYLOG_SCROLLBAR_SLIDER_COLOR_HOVER
		})
	},
	T.state_focused {
		journeylog_hscroll_canvas({
			groove_color = JOURNEYLOG_SCROLLBAR_GROOVE_COLOR_HOVER,
			slider_color = JOURNEYLOG_SCROLLBAR_SLIDER_COLOR_HOVER
		})
	}
})

G_widget("vertical_scrollbar", "naia_journeylog_viewer_vscroll", {
	min_width         = JOURNEYLOG_SCROLLBAR_THICKNESS,
	min_height        = 20,
	default_width     = JOURNEYLOG_SCROLLBAR_THICKNESS,
	default_height    = 20,
	max_width         = JOURNEYLOG_SCROLLBAR_THICKNESS,
	max_height        = 0,
	top_offset        = 0,
	bottom_offset     = 0,
	minimum_positioner_length = JOURNEYLOG_SCROLLBAR_POSITIONER_LENGTH,

	T.state_enabled {
		journeylog_vscroll_canvas({})
	},
	T.state_disabled {
		T.draw {}
	},
	T.state_pressed {
		journeylog_vscroll_canvas({
			groove_color = JOURNEYLOG_SCROLLBAR_GROOVE_COLOR_HOVER,
			slider_color = JOURNEYLOG_SCROLLBAR_SLIDER_COLOR_HOVER
		})
	},
	T.state_focused {
		journeylog_vscroll_canvas({
			groove_color = JOURNEYLOG_SCROLLBAR_GROOVE_COLOR_HOVER,
			slider_color = JOURNEYLOG_SCROLLBAR_SLIDER_COLOR_HOVER
		})
	}
})

local JOURNEYLOG_VIEWER_GRID = T.grid {
	T.row {
		grow_factor = 1,
		T.column {
			grow_factor = 1,
			horizontal_grow = true,
			vertical_grow = true,
			T.grid {
				id = "_content_grid"
			}
		},
		T.column {
			grow_factor = 0,
			vertical_grow = true,
			G_vscrollbar("naia_journeylog_viewer_vscroll", "left", 3)
		}
	},
	T.row {
		grow_factor = 0,
		T.column {
			horizontal_grow = true,
			G_hscrollbar("naia_journeylog_viewer_hscroll", "top", 3)
		},
		T.column {
			T.spacer {}
		}
	}
}

local JOURNEYLOG_LISTBOX_GRID = T.grid {
	T.row {
		grow_factor = 0,
		T.column {
			grow_factor = 1,
			horizontal_grow = true,
			vertical_grow = true,
			T.grid {
				id = "_header_grid"
			}
		},
		T.column {
			T.spacer {}
		}
	},
	T.row {
		grow_factor = 1,
		T.column {
			grow_factor = 1,
			horizontal_grow = true,
			vertical_grow = true,
			T.grid {
				id = "_content_grid",
				T.row {
					T.column {
						horizontal_grow = true,
						vertical_grow = true,
						T.grid {
							id = "_list_grid"
						}
					}
				}
			}
		},
		T.column {
			grow_factor = 0,
			vertical_grow = true,
			G_vscrollbar("naia_journeylog_viewer_vscroll", "left", 3)
		}
	},
	T.row {
		grow_factor = 0,
		T.column {
			grow_factor = 1,
			horizontal_grow = true,
			vertical_grow = true,
			T.grid {
				id = "_footer_grid"
			}
		},
		T.column {
			T.spacer {}
		}
	},
	T.row {
		grow_factor = 0,
		T.column {
			horizontal_grow = true,
			G_hscrollbar("naia_journeylog_viewer_hscroll", "top", 3)
		},
		T.column {
			T.spacer {}
		}
	}
}

G_widget("tree_view", "naia_journeylog_viewer", {
	min_width         = 0,
	min_height        = 0,
	default_width     = 0,
	default_height    = 0,
	max_width         = 0,
	max_height        = 0,

	text_font_size    = 0,
	text_font_style   = "",

	T.state_enabled { T.draw {} },
	T.state_disabled { T.draw {} },

	JOURNEYLOG_VIEWER_GRID,
})

G_widget("listbox", "naia_journeylog_listbox", {
	min_width         = 0,
	min_height        = 0,
	default_width     = 0,
	default_height    = 0,
	max_width         = 0,
	max_height        = 0,

	text_font_size    = 0,
	text_font_style   = "",

	T.state_enabled { T.draw {} },
	T.state_disabled { T.draw {} },

	JOURNEYLOG_LISTBOX_GRID,
})

G_widget("scrollbar_panel", "naia_journeylog_scrollbar_panel", {
	T.background { T.draw {} },
	T.foreground { T.draw {} },

	JOURNEYLOG_VIEWER_GRID,
})

local function journeylog_dialog_line_canvas(font_size, text_color)
	return T.draw {
		T.text {
			x               = 0,
			y               = 0,
			w               = "(width)",
			h               = "(text_height)",
			maximum_width   = "(width)",
			font_family     = "",
			font_size       = font_size,
			font_style      = "",
			color           = string.format("([%s, text_alpha])", text_color),
			text            = "(text)",
			text_markup     = "(text_markup)",
			text_alignment  = "(text_alignment)",
			text_link_aware = "(text_link_aware)",
			text_link_color = "(text_link_color)"
		}
	}
end

local function journeylog_dialog_line_widget_def(font_size, width, color)
	return {
		min_width        = 0,
		min_height       = 0,
		default_width    = width,
		default_height   = 0,
		max_width        = width,
		max_height       = 0,
		text_font_family = "",
		text_font_size   = font_size,
		text_font_style  = "",
		link_color       = "255, 255, 0",

		T.state_enabled {
			-- GUI__FONT_COLOR_ENABLED__DEFAULT
			journeylog_dialog_line_canvas(font_size, color)
		},
		T.state_disabled {
			-- GUI__FONT_COLOR_DISABLED__DEFAULT
			journeylog_dialog_line_canvas(font_size, "128, 128, 128")
		}
	}
end

G_widget(
	"label",
	"naia_journeylog_achievement_title",
	journeylog_dialog_line_widget_def(17, JOURNEYLOG_MESSAGE_WIDTH, JOURNEYLOG_SPEAKER_COLOR)
)

G_widget(
	"label",
	"naia_journeylog_dialog_line",
	journeylog_dialog_line_widget_def(17, JOURNEYLOG_MESSAGE_WIDTH, JOURNEYLOG_DIALOG_COLOR)
)

G_widget(
	"label",
	"naia_journeylog_dialog_speaker",
	journeylog_dialog_line_widget_def(20, JOURNEYLOG_MESSAGE_WIDTH, JOURNEYLOG_SPEAKER_COLOR)
)

G_widget(
	"label",
	"naia_journeylog_dialog_speaker_inline",
	journeylog_dialog_line_widget_def(17, JOURNEYLOG_SPEAKER_WIDTH, JOURNEYLOG_SPEAKER_COLOR)
)

G_widget(
	"label",
	"naia_journeylog_page",
	journeylog_dialog_line_widget_def(17, JOURNEYLOG_PAGE_WIDTH, JOURNEYLOG_DIALOG_COLOR)
)

G_widget(
	"label",
	"naia_journeylog_event_heading",
	journeylog_dialog_line_widget_def(17, JOURNEYLOG_PAGE_WIDTH, JOURNEYLOG_SPEAKER_COLOR)
)

G_widget(
	"label",
	"naia_journeylog_bio_label",
	journeylog_dialog_line_widget_def(15, 100, JOURNEYLOG_SPEAKER_COLOR)
)

G_widget(
	"label",
	"naia_journeylog_bio_text",
	journeylog_dialog_line_widget_def(15, 320, JOURNEYLOG_DIALOG_COLOR)
)

G_widget("progress_bar", "naia_journeylog_achievements_overall_progress", {
	min_width      = 14,
	min_height     = 10,
	default_width  = 14,
	default_height = 10,
	max_width      = 0,
	max_height     = 0,

	T.state_enabled {
		T.draw {
			T.rectangle {
				x = 0,
				y = 0,
				w = "(width)",
				h = "(height)",
				border_thickness = 1,
				-- GUI__BORDER_COLOR_DARK
				border_color = "114, 79, 46, 255"
			},
			T.rectangle {
				x = 1,
				y = 1,
				w = "(width - 2)",
				h = "(height - 2)",
				-- GUI__BACKGROUND_COLOR_ENABLED
				fill_color = "0, 0, 0, 89"
			},
			T.rectangle {
				x = 2,
				y = 2,
				w = "(((width - 4) * percentage) / 100)",
				h = "(height - 4)",
				fill_color = "0, 55, 82, 255"
			}
		}
	}
})

local function mini_button_text(text, color)
	return T.text {
		x               = 0,
		y               = "(max((height - text_height - 2) / 2, 0))",
		w               = "(width)",
		h               = "(text_height)",
		maximum_width   = "(width)",
		font_size       = 20,
		font_style      = "bold",
		color           = ("%s, 255"):format(color),
		text            = text,
		text_markup     = false,
		text_alignment  = "center"
	}
end

local function G_mini_button(id, label)
	G_widget("button", id, {
		min_width         = 30,
		min_height        = 30,
		default_width     = 30,
		default_height    = 30,
		max_width         = 30,
		max_height        = 30,
		text_extra_width  = 0,
		text_extra_height = 0,
		text_font_size    = 20,

		T.state_enabled {
			C_vcanvas(
				C_button_frame({
					background_image_path = "background",
					border_color          = "162, 127, 68, 255",   -- GUI__BORDER_COLOR
					border_color_dark     = "114, 79, 46, 255",    -- GUI__BORDER_COLOR_DARK
					highlight_line_color  = "21, 79, 109, 255"
				}),
				mini_button_text(label, INTRO_TEXT_COLOR)
			)
		},
		T.state_focused {
			C_vcanvas(
				C_button_frame({
					background_image_path = "background-active",
					border_color          = "162, 127, 68, 255",   -- GUI__BORDER_COLOR
					border_color_dark     = "114, 79, 46, 255",    -- GUI__BORDER_COLOR_DARK
					highlight_line_color  = "12, 108, 157, 255"
				}),
				mini_button_text(label, INTRO_TEXT_COLOR)
			)
		},
		T.state_pressed {
			C_vcanvas(
				C_button_frame({
					background_image_path = "background-pressed",
					border_color          = "162, 127, 68, 255",   -- GUI__BORDER_COLOR
					border_color_dark     = "114, 79, 46, 255",    -- GUI__BORDER_COLOR_DARK
					highlight_line_color  = "1, 10, 16, 255"
				}),
				mini_button_text(label, INTRO_TEXT_COLOR)
			)
		},
		T.state_disabled {
			C_vcanvas(
				C_button_frame({
					background_image_path = "background",
					border_color          = "128, 128, 128, 255",  -- GUI__FONT_COLOR_DISABLED__DEFAULT
					border_color_dark     = "89, 89, 89, 255",
					highlight_line_color  = "60, 60, 60, 255",
					ipf                   = "~GS()"
				}),
				mini_button_text(label, "128, 128, 128")
			)
		}
	})
end

G_mini_button("naia_mini_close", "×")
G_mini_button("naia_mini_ok",    "✓")
