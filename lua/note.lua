-- #textdomain wesnoth-ctl

local T = wml.tag
local wml_actions = wesnoth.wml_actions
local _ = wesnoth.textdomain "wesnoth-ctl"
local utils = wesnoth.require "wml-utils"

local function get_pango_color(color)
	local pango_color = "#"

	-- if a hex color was passed in
	-- or if a color string was passed in - contains no non-letter characters
	-- just use that
	if string.sub(color, 1, 1) == "#" or not string.match(color, "%A+") then
		pango_color = color
	-- decimal color was passed in, convert to hex color for pango
	else
		for s in string.gmatch(color, "%d+") do
			pango_color = pango_color .. tonumber(s, 16)
		end
	end

	return pango_color
end

-- add formatting
local function add_formatting(cfg, text)
	-- span tag
	local formatting = "<span"

	-- if message text, add formatting
	if text and cfg then
		-- add font
		if cfg.font and cfg.font ~= '' then
			formatting = formatting .. " font='" .. cfg.font .. "'"
		end

		-- add font_family
		if cfg.font_family and cfg.font_family ~= '' then
			formatting = formatting .. " font_family='" .. cfg.font_family .. "'"
		end

		-- add font_size
		if cfg.font_size and cfg.font_size ~= '' then
			local font_size = cfg.font_size
			if type(font_size) == 'number' then
				if font_size > 1024 then
					wesnoth.deprecated_message("font_size units", 3, '1.16', "Specifying [message]font_size= in 1/1024ths of a point is deprecated. Specify it as points instead.")
				else
					-- Pango expects 1/1024ths of a point here
					font_size = font_size * 1024
				end
			end
			formatting = formatting .. " font_size='" .. font_size .. "'"
		end

		-- font_style
		if cfg.font_style and cfg.font_style ~= '' then
			formatting = formatting .. " font_style='" .. cfg.font_style .. "'"
		end

		-- font_weight
		if cfg.font_weight and cfg.font_weight ~= '' then
			formatting = formatting .. " font_weight='" .. cfg.font_weight .. "'"
		end

		-- font_variant
		if cfg.font_variant and cfg.font_variant ~= '' then
			formatting = formatting .. " font_variant='" .. cfg.font_variant .. "'"
		end

		-- font_stretch
		if cfg.font_stretch and cfg.font_stretch ~= '' then
			formatting = formatting .. " font_stretch='" .. cfg.font_stretch .. "'"
		end

		-- add color
		if cfg.color and cfg.color ~= '' then
			formatting = formatting .. " color='" .. get_pango_color(cfg.color) .. "'"
		end

		-- bgcolor
		if cfg.bgcolor and cfg.bgcolor ~= '' then
			formatting = formatting .. " bgcolor='" .. get_pango_color(cfg.bgcolor) .. "'"
		end

		-- underline
		if cfg.underline and cfg.underline ~= '' then
			local underline
			if cfg.underline == true then
				underline = 'single'
			elseif cfg.underline == false then
				underline = 'none'
			else
				underline = cfg.underline
			end
			formatting = formatting .. " underline='" .. underline .. "'"
		end

		-- underline_color
		if cfg.underline_color and cfg.underline_color ~= '' then
			formatting = formatting .. " underline_color='" .. get_pango_color(cfg.underline_color) .. "'"
		end

		-- rise
		if cfg.rise and cfg.rise ~= '' then
			local rise = cfg.rise
			if type(rise) == 'number' then
				if rise > 1000 then
					wesnoth.deprecated_message("rise units", 3, '1.16', "Specifying [message]rise= in 1/10,000ths of an em is deprecated. Specify it as ems instead.")
				else
					-- Pango expects 1/10000ths of an em here
					rise = rise * 10000
				end
			end
			formatting = formatting .. " rise='" .. rise .. "'"
		end

		-- strikethrough
		if cfg.strikethrough and tostring(cfg.strikethrough) ~= '' then
			formatting = formatting .. " strikethrough='" .. tostring(cfg.strikethrough) .. "'"
		end

		-- strikethrough_color
		if cfg.strikethrough_color and cfg.strikethrough_color ~= '' then
			formatting = formatting .. " strikethrough_color='" .. get_pango_color(cfg.strikethrough_color) .. "'"
		end

		-- fallback
		if cfg.fallback and tostring(cfg.fallback) ~= '' then
			formatting = formatting .. " fallback='" .. tostring(cfg.fallback) .. "'"
		end

		-- letter_spacing
		if cfg.letter_spacing and cfg.letter_spacing ~= '' then
			local letter_spacing = cfg.letter_spacing
			if type(letter_spacing) == 'number' then
				if letter_spacing > 1024 then
					wesnoth.deprecated_message("letter_spacing units", 3, '1.16', "Specifying [message]letter_spacing= in 1/1024ths of a point is deprecated. Specify it as points instead.")
				else
					-- Pango expects 1/1024ths of a point here
					letter_spacing = letter_spacing * 1024
				end
			end
			formatting = formatting .. " letter_spacing='" .. letter_spacing .. "'"
		end

		-- gravity
		if cfg.gravity and cfg.gravity ~= '' then
			formatting = formatting .. " gravity='" .. cfg.gravity .. "'"
		end

		-- gravity_hint
		if cfg.gravity_hint and cfg.gravity_hint ~= '' then
			formatting = formatting .. " gravity_hint='" .. cfg.gravity_hint .. "'"
		end

		-- wrap in span tags and return if a color was added
		if formatting ~= "<span" then
			return formatting .. ">" .. text .. "</span>"
		end
	end

	-- or return unmodified message
	return text
end

function wml_actions.note_paper(cfg)

	 function pre_show(self)

	self.note_message.label = add_formatting(cfg, cfg.message)

    end

	local dialog_wml = wml.load "~add-ons/Chasing_the_Light/gui/note_paper.cfg"
	
	local paper_window = wml.load("~add-ons/Chasing_the_Light/gui/widget/window_transparent.cfg")
    gui.add_widget_definition("window", "transparent", wml.get_child(paper_window, 'window_definition'))
	
	local result = wesnoth.sync.evaluate_single(function()
		return { value = gui.show_dialog(wml.get_child(dialog_wml, 'resolution'), pre_show) }
	end)

	wesnoth.redraw {}
end