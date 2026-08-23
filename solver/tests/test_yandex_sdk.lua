-- D1: мост к SDK Яндекс.Игр — Lua-сторона.
--
-- Что здесь проверяется и что НЕ проверяется.
-- Проверяется: последовательность намерений игры (что и когда Lua просит у
-- моста) и приоритет языка. Парность start/stop и «ready ровно один раз» на
-- стороне JS живут в html5/engine_template.html и покрыты сценарием стенда
-- `yasdk` — фальшивый html5 ниже пишет вызовы СЫРЫМИ, без дедупликации, чтобы
-- зелёный тест здесь не выдавал себя за проверку JS-моста.

local new_harness = require("solver.tests.harness")
local stub = require("solver.tests.defold_stub")
local H = new_harness()

stub.install()

local function load_script(rel)
   local chunk, err = loadfile(rel)
   if not chunk then error(err) end
   chunk()
end

-- Фальшивый html5.run: отвечает на те же строки, что кладёт yandex.lua.
-- Незнакомый вызов — ошибка, а не молчаливый nil: если Lua-сторона начнёт
-- звать мост иначе, тест обязан это заметить, а не тихо позеленеть.
local function fake_html5(bridge)
   return {
      run = function(js)
         if js == "typeof window.__ya" then
            return bridge and "object" or "undefined"
         end
         if js == "window.location.search" then
            return (bridge and bridge.search) or ""
         end
         if not bridge then
            return nil
         end
         if js == "__ya.state()" then
            bridge.polls = bridge.polls + 1
            return bridge.state
         end
         if js == "__ya.lang()" then
            return bridge.lang or ""
         end
         if js == "__ya.trace()" then
            return table.concat(bridge.calls, ",")
         end
         if js == "__ya.loadingReady()" then
            bridge.calls[#bridge.calls + 1] = "ready"
            return ""
         end
         if js == "__ya.gameplay(true)" then
            bridge.calls[#bridge.calls + 1] = "start"
            return ""
         end
         if js == "__ya.gameplay(false)" then
            bridge.calls[#bridge.calls + 1] = "stop"
            return ""
         end
         error("мост позвали неизвестным способом: " .. tostring(js))
      end,
   }
end

local function new_bridge(fields)
   local b = { state = "pending", lang = "", search = "", calls = {}, polls = 0 }
   for k, v in pairs(fields or {}) do b[k] = v end
   return b
end

local function calls(bridge)
   return table.concat(bridge.calls, ",")
end

-- Прогнать N кадров game_manager.update.
local function frames(self, n)
   for _ = 1, (n or 1) do update(self, 0.016) end
end

local function fresh_manager()
   load_script("main/Scripts/game_manager.script")
   msg.clear()
   local self = {}
   init(self)
   return self
end

-- ---------------------------------------------------------------- отсутствие

H.test("D1 без html5 игра вообще не трогает мост", function()
   _G.html5 = nil
   local self = fresh_manager()
   frames(self, 5)
   on_message(self, hash("start_game"), {}, "ui")
   on_message(self, hash("unload_level"), {}, "ui")
   if stub.msg_count("language_ready") > 0 then
      return false, "без SDK ui просят перекрасить подписи"
   end
   return true
end)

H.test("D1 мост не найден (старый шаблон) — состояние absent, ready не уходит", function()
   _G.html5 = fake_html5(nil)
   local self = fresh_manager()
   frames(self, 5)
   if stub.msg_count("language_ready") > 0 then
      return false, "без моста ui просят перекрасить подписи"
   end
   _G.html5 = nil
   return true
end)

-- ------------------------------------------------------------------ загрузка

H.test("D1 пока промис SDK не разрешился, LoadingAPI.ready не зовут", function()
   local bridge = new_bridge({ state = "pending" })
   _G.html5 = fake_html5(bridge)
   local self = fresh_manager()
   frames(self, 20)
   _G.html5 = nil
   if calls(bridge) ~= "" then
      return false, "мост позвали до готовности SDK: " .. calls(bridge)
   end
   if bridge.polls < 20 then
      return false, "опрос состояния прекратился раньше ответа SDK (" .. bridge.polls .. " кадров)"
   end
   return true
end)

H.test("D1 SDK ответил — ready ровно один раз, дальше опрос прекращается", function()
   local bridge = new_bridge({ state = "pending", lang = "ru" })
   _G.html5 = fake_html5(bridge)
   local self = fresh_manager()
   frames(self, 3)
   bridge.state = "ready"
   frames(self, 30)
   local polls_after = bridge.polls
   frames(self, 10)
   _G.html5 = nil
   if calls(bridge) ~= "ready" then
      return false, "ожидали ровно один ready, получили: " .. calls(bridge)
   end
   if stub.msg_count("language_ready") ~= 1 then
      return false, "language_ready ушёл " .. stub.msg_count("language_ready") .. " раз вместо одного"
   end
   if bridge.polls ~= polls_after then
      return false, "после ответа SDK опрос состояния продолжается каждый кадр"
   end
   return true
end)

H.test("D1 SDK упал — ready не зовём и подписи не трогаем", function()
   local bridge = new_bridge({ state = "failed" })
   _G.html5 = fake_html5(bridge)
   local self = fresh_manager()
   frames(self, 10)
   _G.html5 = nil
   if calls(bridge) ~= "" then
      return false, "после ошибки SDK мост всё равно позвали: " .. calls(bridge)
   end
   if stub.msg_count("language_ready") > 0 then
      return false, "после ошибки SDK ui просят перекрасить подписи"
   end
   return true
end)

-- ------------------------------------------------------------------ геймплей

H.test("D1 GameplayAPI: старт партии, конец партии, выгрузка уровня", function()
   local bridge = new_bridge({ state = "ready" })
   _G.html5 = fake_html5(bridge)
   local self = fresh_manager()
   frames(self, 2)
   on_message(self, hash("start_game"), {}, "ui")
   on_message(self, hash("gameplay_over"), {}, "ui")   -- победа, уровень ещё на экране
   on_message(self, hash("restart_level"), {}, "ui")
   on_message(self, hash("unload_level"), {}, "ui")
   _G.html5 = nil
   if calls(bridge) ~= "ready,start,stop,start,stop" then
      return false, "неверная последовательность: " .. calls(bridge)
   end
   return true
end)

H.test("D1 меню не считается геймплеем: до start_game старта нет", function()
   local bridge = new_bridge({ state = "ready" })
   _G.html5 = fake_html5(bridge)
   local self = fresh_manager()
   frames(self, 10)
   _G.html5 = nil
   if calls(bridge) ~= "ready" then
      return false, "в меню мост позвали лишним вызовом: " .. calls(bridge)
   end
   return true
end)

-- --------------------------------------------------------------------- победа

-- Минимальный gui: ноды — просто их имена, вся отрисовка — no-op. Нужен ровно
-- для того, чтобы загрузить настоящий ui.gui_script и прогнать его update.
local function fake_gui()
   local g = {
      EASING_OUTQUAD = 0, EASING_OUTBACK = 1,
      get_node = function(name) return name end,
      set_text = function() end,
      set_enabled = function() end,
      is_enabled = function() return true end,
      set_color = function() end,
      set_position = function() end,
      set_scale = function() end,
      animate = function() end,
      pick_node = function() return false end,
   }
   return g
end

H.test("D1 победа сообщает платформе, что партия кончилась", function()
   local tutorial_state = require("main.Scripts.tutorial_state")
   _G.gui = fake_gui()
   _G.html5 = nil
   load_script("gui/ui.gui_script")
   local self = {}
   init(self)
   msg.clear()

   tutorial_state.is_tutorial = false
   tutorial_state.show_victory = true
   update(self, 0.016)
   local first = stub.msg_count("gameplay_over")
   -- Экран победы висит дальше, уровень ещё загружен: второй раз платформе
   -- говорить нечего.
   update(self, 0.016)
   local second = stub.msg_count("gameplay_over")
   tutorial_state.reset()
   _G.gui = nil

   if first ~= 1 then
      return false, "победа не сказала game_manager про конец геймплея (ушло " .. first .. ")"
   end
   if second ~= 1 then
      return false, "gameplay_over ушёл повторно на следующем кадре (" .. second .. ")"
   end
   return true
end)

-- ---------------------------------------------------------------------- язык

H.test("D1 язык из SDK бьёт ?lang= в адресе", function()
   local bridge = new_bridge({ state = "ready", lang = "ru", search = "?lang=en" })
   _G.html5 = fake_html5(bridge)
   local i18n = require("main.Scripts.i18n")
   local got = i18n.detect()
   _G.html5 = nil
   if got ~= "ru" then
      return false, "SDK сказал ru, а detect вернул " .. tostring(got)
   end
   return true
end)

H.test("D1 SDK ещё молчит — работает прежний порядок (?lang=)", function()
   local bridge = new_bridge({ state = "pending", lang = "", search = "?lang=en" })
   _G.html5 = fake_html5(bridge)
   local i18n = require("main.Scripts.i18n")
   local got = i18n.detect()
   _G.html5 = nil
   if got ~= "en" then
      return false, "без ответа SDK detect вернул " .. tostring(got) .. " вместо en"
   end
   return true
end)

H.test("D1 незнакомый язык платформы не ломает игру, а падает вниз по списку", function()
   local bridge = new_bridge({ state = "ready", lang = "kk", search = "?lang=tr" })
   _G.html5 = fake_html5(bridge)
   local i18n = require("main.Scripts.i18n")
   local got = i18n.detect()
   _G.html5 = nil
   if got ~= "tr" then
      return false, "казахский у нас не переведён, ждали tr, получили " .. tostring(got)
   end
   return true
end)

return H
