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

-- Вертикальное смещение карт в стопке tableau («корешок» — видимая полоса карты).
--
-- G5. Раньше здесь была константа -35, и длинная колонка просто уезжала за низ
-- экрана. Замерено (reviews/probe_stack_len.lua): слот tableau стоит на y=299,
-- карта 150 px, экран 0..540 — при шаге 35 полностью видны только 7 карт,
-- восьмая уже обрезана, а с двенадцатой ВЕРХНЯЯ карта колонки (единственная,
-- которую можно взять) целиком уходит за экран, и партия становится
-- недоигрываемой.
--
-- Потолок длины колонки — 12 карт: раздаётся 5, сверху кладётся строго
-- убывающая последовательность разных мастей, максимум 9..3 на раздатую 10
-- (двойка не считается: оказавшись верхней, она сама улетает в foundation,
-- см. tableau_script.last_card_to_slot). Тринадцатая карта существует один кадр
-- плюс время полёта — это и есть та самая двойка, положенная на тройку.
--
-- Поэтому шаг адаптивный: пока колонка помещается — привычные 35 px, дальше
-- ровно столько, чтобы последняя карта села на нижнюю кромку. Ранг карты
-- занимает верхние 16 px спрайта (замер по всем 27 номиналам: строки 2..15,
-- дальше разрыв и начало арта), а при 13 картах шаг всё ещё 18.2 px — ранг
-- читается на любой длине.
M.STACK_PITCH_MAX = 35
M.STACK_BOTTOM_MARGIN = 6   -- зазор до нижней кромки экрана
M.STACK_PITCH_MIN = 17      -- страховка: не уже полосы с рангом

-- count  — сколько карт в колонке ЦЕЛИКОМ (не индекс карты)
-- slot_y — мировая y слота tableau; по умолчанию авторские 299
function M.stack_offset_y(count, slot_y)
   local n = count or 1
   if n < 2 then return -M.STACK_PITCH_MAX end
   -- от низа ПЕРВОЙ карты до нижней кромки: столько есть на все остальные
   local span = ((slot_y or 299) - M.CARD_HALF_SIZE.y) - M.STACK_BOTTOM_MARGIN
   local pitch = span / (n - 1)
   if pitch > M.STACK_PITCH_MAX then pitch = M.STACK_PITCH_MAX end
   if pitch < M.STACK_PITCH_MIN then pitch = M.STACK_PITCH_MIN end
   return -pitch
end

-- Базовое разрешение дисплея
M.DISPLAY_WIDTH  = 960
M.DISPLAY_HEIGHT = 540

return M
