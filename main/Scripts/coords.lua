-- coords.lua — экран → мир.
--
-- Defold отдаёт action.x/y ЛИНЕЙНО РАСТЯНУТЫМИ в авторское разрешение:
--     action.x = screen_px_x * display.width  / window_width
--     action.y = screen_px_y * display.height / window_height
-- Леттербокс при этом не учитывается никак. А рендер идёт через
-- fixed_fit_projection, который ВПИСЫВАЕТ вид: zoom = min(w/W, h/H), картинка
-- центрируется, по широкой оси доступен лишний мир (builtin render script:
-- projected_width = window_width/zoom, xoffset = -(projected_width - W)/2).
--
-- На 16:9 обе системы численно совпадают — поэтому расхождение невидимо на
-- авторском 960x540 и вылезает на любом другом соотношении канваса. Замерено
-- в браузере (tools/browser-test.py --scenario hittest, зонд в on_input):
--     window 1200x540: нажатие на карту с миров. x=77  пришло как action.x=158
--     window  800x600: нажатие на карту с миров. y=159 пришло как action.y=187
-- Первый случай — промах мимо карты целиком (пол-леттербокса, 81 px), второй
-- маскировался высотой карты. Итог: на не-16:9 хит-тесты уезжают.
--
-- Здесь снимаем растяжение, затем снимаем центрирующий леттербокс.
local M = {}

local function display_size()
   return sys.get_config_int("display.width", 960),
          sys.get_config_int("display.height", 540)
end

function M.screen_to_world(x, y)
   local W, H = display_size()
   local w, h = window.get_size()
   -- До первого кадра/в тестах размера может не быть — тогда честнее вернуть
   -- вход как есть (на авторском разрешении это и есть верный ответ).
   if not w or w <= 0 or not h or h <= 0 then return x, y end

   local zoom = math.min(w / W, h / H)
   if zoom <= 0 then return x, y end

   -- action → реальные пиксели окна
   local sx = x * w / W
   local sy = y * h / H
   -- пиксели окна → мир, вычитая центрирующее смещение fixed_fit
   return (sx - (w - W * zoom) / 2) / zoom,
          (sy - (h - H * zoom) / 2) / zoom
end

return M
