local T = wml.tag
local _ = wesnoth.textdomain "wesnoth-ctl"

--###########################################################################################################################################################
--                                                                    CONSTANTS
--###########################################################################################################################################################
local WIDGET_FILE = "~add-ons/Chasing_the_Light/gui/widget/objectives.cfg"

local WIDGET_KINDS = {
	window_definition = "window",
	button_definition = "button",
}

local QUEST_SLOTS = 32
local ITEM_SLOTS  = { "tiara", "crossbow", "gem", "fish", "zelembia" }

local COLUMN_WIDTH = 400
local COLUMN_GAP   = 26
local SHEET_BORDER = 18

local MAIN_WRAP  = 92
local ENTRY_WRAP = 46
local NOTE_WRAP  = 60

local HANGING = "   "

local ORNAMENT = "icons/banner3_popup.png"

local COLOR = {
	main    = "#efdca6",
	heading = "#baac7d",
	counter = "#8a8270",
	active  = "#d7d7d7",
	done    = "#7f9163",
	rest    = "#6a6458",
	defeat  = "#c2695a",
	note    = "#8a8270",
}

local GLYPH = {
	main   = "<span font_family='DejaVu Sans'>✦</span>",
	active = "•",
	done   = "<span font_family='DejaVu Sans'>✔</span>",
	defeat = "<span font_family='DejaVu Sans'>✘</span>",
	note   = "•",
}

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
		wesnoth.log("err", "[CtL] objectives widgets failed to register: " .. tostring(err))
		return false
	end

	registered = true
	return true
end

--###########################################################################################################################################################
--                                                                       TEXT
--###########################################################################################################################################################
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

local function is_done(text)
	return text:find("strikethrough", 1, true) ~= nil
end

local function undress(text)
	local s = text:gsub("<span[^>]*strikethrough[^>]*>", "")
	s = s:gsub("</span>%s*$", "")
	return s
end

local function fold(text, budget)
	return (soft_wrap(text, budget):gsub("\n", "\n" .. HANGING))
end

local function entry(color, glyph, text)
	return ("<span color='%s'>%s %s</span>"):format(color, glyph, fold(text, ENTRY_WRAP))
end

local function heading(text, counter)
	local s = ("<span color='%s'><b>%s</b></span>"):format(COLOR.heading, tostring(text))
	if counter then
		s = s .. ("   <span color='%s'><small>%s</small></span>"):format(COLOR.counter, counter)
	end
	return s
end

local function remainder(count)
	return ("<span color='%s'><small><i>%s %d</i></small></span>")
		:format(COLOR.rest, fold(tostring(_ "Yet to be discovered:"), NOTE_WRAP), count)
end

--###########################################################################################################################################################
--                                                                     CONTENT
--###########################################################################################################################################################
local function main_line()
	local main = tostring(wml.variables["s9_quest_main"] or "")
	if main == "" then return nil end

	return ("<span size='large' color='%s'><b>%s  %s</b></span>")
		:format(COLOR.main, GLYPH.main, fold(main, MAIN_WRAP))
end

