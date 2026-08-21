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

-- ─── Математика «болтания» карты при перетаскивании ──────────────────────────
-- Чистые функции без Defold-зависимостей: их гоняют юнит-тесты
-- (solver/tests/test_game_scripts.lua), а cursor.script только применяет
-- результат. Держать здесь, а не инлайном в cursor.script — иначе не замерить.

-- ВАЖНО про нормировку. Прежний наклон считался от `dx` — сдвига курсора
-- МЕЖДУ ДВУМЯ СОБЫТИЯМИ ВВОДА. Событий на 144 Гц вдвое больше, чем на 60, и
-- каждое `dx` вдвое меньше ⇒ один и тот же жест давал разный наклон на разных
-- машинах, а в HTML5 частота кадров вообще плавает. Считаем от СКОРОСТИ
-- (px/сек), тогда эффект зависит от жеста, а не от железа.

M.DRAG_MAX_TILT_DEG = 10     -- предельный наклон карты, градусы
-- 650 px/сек — скорость обычного, не резкого протаскивания (замер в браузере:
-- медленный драг харнесса даёт ~350 px/сек, резкий флик — тысячи). При 900
-- обычный ход давал ~1.4° и эффекта не было видно вообще.
M.DRAG_REF_SPEED    = 650
M.DRAG_MAX_SQUASH   = 0.10   -- предельное сжатие по X (было 0.45 — карта в лапшу)
M.DRAG_LAG_BASE     = 0.05   -- сек: длительность доводки позиции верхней карты
M.DRAG_LAG_PER_CARD = 0.022  -- сек: добавка на каждую карту вглубь стопки
M.DRAG_LAG_MAX      = 0.16   -- сек: потолок, иначе хвост стопки «отстаёт» насовсем

local function clamp(v, lo, hi)
   if v < lo then return lo end
   if v > hi then return hi end
   return v
end

-- Скорость курсора по X в px/сек из сдвига за кадр. dt<=0 (первый кадр,
-- сдвоенное событие) даёт 0, а не деление на ноль и не всплеск наклона.
function M.drag_speed(dx, dt)
   if not dt or dt <= 0 then return 0 end
   return dx / dt
end

-- Сглаживание скорости. Курсор двигается СОБЫТИЯМИ, а кадры идут всегда: в
-- кадре без события сырая скорость = 0, и карта дёргано выпрямляется между
-- движениями руки (замерено зондом в браузере: target скакал 0 / 6.7 / 0).
-- Экспоненциальное сглаживание держит наклон между событиями.
M.DRAG_SPEED_TAU = 0.06 -- сек, постоянная времени

function M.smooth_speed(prev, raw, dt)
   if prev == nil then return raw end
   if not dt or dt <= 0 then return prev end
   local k = 1 - math.exp(-dt / M.DRAG_SPEED_TAU)
   return prev + (raw - prev) * k
end

-- Наклон в градусах. Знак минусовой: карта ОТСТАЁТ от движения (тянем вправо —
-- низ карты волочится влево), как настоящая карта между пальцами.
function M.drag_tilt_deg(speed_x)
   local n = clamp((speed_x or 0) / M.DRAG_REF_SPEED, -1, 1)
   return -n * M.DRAG_MAX_TILT_DEG
end

-- Сжатие по X (псевдо-3D): 1.0 = карта в полную ширину.
function M.drag_squash(speed_x)
   local n = clamp(math.abs(speed_x or 0) / M.DRAG_REF_SPEED, 0, 1)
   return 1.0 - n * M.DRAG_MAX_SQUASH
end

-- Длительность доводки для index-й карты стопки (1 = та, что под курсором).
-- Разная длительность = карты приезжают вразнобой, стопка «веером» изгибается;
-- одинаковая (как было) = жёсткое тело.
function M.drag_lag(index)
   local i = (index or 1) - 1
   if i < 0 then i = 0 end
   return math.min(M.DRAG_LAG_BASE + i * M.DRAG_LAG_PER_CARD, M.DRAG_LAG_MAX)
end

return M
