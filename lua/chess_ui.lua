local T = wml.tag
local _ = wesnoth.textdomain "wesnoth-ctl"

--###########################################################################################################################################################
--                                                                    CONSTANTS
--###########################################################################################################################################################
local CHROME_MODULE = "~add-ons/Chasing_the_Light/lua/location_ui.lua"

local ART_WIDTH  = 420
local ART_HEIGHT = 420

local CLOSE = 1

--###########################################################################################################################################################
--                                                                   REGISTRATION
--###########################################################################################################################################################
local broken = false

local function register()
	if broken then return false end

	local ok, chrome = pcall(wesnoth.require, CHROME_MODULE)

	if not ok or type(chrome) ~= "table" or type(chrome.register) ~= "function" then
		broken = true
		wesnoth.log("err", "[CtL] chess popup cannot reach the location chrome: " .. tostring(chrome))
		return false
	end

	if not chrome.register() then
		broken = true
		return false
	end

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

local function card(msg, chrome)
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

	local image = msg.image and tostring(msg.image) or ""
	if image ~= "" and image ~= "none" then
		table.insert(rows, T.row {
			grow_factor = 1,
			T.column {
				horizontal_alignment = "center",
				vertical_alignment = "center",
				art(image),
			},
		})
	end

	table.insert(rows, T.row {
		grow_factor = 0,
		T.column {
			horizontal_alignment = "center",
			border = "top",
			border_size = 18,
			T.button {
				id = "ctl_chess_ok",
				definition = chrome and "ctl_location_choice" or "default",
				return_value = CLOSE,
				use_markup = true,
				label = tostring(_ "Close"),
			},
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

local function scene(msg, chrome)
	local content = card(msg, chrome)

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
--                                                                       SHOW
--###########################################################################################################################################################
local function present(msg)
	for _i, level in ipairs(LEVELS) do
		if not level.chrome or register() then
			local built, dlg = pcall(scene, msg, level.chrome)
			if not built then
				wesnoth.log("err", ("[CtL] chess level %s did not build: %s")
					:format(level.name, tostring(dlg)))
			else
				local ok, err = pcall(gui.show_dialog, dlg)
				if ok then return true end
				wesnoth.log("err", ("[CtL] chess level %s failed to show: %s")
					:format(level.name, tostring(err)))
			end
		end
	end

	return false
end

--###########################################################################################################################################################
--                                                                    WML TAGS
--###########################################################################################################################################################
function wesnoth.wml_actions.show_chess_moves(cfg)
	local msg = {
		title = cfg.title,
		image = cfg.image,
	}

	wesnoth.sync.evaluate_single(function()
		present(msg)
		return {}
	end)
end