local function quest_pane()
	local v = wml.variables
	local unknown = tostring(_ "Unknown quest")
	local out = {}

	local listed, hidden = {}, 0
	for i = 1, QUEST_SLOTS do
		local q = v["s9_quest_" .. i]
		if q == nil then break end
		q = tostring(q)
		if q == "" or q == unknown then
			hidden = hidden + 1
		else
			listed[#listed + 1] = q
		end
	end

	if #listed == 0 and hidden == 0 then return nil end

	local done_n = tonumber(v["stormvale_quests_completed"]) or 0
	local max_n  = tonumber(v["stormvale_quests_max"]) or (#listed + hidden)

	out[#out + 1] = heading(_ "Quests:", ("%d / %d"):format(done_n, max_n))

	for _i, q in ipairs(listed) do
		if is_done(q) then
			out[#out + 1] = entry(COLOR.done, GLYPH.done, undress(q))
		else
			out[#out + 1] = entry(COLOR.active, GLYPH.active, q)
		end
	end

	if hidden > 0 then
		out[#out + 1] = remainder(hidden)
	end

	return table.concat(out, "\n")
end

local function aside_pane()
	local v = wml.variables
	local unknown = tostring(_ "Unknown item")
	local out = {}

	local listed, hidden = {}, 0
	for _i, slot in ipairs(ITEM_SLOTS) do
		local it = v["s9_item_" .. slot]
		if it ~= nil then
			it = tostring(it)
			if it == "" or it == unknown then
				hidden = hidden + 1
			else
				listed[#listed + 1] = it
			end
		end
	end

	if #listed + hidden > 0 then
		out[#out + 1] = heading(_ "Found Items:", ("%d / %d"):format(#listed, #listed + hidden))
		for _i, it in ipairs(listed) do
			out[#out + 1] = entry(COLOR.done, GLYPH.done, it)
		end
		if hidden > 0 then
			out[#out + 1] = remainder(hidden)
		end
		out[#out + 1] = ""
	end

	out[#out + 1] = heading(_ "Defeat:")
	out[#out + 1] = entry(COLOR.defeat, GLYPH.defeat, tostring(_ "Death of Daeola"))
	out[#out + 1] = ""

	out[#out + 1] = heading(_ "Notes:")
	local notes = {
		_ "Quests are optional.",
		_ "Completing quests can give rewards in the next scenarios.",
		_ "Units who can give quests are marked with a hero crown.",
		_ "Daeola is able to open doors and gates.",
	}
	for _i, note in ipairs(notes) do
		out[#out + 1] = ("<span color='%s'><small>%s %s</small></span>")
			:format(COLOR.note, GLYPH.note, fold(tostring(note), NOTE_WRAP))
	end

	return table.concat(out, "\n")
end

local function flatten(main, left, right)
	local out = {}
	for _i, block in ipairs({ main or "", left or "", right or "" }) do
		if block ~= "" then out[#out + 1] = block end
	end
	return table.concat(out, "\n\n")
end

--###########################################################################################################################################################
--                                                                      LAYOUT
--###########################################################################################################################################################
local function pane(text, chrome)
	return T.grid {
		T.row {
			grow_factor = 0,
			T.column { T.spacer { width = COLUMN_WIDTH, height = 1 } },
		},
		T.row {
			grow_factor = 1,
			T.column {
				horizontal_grow = true,
				vertical_grow = true,
				T.scroll_label {
					definition = chrome and "wml_message" or "default",
					use_markup = true,
					wrap = true,
					horizontal_scrollbar_mode = "never",
					vertical_scrollbar_mode = "auto",
					label = text,
				},
			},
		},
	}
end

local function sheet(main, left, right, chrome)
	local rows = {}

	table.insert(rows, T.row {
		grow_factor = 0,
		T.column {
			horizontal_alignment = "center",
			T.label {
				definition = "title",
				use_markup = true,
				label = tostring(_ "Objectives"),
			},
		},
	})

	if chrome then
		table.insert(rows, T.row {
			grow_factor = 0,
			T.column {
				horizontal_alignment = "center",
				border = "top,bottom",
				border_size = 8,
				T.image { label = ORNAMENT },
			},
		})
	end

	if main then
		table.insert(rows, T.row {
			grow_factor = 0,
			T.column {
				horizontal_alignment = "center",
				border = "bottom",
				border_size = 16,
				T.label { use_markup = true, label = main },
			},
		})
	end

	local cells = {}
	if left then
		table.insert(cells, T.column {
			grow_factor = 1,
			horizontal_grow = true,
			vertical_grow = true,
			border = "right",
			border_size = COLUMN_GAP,
			pane(left, chrome),
		})
	end
	table.insert(cells, T.column {
		grow_factor = 1,
		horizontal_grow = true,
		vertical_grow = true,
		pane(right, chrome),
	})

	table.insert(rows, T.row {
		grow_factor = 1,
		T.column {
			horizontal_grow = true,
			vertical_grow = true,
			T.grid { T.row(cells) },
		},
	})

	table.insert(rows, T.row {
		grow_factor = 0,
		T.column {
			horizontal_alignment = "center",
			border = "top",
			border_size = 18,
			T.button {
				id = "ctl_objectives_ok",
				definition = chrome and "ctl_objectives_close" or "default",
				return_value = 1,
				use_markup = true,
				label = tostring(_ "Close"),
			},
		},
	})

	return T.grid(rows)
end

local function scene(main, left, right, chrome)
	local content = sheet(main, left, right, chrome)

	if not chrome then
		return {
			definition = "menu",
			T.tooltip { id = "tooltip_large" },
			T.helptip { id = "tooltip_large" },
			T.grid { T.row { T.column { border = "all", border_size = 16, content } } },
		}
	end

	return {
		definition = "ctl_objectives",
		maximum_width = "(min(1120, screen_width - 60))",
		maximum_height = "(screen_height - 60)",

		T.tooltip { id = "tooltip" },
		T.helptip { id = "tooltip" },

		T.grid {
			T.row {
				grow_factor = 1,
				T.column {
					horizontal_grow = true,
					vertical_grow = true,
					border = "all",
					border_size = SHEET_BORDER,
					content,
				},
			},
		},
	}
end

local LEVELS = {
	{ name = "sheet", chrome = true  },
	{ name = "plain", chrome = false },
}

local function present(main, left, right)
	for _i, level in ipairs(LEVELS) do
		if not level.chrome or register() then
			local built, dlg = pcall(scene, main, left, right, level.chrome)
			if not built then
				wesnoth.log("err", ("[CtL] objectives level %s did not build: %s")
					:format(level.name, tostring(dlg)))
			else
				local ok, err = pcall(gui.show_dialog, dlg)
				if ok then return true end
				wesnoth.log("err", ("[CtL] objectives level %s failed to show: %s")
					:format(level.name, tostring(err)))
			end
		end
	end

	return false
end

--###########################################################################################################################################################
--                                                                    WML TAGS
--###########################################################################################################################################################
local function compose()
	local main  = main_line()
	local left  = quest_pane()
	local right = aside_pane()

	wesnoth.wml_actions.objectives {
		silent = true,
		note = flatten(main, left, right),
	}

	return main, left, right
end

function wesnoth.wml_actions.s9_objectives(cfg)
	local main, left, right = compose()

	if not cfg.silent then
		present(main, left, right)
	end
end

function wesnoth.wml_actions.s9_show_objectives(cfg)
	present(compose())
end
