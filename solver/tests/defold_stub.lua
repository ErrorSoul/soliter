-- Minimal Defold API stubs so .script files can be loadfile'd in host Lua.
-- Not a simulator: enough for on_message / check_* unit tests.

local M = {}

function M.install()
   M.go_props = {}
   M.go_positions = {}
   M.go_self_pos = { x = 0, y = 0, z = 0 }
   M.anims = {}
   _G.hash = function(s) return tostring(s) end

   -- vector3 needs `+` because scripts add offsets to message.position.
   local v3mt = {}
   local function v3(x, y, z)
      return setmetatable({ x = x or 0, y = y or 0, z = z or 0 }, v3mt)
   end
   v3mt.__add = function(a, b) return v3(a.x + b.x, a.y + b.y, a.z + b.z) end
   v3mt.__sub = function(a, b) return v3(a.x - b.x, a.y - b.y, a.z - b.z) end

   _G.vmath = {
      vector3 = v3,
      vector4 = function(x, y, z, w) return { x = x or 0, y = y or 0, z = z or 0, w = w or 0 } end,
      quat = function() return {} end,
   }

   _G.msg = { log = {} }
   function _G.msg.post(to, id, data)
      _G.msg.log[#_G.msg.log + 1] = { to = to, id = tostring(id), data = data }
   end
   function _G.msg.clear()
      _G.msg.log = {}
   end

   _G.go = {
      get_id = function() return "self_go" end,
      -- G5: раскладка стопки читает позицию слота и пишет позиции карт. Без
      -- этого стора tableau_script.update_visible_cards нечем проверить: шаг
      -- зависит от длины колонки, а значит проверять надо КООРДИНАТЫ, а не факт
      -- вызова. get_position() без id — это сам слот (M.go_self_pos).
      get_position = function(id)
         if id == nil then return M.go_self_pos end
         return M.go_positions[tostring(id)] or { x = 0, y = 0, z = 0 }
      end,
      set_position = function(pos, id)
         if id ~= nil then M.go_positions[tostring(id)] = pos end
      end,
      -- G7: анимации складываем в очередь и прокручиваем ВРУЧНУЮ (M.flush_anims).
      -- Автозапуск здесь недопустим: fly_card_arc вкладывает вторую анимацию в
      -- колбэк первой, и «мгновенная» анимация превратила бы полёт в
      -- синхронный вызов — тест перестал бы отличать «карта долетела» от
      -- «карту отправили лететь».
      animate = function(_id, _prop, _pb, _to, _easing, _dur, _delay, cb)
         if cb then M.anims[#M.anims + 1] = cb end
      end,
      cancel_animations = function() end,
      -- go.set/go.get держат общий стор свойств: скрипты читают то, что писали
      -- (card.script читает euler.z, чтобы доводить поворот маятником).
      set = function(_url, prop, value)
         M.go_props[tostring(prop)] = value
      end,
      get = function(_url, prop)
         local v = M.go_props[tostring(prop)]
         if v ~= nil then return v end
         return 0
      end,
   }

   _G.sprite = { set_constant = function() end }
   _G.sound = { play = function() end }

   -- Задержку ЗАПОМИНАЕМ, а не выбрасываем: ревью блока M (grok-4.6) заметило,
   -- что прежний стаб делал `timer.delay(0.01, ...)` и `timer.delay(1.5, ...)`
   -- неразличимыми, а величина задержки в этом коде смысловая (дуга драконов,
   -- полёт цветка). Тест обязан иметь возможность её проверить.
   _G.timer = { pending = {}, delays = {} }
   function _G.timer.delay(t, _repeat, cb)
      _G.timer.pending[#_G.timer.pending + 1] = cb
      _G.timer.delays[#_G.timer.pending] = t
   end
   function _G.timer.flush()
      local q = _G.timer.pending
      _G.timer.pending = {}
      _G.timer.delays = {}
      for i = 1, #q do q[i]() end
   end

   _G.window = {
      get_size = function() return M.window_size[1], M.window_size[2] end,
   }

   _G.sys = {
      get_config_int = function(key, default)
         if key == "display.width" then return 960 end
         if key == "display.height" then return 540 end
         return default
      end,
   }
end

-- Canvas the game believes it is running on; coords tests resize it.
M.window_size = { 960, 540 }
M.go_props = {}
M.go_positions = {}
M.go_self_pos = { x = 0, y = 0, z = 0 }
M.anims = {}

-- Прокрутить очередь колбэков анимаций. rounds — сколько раз подряд: полёт по
-- дуге (fly_card_arc) состоит из двух вложенных анимаций, значит нужно два.
function M.flush_anims(rounds)
   for _ = 1, (rounds or 1) do
      local q = M.anims
      M.anims = {}
      for i = 1, #q do q[i]() end
   end
end

function M.set_window(w, h)
   M.window_size = { w, h }
end

function M.msg_count(id)
   local n = 0
   for _, e in ipairs(_G.msg.log) do
      if e.id == tostring(id) then n = n + 1 end
   end
   return n
end

function M.load_script(path)
   local chunk, err = loadfile(path)
   if not chunk then error("loadfile " .. path .. ": " .. tostring(err)) end
   return chunk()
end

return M
