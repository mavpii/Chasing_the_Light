local T = wml.tag
local _ = wesnoth.textdomain "wesnoth-ctl"

--###########################################################################################################################################################
--                                                                    CONSTANTS
--###########################################################################################################################################################
local WIDGET_FILE = "~add-ons/Chasing_the_Light/gui/widget/dialogue.cfg"

local WIDGET_KINDS = {
	window_definition = "window",
	panel_definition  = "panel",
	button_definition = "button",
}

local CHOICE_BASE = 100

local HINT_COLOR    = "#8a8270"

local TEXT_CHARS_PER_LINE = 78
local CHOICE_WRAP_CHARS   = 100

local PORTRAIT_SLOT   = 300

local BOX_MIN_HEIGHT = 58

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
		wesnoth.log("err", "[CtL] dialogue widgets failed to register: " .. tostring(err))
		return false
	end

	registered = true
	return true
end

--###########################################################################################################################################################
--                                                                       TEXT
--###########################################################################################################################################################
local function colour(hex, s)
	return ("<span color='%s'>%s</span>"):format(hex, s)
end

local function soft_wrap(text, budget)
	local out = {}
	local visible, last_space, visible_at_space, in_tag = 0, nil, 0, false

	for i = 1, #text do
		local c = text:sub(i, i)
		out[i] = c

		if c == "<" then
			in_tag = true
		elseif c == ">" then
			in_tag = false
		elseif not in_tag then
			if c == "\n" then
				visible, last_space = 0, nil
			elseif c:byte() < 0x80 or c:byte() >= 0xC0 then
				visible = visible + 1
				if c == " " then
					last_space, visible_at_space = i, visible
				end
			end
		end

		if visible > budget and last_space then
			out[last_space] = "\n"
			visible = visible - visible_at_space
			last_space = nil
		end
	end

	return table.concat(out)
end

--###########################################################################################################################################################
--                                                                      LAYOUT
--###########################################################################################################################################################
local function portrait_layer(image, mirror, side)
	local path = tostring(image)
	if mirror then path = path .. "~FL()" end

	return T.layer {
		T.row {
			grow_factor = 1,
			T.column {
				horizontal_alignment = side,
				vertical_alignment = "bottom",
				T.image { label = path },
			},
		},
	}
end

local function box_panel(msg, options, level)
	local rows = {}

	local title = msg.title and tostring(msg.title) or ""
	if title ~= "" then
		table.insert(rows, T.row {
			grow_factor = 0,
			T.column {
				horizontal_alignment = "left",
				border = "bottom",
				border_size = 6,
				T.label {
					definition = "title",
					use_markup = true,
					label = title,
				},
			},
		})
	end

	table.insert(rows, T.row {
		grow_factor = 1,
		T.column {
			horizontal_grow = true,
			vertical_alignment = "top",
			T.label {
				use_markup = true,
				wrap = true,
				characters_per_line = TEXT_CHARS_PER_LINE,
				label = msg.message and tostring(msg.message) or "",
			},
		},
	})

	for i, option in ipairs(options) do
		table.insert(rows, T.row {
			grow_factor = 0,
			T.column {
				horizontal_grow = true,
				border = "top",
				border_size = (i == 1) and 14 or 5,
				T.button {
					id = "ctl_choice_" .. i,
					definition = level.chrome and "ctl_dialogue_choice" or "default",
					return_value = CHOICE_BASE + i,
					label = soft_wrap(tostring(option.label or ""), CHOICE_WRAP_CHARS),
					tooltip = tostring(option.description or ""),
				},
			},
		})
	end

	if #options == 0 then
		table.insert(rows, T.row {
			grow_factor = 0,
			T.column {
				horizontal_alignment = "right",
				border = "top",
				border_size = 8,
				T.label {
					use_markup = true,
					label = colour(HINT_COLOR, ("<span size='small'>%s  &#9654;</span>")
						:format(tostring(_ "click to continue"))),
				},
			},
		})
	end

	local body = T.stacked_widget {
		T.layer {
			T.row {
				grow_factor = 1,
				T.column { T.spacer { width = 1, height = BOX_MIN_HEIGHT } },
			},
		},
		T.layer {
			T.row {
				grow_factor = 1,
				T.column {
					horizontal_grow = true,
					vertical_alignment = "top",
					T.grid(rows),
				},
			},
		},
	}

	if not level.chrome then
		return body
	end

	return T.panel {
		definition = "ctl_dialogue_box",
		T.grid { T.row { T.column { horizontal_grow = true, body } } },
	}
end

