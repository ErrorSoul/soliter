-- Shared GUI button interaction. All button faces have unit root scale;
-- icon, label and decoration are children, so the entire control moves together.
local M = {}
local function pose(node, pressed)
    -- Animate only the visual child; the hit rectangle never shrinks.
    node = gui.get_node(node .. "_face")
    gui.cancel_animations(node, "scale")
    gui.animate(node, "scale", vmath.vector3(pressed and 0.94 or 1, pressed and 0.94 or 1, 1),
        pressed and gui.EASING_OUTQUAD or gui.EASING_OUTBACK, pressed and 0.07 or 0.16)
end

local function eligible(id, ids)
    for _, candidate in ipairs(ids) do
        if candidate == id then return gui.is_enabled(gui.get_node(id)) end
    end
    return false
end

function M.cancel(state)
    if state.pressed then pose(state.pressed, false) end
    state.pressed = nil
end

-- Returns activated id, consumed. Release outside cancels; no action on press.
function M.input(state, action, ids)
    if action.pressed then
        M.cancel(state) -- recover from a lost release before a new gesture
        for _, id in ipairs(ids) do
            local node = gui.get_node(id)
            if gui.is_enabled(node) and gui.pick_node(node, action.x, action.y) then
                state.pressed = id
                pose(id, true)
                return nil, true
            end
        end
    elseif state.pressed then
        local id = state.pressed
        local node = gui.get_node(id)
        local inside = eligible(id, ids) and gui.pick_node(node, action.x, action.y)
        if action.released then
            M.cancel(state)
            return inside and id or nil, true
        end
        pose(id, inside)
        return nil, true
    end
    return nil, false
end
return M
