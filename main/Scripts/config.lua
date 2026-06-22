-- config.lua — единый конфиг констант (размеры, маппинги, z-индексы, смещения)
local M = {}

-- Маппинг масть → foundation-слот (используется в cursor.script и tableau_script.script)
M.BASE_SLOT_TRACE = {
    red   = "base_slot1",
    blue  = "base_slot2",
    green = "base_slot3"
}

M.DRAGON_BUTTON_TRACE = {
    red   = "dragon_button1",
    blue  = "dragon_button2",
    green = "dragon_button3"
}

-- Размеры карт и кнопок (используются в cursor.script / hit_test)
M.CARD_SIZE      = vmath.vector3(90, 150, 0)
M.CARD_HALF_SIZE = vmath.vector3(45, 75, 0)
M.BTN_SIZE       = vmath.vector3(48, 48, 0)
M.BTN_HALF_SIZE  = vmath.vector3(24, 24, 0)

-- Z-index слои
M.Z_CARD_DEFAULT        = 0.2
M.Z_CARD_DRAGGING       = 0.3
M.Z_CARD_LAST_IN_STACK  = 0.03
M.Z_CARD_STACK_BASE     = 0.002
M.Z_CARD_STACK_STEP     = 0.002

-- Вертикальное смещение карт в стопке tableau
M.STACK_CARD_OFFSET_Y = -35

-- Базовое разрешение дисплея
M.DISPLAY_WIDTH  = 960
M.DISPLAY_HEIGHT = 540

return M
