mouse_handlers = {}

function register_mouse_handler(func)
    table.insert(mouse_handlers, func)
end

wesnoth.game_events.on_mouse_action = function(x, y)
    for _, handler in ipairs(mouse_handlers) do
        handler(x, y)
    end
end