local function scene(msg, options, level)
	local portrait = msg.portrait and tostring(msg.portrait) or ""
	if portrait == "" or portrait == "none" then portrait = nil end

	local second = msg.second_portrait and tostring(msg.second_portrait) or ""
	if second == "" or second == "none" then second = nil end

	local on_left = (msg.left_side ~= false) or (second ~= nil)
	local show_art = level.portrait

	-- The slot is reserved whether or not anyone is standing in it, so the box
	-- always begins at the same place and keeps the same width.
	local function slot()
		return T.column {
			grow_factor = 0,
			T.spacer { width = PORTRAIT_SLOT, height = 1 },
		}
	end

	local box = T.column {
		grow_factor = 1,
		horizontal_grow = true,
		vertical_alignment = "bottom",
		border = "all",
		border_size = 10,
		box_panel(msg, options, level),
	}

	local cells = { grow_factor = 0 }
	if on_left then
		table.insert(cells, slot())
		table.insert(cells, box)
	else
		table.insert(cells, box)
		table.insert(cells, slot())
	end
	if second and show_art then
		table.insert(cells, slot())
	end

	local layers = {}
	if portrait and show_art then
		table.insert(layers, portrait_layer(portrait, msg.mirror, on_left and "left" or "right"))
	end
	if second and show_art then
		table.insert(layers, portrait_layer(second, msg.second_mirror, "right"))
	end

	table.insert(layers, T.layer {
		T.row {
			grow_factor = 1,
			T.column {
				horizontal_grow = true,
				vertical_alignment = "bottom",
				T.grid { T.row(cells) },
			},
		},
	})

	local dismissable = (#options == 0) and level.dismiss

	local dlg = {
		definition = level.chrome and (dismissable and "ctl_dialogue_dismiss" or "ctl_dialogue") or "default",
		automatic_placement = false,
		click_dismiss = dismissable and true or false,

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
								horizontal_grow = true,
								vertical_alignment = "bottom",
								T.stacked_widget(layers),
							},
						},
					},
				},
			},
		},
	}

	if level.placement == "map" then
		dlg.x = "(gamemap_x_offset)"
		dlg.y = 30
		dlg.width = "(gamemap_width)"
		dlg.height = "(screen_height - 30)"
	else
		dlg.x = 0
		dlg.y = 0
		dlg.width = "(screen_width)"
		dlg.height = "(screen_height)"
	end

	return dlg
end

local LEVELS = {
	{ name = "map+portrait+dismiss",    placement = "map",    portrait = true,  dismiss = true,  chrome = true },
	{ name = "screen+portrait+dismiss", placement = "screen", portrait = true,  dismiss = true,  chrome = true },
	{ name = "screen+portrait",         placement = "screen", portrait = true,  dismiss = false, chrome = true },
	{ name = "screen+panel",            placement = "screen", portrait = false, dismiss = false, chrome = true },
	{ name = "screen+plain",            placement = "screen", portrait = false, dismiss = false, chrome = false },
}

--###########################################################################################################################################################
--                                                                    NARRATION HOOK
--###########################################################################################################################################################
local fallback = gui.show_narration
local level_in_use = 1

local function unsupported(msg, options, text_input)
	if text_input ~= nil then return true end
	for _i, option in ipairs(options) do
		if option.image and tostring(option.image) ~= "" then return true end
	end
	return false
end

function gui.show_narration(msg, options, text_input)
	options = options or {}

	if unsupported(msg, options, text_input) or not register() then
		return fallback(msg, options, text_input)
	end

	local has_choices = #options > 0

	for _attempt = 1, 8 do
		local retval, shown = nil, false

		for i = level_in_use, #LEVELS do
	local level = LEVELS[i]
	local built, dlg = pcall(scene, msg, options, level)
	if not built then
		wesnoth.log("err", ("[CtL] dialogue level %s did not build: %s")
			:format(level.name, tostring(dlg)))
	else
		local ok, r = pcall(gui.show_dialog, dlg)
		if ok then
			if level_in_use ~= i then
				wesnoth.log("warning", "[CtL] dialogue level in use: " .. level.name)
				level_in_use = i
			end
			retval, shown = r, true
			break
		else
			wesnoth.log("err", ("[CtL] dialogue level %s failed to show: %s")
				:format(level.name, tostring(r)))
		end
	end
end

		if not shown then
			broken = true
			return fallback(msg, options, text_input)
		end

		retval = tonumber(retval) or 0

		if not has_choices then
			return (retval == -2) and -2 or 0
		end

		local picked = retval - CHOICE_BASE
		if picked >= 1 and picked <= #options then
			return picked
		end
	end

	return fallback(msg, options, text_input)
end
