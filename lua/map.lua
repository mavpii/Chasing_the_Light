local T = wml.tag
local wml_actions = wesnoth.wml_actions
local _ = wesnoth.textdomain "wesnoth-ctl"
local utils = wesnoth.require "wml-utils"

function wml_actions.caves_map(cfg)

    -- preload hook (на майбутнє, навіть якщо зараз не використовується)
    local function pre_show(self)
        -- тут можна буде щось додати пізніше
    end

    -- завантаження діалогу
    local dialog_wml = wml.load "~add-ons/Chasing_the_Light/gui/map.cfg"
    if not dialog_wml then
        wesnoth.error("Failed to load map.cfg")
    end

    local resolution = wml.get_child(dialog_wml, 'resolution')
    if not resolution then
        wesnoth.error("Missing [resolution] in map.cfg")
    end

    -- завантаження transparent window
    local map_window = wml.load "~add-ons/Chasing_the_Light/gui/widget/window_transparent.cfg"
    local window_def = wml.get_child(map_window, 'window_definition')
    if not window_def then
        wesnoth.error("Missing window_definition in window_transparent.cfg")
    end

    gui.add_widget_definition("window", "transparent", window_def)

    -- показ діалогу (як у note_paper)
    local result = wesnoth.sync.evaluate_single(function()
        return {
            value = gui.show_dialog(resolution, pre_show)
        }
    end)

    wesnoth.redraw {}
end