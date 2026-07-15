-- coords.lua — координатные преобразования экран → игровой мир
local config = require("main.Scripts.config")
local M = {}

-- Преобразование экранных координат в игровые без камеры (fixed_fit_projection)
function M.screen_to_world(x, y)
    local w, h = window.get_size()
    w = w / (w / config.DISPLAY_WIDTH)
    h = h / (h / config.DISPLAY_HEIGHT)

    local zoom = math.min(w / config.DISPLAY_WIDTH, h / config.DISPLAY_HEIGHT)
    local offset_x = (w - config.DISPLAY_WIDTH * zoom) / 2
    local offset_y = (h - config.DISPLAY_HEIGHT * zoom) / 2

    local norm_x = (2 * x / w) - 1
    local norm_y = (2 * y / h) - 1

    local world_x = (norm_x + 1) * (config.DISPLAY_WIDTH / 2)
    local world_y = (norm_y + 1) * (config.DISPLAY_HEIGHT / 2)

    world_x = (world_x - offset_x / zoom)
    world_y = (world_y - offset_y / zoom)

    return world_x, world_y
end

return M
