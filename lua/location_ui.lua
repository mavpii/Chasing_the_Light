local T = wml.tag
local _ = wesnoth.textdomain "wesnoth-ctl"

--###########################################################################################################################################################
--                                                                    CONSTANTS
--###########################################################################################################################################################
local WIDGET_FILE = "~add-ons/Chasing_the_Light/gui/widget/location.cfg"

local WIDGET_KINDS = {
	window_definition = "window",
	panel_definition  = "panel",
	button_definition = "button",
}

local ENTER   = 1
local DECLINE = 2

local ART_WIDTH  = 240
local ART_HEIGHT = 300

local TEXT_CHARS_PER_LINE = 72

local ART_GAP    = 24
local BUTTON_GAP = 14

--###########################################################################################################################################################
--                                                                   REGISTRATION
--###########################################################################################################################################################
local registered = false
local broken = false

local function register()
	if registered then return true end
	if broken then return false end

	local ok, err = pcall(function()
		local defs = wml.load(WIDGET_FILE)
		for tag, widget_type in pairs(WIDGET_KINDS) do
			for def in wml.child_range(defs, tag) do
				gui.add_widget_definition(widget_type, def.id, def)
			end
		end
	end)

	if not ok then
		broken = true
		wesnoth.log("err", "[CtL] location widgets failed to register: " .. tostring(err))
		return false
	end

	registered = true
	return true
end

--###########################################################################################################################################################
--                                                                      LAYOUT
--###########################################################################################################################################################
local function art(image)
	return T.drawing {
		width = ART_WIDTH,
		height = ART_HEIGHT,
		T.draw {
			T.image {
				name = image,
				w = ("(min(%d, (image_original_width * %d) / image_original_height))")
					:format(ART_WIDTH, ART_HEIGHT),
				h = ("(min(%d, (image_original_height * %d) / image_original_width))")
					:format(ART_HEIGHT, ART_WIDTH),
				x = "(width / 2 - image_width / 2)",
				y = "(height / 2 - image_height / 2)",
			},
		},
	}
end

local function card(msg, options, chrome)
	local rows = {}

	local title = msg.title and tostring(msg.title) or ""
	if title ~= "" then
		table.insert(rows, T.row {
			grow_factor = 0,
			T.column {
				horizontal_alignment = "center",
				border = "bottom",
				border_size = 14,
				T.label {
					definition = "title",
					use_markup = true,
					label = title,
				},
			},
		})
	end

	local body = {}

	local image = msg.image and tostring(msg.image) or ""
	if image ~= "" and image ~= "none" then
		table.insert(body, T.column {
			grow_factor = 0,
			vertical_alignment = "top",
			border = "right",
			border_size = ART_GAP,
			art(image),
		})
	end

	table.insert(body, T.column {
		grow_factor = 1,
		horizontal_grow = true,
		vertical_alignment = "top",
		T.label {
			use_markup = true,
			wrap = true,
			characters_per_line = TEXT_CHARS_PER_LINE,
			label = msg.message and tostring(msg.message) or "",
		},
	})

	table.insert(rows, T.row {
		grow_factor = 1,
		T.column {
			horizontal_grow = true,
			vertical_alignment = "top",
			T.grid { T.row(body) },
		},
	})

	local buttons = {}
	for i, option in ipairs(options) do
		table.insert(buttons, T.column {
			border = (i > 1) and "left" or nil,
			border_size = BUTTON_GAP,
			T.button {
				id = "ctl_location_choice_" .. i,
				definition = chrome and "ctl_location_choice" or "default",
				return_value = option.value,
				use_markup = true,
				label = tostring(option.label),
			},
		})
	end

	table.insert(rows, T.row {
		grow_factor = 0,
		T.column {
			horizontal_alignment = "center",
			border = "top",
			border_size = 20,
			T.grid { T.row(buttons) },
		},
	})

	if not chrome then
		return T.grid(rows)
	end

	return T.panel {
		definition = "ctl_location_box",
		T.grid { T.row { T.column { horizontal_grow = true, T.grid(rows) } } },
	}
end

local function scene(msg, options, chrome)
	local content = card(msg, options, chrome)

	if not chrome then
		return {
			definition = "menu",
			T.tooltip { id = "tooltip_large" },
			T.helptip { id = "tooltip_large" },
			T.grid { T.row { T.column { border = "all", border_size = 16, content } } },
		}
	end

	return {
		definition = "ctl_location",
		automatic_placement = false,
		x = 0,
		y = 0,
		width = "(screen_width)",
		height = "(screen_height)",

		T.tooltip { id = "tooltip" },
		T.helptip { id = "tooltip" },

		T.grid {
			T.row {
				grow_factor = 1,
				T.column {
					horizontal_grow = true,
					vertical_grow = true,
					T.grid {
						T.row {
							grow_factor = 1,
							T.column { T.spacer { width = 1, height = 1 } },
						},
						T.row {
							grow_factor = 0,
							T.column {
								horizontal_alignment = "center",
								vertical_alignment = "center",
								content,
							},
						},
						T.row {
							grow_factor = 1,
							T.column { T.spacer { width = 1, height = 1 } },
						},
					},
				},
			},
		},
	}
end

local LEVELS = {
	{ name = "card",  chrome = true  },
	{ name = "plain", chrome = false },
}

--###########################################################################################################################################################
--                                                                       ASK
--###########################################################################################################################################################
local function ask(msg, options)
	for _i, level in ipairs(LEVELS) do
		if not level.chrome or register() then
			local built, dlg = pcall(scene, msg, options, level.chrome)
			if not built then
				wesnoth.log("err", ("[CtL] location level %s did not build: %s")
					:format(level.name, tostring(dlg)))
			else
				local ok, retval = pcall(gui.show_dialog, dlg)
				if ok then
					return tonumber(retval) or DECLINE
				end
				wesnoth.log("err", ("[CtL] location level %s failed to show: %s")
					:format(level.name, tostring(retval)))
			end
		end
	end

	return DECLINE
end

--###########################################################################################################################################################
--                                                                    WML TAGS
--###########################################################################################################################################################
function wesnoth.wml_actions.change_location(cfg)
	local msg = {
		title   = cfg.title,
		message = cfg.message,
		image   = cfg.image,
	}

	local options
	if cfg.fake then
		options = {
			{ label = _ "Close", value = DECLINE },
		}
	else
		options = {
			{ label = _ "Yes, I'll come in now", value = ENTER },
			{ label = _ "No, maybe later",       value = DECLINE },
		}
	end

	local picked = wesnoth.sync.evaluate_single(function()
		return { value = ask(msg, options) }
	end)

	if not cfg.fake then
		wml.variables["s9_change_location"] = (tonumber(picked.value) == ENTER)
	end
end

return { register = register }
