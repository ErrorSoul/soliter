-- D1: Lua-сторона моста к SDK Яндекс.Игр.
--
-- Промисы, парность gameplay start/stop и разбор features живут в
-- html5/engine_template.html (блок ya-bridge). Здесь только вызовы строковых
-- геттеров: html5.run умеет вернуть в Lua строку и ничего кроме неё, поэтому
-- всё, что сложнее строки, разбирается на стороне JS.
--
-- Библиотеку defold-yagames сознательно не подключали: из всего SDK нужны
-- четыре вызова (init, LoadingAPI.ready, GameplayAPI.start/stop, язык), а
-- зависимость тянет рекламу/лидерборды/платежи, которых в игре нет. Если
-- появятся — переезд на библиотеку остаётся открытым.
--
-- Вне HTML5 (редактор, десктоп) и вне iframe Я.Игр (мост не найден или /sdk.js
-- отдал 404) все функции — no-op, а state() = "absent". Ни одна ветка игры от
-- SDK не зависит.

local M = {}

local function run(js)
   if not html5 then
      return nil
   end
   local ok, res = pcall(html5.run, js)
   if not ok then
      return nil
   end
   return res
end

-- Мост может отсутствовать, если бандл собран старым шаблоном.
function M.available()
   return run("typeof window.__ya") == "object"
end

-- "absent" | "pending" | "ready" | "failed"
function M.state()
   local s = run("__ya.state()")
   if type(s) ~= "string" or s == "" then
      return "absent"
   end
   return s
end

-- Язык интерфейса игрока по версии платформы; "" пока SDK не ответил.
function M.lang()
   local l = run("__ya.lang()")
   return (type(l) == "string") and l or ""
end

-- Платформа снимает свой лоадер. Мост сам следит, чтобы это случилось один раз.
function M.loading_ready()
   run("__ya.loadingReady()")
end

-- Игрок за столом (true) или в меню/на экране победы (false).
function M.gameplay(on)
   run("__ya.gameplay(" .. (on and "true" or "false") .. ")")
end

-- Для стенда: список вызовов моста через запятую, в порядке их совершения.
function M.trace()
   local t = run("__ya.trace()")
   return (type(t) == "string") and t or ""
end

return M
