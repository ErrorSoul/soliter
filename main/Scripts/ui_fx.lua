-- ui_fx.lua — общие highlight/unhighlight эффекты для слот-GO
-- Работает через относительные URL ("." / "#sprite"), которые резолвятся
-- к инстансу GO, вызвавшего функцию (Defold: context propagation).
local M = {}

-- scale — вектор масштаба пульсации (например, 1.06 или 1.15)
function M.highlight(scale)
    sprite.set_constant("#sprite", "tint", vmath.vector4(1.5, 1.4, 1.0, 1))
    go.cancel_animations(".", "scale")
    go.animate(".", "scale", go.PLAYBACK_LOOP_PINGPONG,
        vmath.vector3(scale, scale, 1), go.EASING_INSINE, 0.5)
end

function M.unhighlight()
    sprite.set_constant("#sprite", "tint", vmath.vector4(1, 1, 1, 1))
    go.cancel_animations(".", "scale")
    go.set(".", "scale", vmath.vector3(1, 1, 1))
end

return M
