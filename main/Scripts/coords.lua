-- coords.lua — экран → мир.
-- Defold fixed_fit_projection already delivers action.x/y in virtual 960×540
-- space. Unprojecting by window.get_size() double-applies letterbox and breaks
-- hit-tests on non-16:9 canvases. See docs/responsive-explained.md §2.
local M = {}

function M.screen_to_world(x, y)
    return x, y
end

return M
