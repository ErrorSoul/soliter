-- D3: сохранение состояния партии (sys.save/sys.load) и восстановление при
-- старте. Формат — свой компактный текст (не JSON, см. main.script), три
-- слоя проверяются раздельно:
--   1) формат: encode/decode снапшота, включая порчу каждого класса поля;
--   2) политика: should_save (когда вообще можно сохранять) и census-
--      валидация чужого/битого сохранения при загрузке;
--   3) стык с диском: save_game/load_saved_game/clear_save через фальшивый
--      sys.save/sys.load, и game_manager.restart_level/switch_level,
--      стирающие сохранение ДО show() (иначе рестарт вернул бы брошенную
--      партию — см. main.script.load_saved_game).
--
-- Восстановление (restore_tableau_from_layout/restore_cells_and_foundation)
-- проверяется в конце файла двумя способами: по сообщениям, которые шлёт main
-- (порядок оснований, запечатанная ячейка), и по ИТОГОВОМУ состоянию кнопок
-- драконов — настоящие free_cell/dragon_button/tableau_script на шине
-- сообщений, оракул — rules.legal_moves. factory.create стаб объявляет.
--
-- НЕ проверяется здесь (и не может быть проверено без песочницы/движка):
--   - ysdk.player.setData/getData — сознательно не подключены в этом заходе
--     (см. main.script.save_game): писать в SDK и никогда не читать обратно
--     бесполезнее, чем не писать вовсе, а честная асинхронная загрузка
--     потребовала бы поллинга, который проверяется только в песочнице Я.Игр.

local new_harness = require("solver.tests.harness")
local stub = require("solver.tests.defold_stub")
local H = new_harness()

-- Базовый стаб нужен ДАЖЕ тестам формата (main.script на верхнем уровне
-- требует config.lua, а тот трогает vmath при загрузке модуля). Не полагаемся
-- на то, что stub.install() уже вызвал какой-то предыдущий тестовый файл —
-- этот файл обязан быть зелёным и при запуске в одиночку. Тесты с диском
-- дополнительно зовут stub.install() сами — им нужен чистый save_fs.
stub.install()

local config = require("main.Scripts.config")
local rules = require("solver.rules")
local bridge = require("solver.bridge")

local function load_script(rel)
   local chunk, err = loadfile(rel)
   if not chunk then error(err) end
   chunk()
end

local function last_msg(id)
   local log = _G.msg.log
   for i = #log, 1, -1 do
      if log[i].id == tostring(id) then return log[i] end
   end
   return nil
end

-- Глубокое равенство: снапшоты — вложенные таблицы вперемешку с числовыми и
-- строковыми ключами (tableau[col][i], free_cells[ord].card, foundation.red).
local function deep_eq(a, b)
   if a == b then return true end
   if type(a) ~= "table" or type(b) ~= "table" then return false end
   for k, v in pairs(a) do
      if not deep_eq(v, b[k]) then return false end
   end
   for k in pairs(b) do
      if a[k] == nil then return false end
   end
   return true
end

-- Полная честная раздача (40 карт), разложенная так, чтобы задействовать
-- каждую особенность формата разом: непустое foundation по всем трём мастям,
-- запаркованная карта в ячейке, заблокированная (собранная) масть драконов
-- в другой ячейке, третья ячейка пустая, и цветок ЗАКОПАННЫЙ в колонке
-- (не на верхушке — иначе это была бы уже "долетевшая" карта, а не позиция
-- на столе).
--
-- Подсчёт: foundation red=5 -> красные 2,3,4,5 сняты с доски (4);
-- foundation green=3 -> зелёные 2,3 сняты (2); ячейка 1 = 6_blue (1);
-- ячейка 3 = заблокированная зелёная масть (представляет все 4 зелёных
-- дракона). Остаток — 40-4-2-1-4 = 29 карт — лежит в восьми колонках.
local function build_full_deal_self()
   local function card(value, suit, extra)
      local d = { value = value, suit = suit }
      if extra then for k, v in pairs(extra) do d[k] = v end end
      return d
   end
   local function rec(id, value, suit, extra)
      return { id = id, data = card(value, suit, extra) }
   end

   local remaining = {}
   local function push(id, value, suit, extra) remaining[#remaining + 1] = rec(id, value, suit, extra) end

   for _, v in ipairs({ 6, 7, 8, 9, 10 }) do push(v .. "_red", v, "red") end
   for i = 1, 4 do push("d_red_" .. i, 'd', "red", { is_dragon = true }) end

   for _, v in ipairs({ 4, 5, 6, 7, 8, 9, 10 }) do push(v .. "_green", v, "green") end
   -- зелёные драконы — все 4 уже в заблокированной ячейке, в остаток не идут

   for _, v in ipairs({ 2, 3, 4, 5, 7, 8, 9, 10 }) do push(v .. "_blue", v, "blue") end
   for i = 1, 4 do push("d_blue_" .. i, 'd', "blue", { is_dragon = true }) end

   push("flower", 'f', "flower", { is_flower = true })

   if #remaining ~= 29 then error("тестовая фикстура сломана: остаток = " .. #remaining) end

   local tableau_stacks = {}
   for col = 1, 8 do tableau_stacks[col] = { cards = {} } end
   -- Раздаём круговым обходом — порядок внутри колонки не важен для census,
   -- важно только что цветок НЕ последний элемент своей колонки (иначе
   -- snapshot_and_go_map счёл бы его "долетевшим" и это была бы другая,
   -- менее интересная фикстура). remaining[29] — цветок, кладём его первым
   -- в колонку 1, а следом ещё карту.
   local flower_entry = table.remove(remaining) -- снимает "flower" (был последним push)
   table.insert(tableau_stacks[1].cards, flower_entry)
   local col = 2
   for _, entry in ipairs(remaining) do
      table.insert(tableau_stacks[((col - 1) % 8) + 1].cards, entry)
      col = col + 1
   end

   return {
      states = { INIT = "init", PLAYING = "playing", PAUSED = "paused", WIN = "win", GAME_OVER = "gameover" },
      currentState = "playing",
      tutorial_mode = false,
      is_full_deal = true,
      restoring = false,
      auto_finishing = false,
      auto_collecting = false,
      debug_replaying = false,
      tableau_stacks = tableau_stacks,
      foundation_top = { red = 5, blue = 1, green = 3 },
      free_cell_state = {
         { card = rec("go_6b", 6, "blue"), is_blocked = false },
         {},
         { card = rec("go_dg", 'd', "green", { is_dragon = true }), is_blocked = true },
      },
      flower_collected = false,
   }
end

-- ============================== формат: round-trip ==============================

H.test("D3 round-trip: snapshot_and_go_map -> encode -> decode воспроизводит исходную доску", function()
   load_script("main/Scripts/main.script")
   local self = build_full_deal_self()
   local snap, _, _, err = snapshot_and_go_map(self)
   if err then return false, "честная фикстура отвергнута снапшотом: " .. tostring(err) end

   local encoded, enc_err = save_encode_snapshot(snap)
   if not encoded then return false, "encode отказал на честном снапшоте: " .. tostring(enc_err) end

   local decoded, dec_err = save_decode_snapshot(encoded)
   if not decoded then return false, "decode отказал на своей же строке: " .. tostring(dec_err) end

   if not deep_eq(decoded, snap) then
      return false, "decode(encode(snap)) != snap — раскодированная доска отличается от исходной"
   end
   return true
end)

H.test("D3 round-trip чувствителен к содержимому доски (не просто эхо константы)", function()
   load_script("main/Scripts/main.script")
   local self = build_full_deal_self()
   local snap1 = snapshot_and_go_map(self)
   local encoded1 = save_encode_snapshot(snap1)

   -- Мутация фикстуры: продвигаем красное foundation на одну карту дальше
   -- (снимаем 6_red с колонки 1, где он лежит, и поднимаем foundation.red).
   local moved = false
   for _, entry in ipairs(self.tableau_stacks[2].cards) do
      if entry.data.value == 6 and entry.data.suit == "red" then moved = true end
   end
   if not moved then return false, "фикстура теста устарела: 6_red не там, где ожидал тест" end
   for i = #self.tableau_stacks[2].cards, 1, -1 do
      if self.tableau_stacks[2].cards[i].data.value == 6 and self.tableau_stacks[2].cards[i].data.suit == "red" then
         table.remove(self.tableau_stacks[2].cards, i)
         break
      end
   end
   self.foundation_top.red = 6

   local snap2 = snapshot_and_go_map(self)
   local encoded2 = save_encode_snapshot(snap2)
   if encoded1 == encoded2 then
      return false, "две РАЗНЫЕ доски закодировались в одну и ту же строку"
   end
   local decoded2 = save_decode_snapshot(encoded2)
   if deep_eq(decoded2, snap1) then
      return false, "round-trip после мутации всё ещё равен ДОмутационному снапшоту — тест ничего не различает"
   end
   return true
end)

-- ============================== decode: порча каждого класса поля ==============================

local function golden_encoded()
   load_script("main/Scripts/main.script")
   local self = build_full_deal_self()
   local snap = snapshot_and_go_map(self)
   return save_encode_snapshot(snap)
end

H.test("D3 decode отвергает неизвестную версию", function()
   local s = golden_encoded():gsub("^V1;", "V2;")
   local snap, err = save_decode_snapshot(s)
   if snap then return false, "чужая версия принята как своя" end
   if not err then return false, "нет причины отказа" end
   return true
end)

H.test("D3 decode отвергает недостающую колонку (7 вместо 8)", function()
   -- Строка собрана вручную, а не хирургией golden-строки: слияние двух
   -- НЕПУСТЫХ колонок через вырезанный "|" может случайно дать невалидный
   -- токен и тест прошёл бы по ДРУГОЙ причине. Здесь все колонки пустые —
   -- единственное, что может поймать разбор, это именно счётчик колонок.
   local s = "V1;T:||||||;C:||;F:1,1,1;L:0" -- 6 "|" = 7 колонок, а не 8
   local snap, err = save_decode_snapshot(s)
   if snap then return false, "строка с 7 колонками принята как честная (нужно 8)" end
   if not err or not err:find("колон") then return false, "причина отказа не про число колонок: " .. tostring(err) end
   return true
end)

H.test("D3 decode отвергает битый токен карты", function()
   local s = golden_encoded():gsub("6R", "6X", 1) -- "X" не масть
   local snap, err = save_decode_snapshot(s)
   if snap then return false, "битый токен карты принят" end
   return true
end)

H.test("D3 decode отвергает нечисловое foundation", function()
   local s = golden_encoded():gsub(";F:5,1,3;", ";F:x,1,3;")
   local snap, err = save_decode_snapshot(s)
   if snap then return false, "нечисловое foundation принято" end
   return true
end)

H.test("D3 decode отвергает битый флаг цветка", function()
   local s = golden_encoded():gsub(";L:0$", ";L:9")
   local snap, err = save_decode_snapshot(s)
   if snap then return false, "флаг цветка вне {0,1} принят" end
   return true
end)

H.test("D3 decode отвергает строку без поля foundation", function()
   local s = golden_encoded():gsub(";F:5,1,3", "")
   local snap, err = save_decode_snapshot(s)
   if snap then return false, "строка без F: принята как полная" end
   return true
end)

H.test("D3 decode не падает на мусоре и пустой строке", function()
   local ok1, snap1 = pcall(save_decode_snapshot, "совсем не то")
   if not ok1 then return false, "decode бросил исключение на мусоре вместо nil,err" end
   if snap1 then return false, "мусор распознан как сохранение" end
   local ok2, snap2 = pcall(save_decode_snapshot, "")
   if not ok2 then return false, "decode бросил исключение на пустой строке" end
   if snap2 then return false, "пустая строка распознана как сохранение" end
   return true
end)

-- ============================== census: чужая/бессмысленная доска ==============================

H.test("D3 load отвергает структурно honest, но нечестную по переписи доску", function()
   load_script("main/Scripts/main.script")
   -- Две пятёрки красных вместо пятёрки и шестёрки — валидный ФОРМАТ, но не
   -- настоящая раздача. save_decode_snapshot этого не видит (формат ей не
   -- врёт), census_error обязан поймать.
   local s = "V1;T:5R,5R|||||||;C:||;F:1,1,1;L:0"
   local snap, err = save_decode_snapshot(s)
   if not snap then return false, "decode отказал на структурно валидной строке: " .. tostring(err) end
   local census_err = snapshot_census_error(snap)
   if not census_err then
      return false, "перепись пропустила доску с двумя одинаковыми картами и без большинства колоды"
   end
   return true
end)

H.test("D3 load_saved_game отвергает структурно честное, но нечестное по переписи сохранение", function()
   stub.install()
   load_script("main/Scripts/main.script")
   -- Та же строка, что и в тесте на snapshot_census_error напрямую, но здесь
   -- проверяется СТЫК: что load_saved_game реально зовёт перепись, а не
   -- только полагается на save_decode_snapshot (тот принимает эту строку —
   -- формат валиден, две одинаковые карты и почти пустая колода это не
   -- проверка формата, а вопрос содержимого).
   local path = sys.get_save_file("shenzhen_solitaire", "progress")
   sys.save(path, { v = 1, data = "V1;T:5R,5R|||||||;C:||;F:1,1,1;L:0" })
   local got = load_saved_game()
   if got then return false, "load_saved_game принял доску, не прошедшую перепись" end
   return true
end)

-- ============================== should_save: политика ==============================

local function base_ok_self()
   return {
      states = { PLAYING = "playing", WIN = "win" },
      currentState = "playing",
      tutorial_mode = false,
      is_full_deal = true,
      restoring = false,
      auto_finishing = false,
      auto_collecting = false,
      debug_replaying = false,
   }
end

H.test("D3 should_save: честная осевшая доска — можно", function()
   load_script("main/Scripts/main.script")
   if not should_save(base_ok_self()) then return false, "базовый честный случай отклонён" end
   return true
end)

local DENY_CASES = {
   { field = "tutorial_mode",    value = true,  label = "туториал" },
   { field = "is_full_deal",     value = false, label = "не полная раздача (debug/тутор)" },
   { field = "restoring",        value = true,  label = "идёт восстановление" },
   { field = "auto_finishing",   value = true,  label = "идёт авто-финиш" },
   { field = "auto_collecting",  value = true,  label = "идёт авто-сбор драконов" },
   { field = "debug_replaying",  value = true,  label = "идёт реплей солвера" },
}
for _, case in ipairs(DENY_CASES) do
   H.test("D3 should_save: нельзя сохранять, когда " .. case.label, function()
      load_script("main/Scripts/main.script")
      local self = base_ok_self()
      self[case.field] = case.value
      if should_save(self) then return false, case.field .. " не остановил should_save" end
      return true
   end)
end

H.test("D3 should_save: нельзя сохранять после победы", function()
   load_script("main/Scripts/main.script")
   local self = base_ok_self()
   self.currentState = self.states.WIN
   if should_save(self) then return false, "победившая доска разрешила сохранение" end
   return true
end)

-- ============================== стык с диском ==============================

H.test("D3 save_game -> load_saved_game восстанавливает ту же доску", function()
   stub.install()
   load_script("main/Scripts/main.script")
   local self = build_full_deal_self()
   local want = snapshot_and_go_map(self)

   save_game(self)
   local got = load_saved_game()
   if not got then return false, "load_saved_game не нашёл только что сохранённую партию" end
   if not deep_eq(got, want) then return false, "восстановленная доска отличается от сохранённой" end
   return true
end)

H.test("D3 save_game отказывается писать, пока should_save запрещает", function()
   stub.install()
   load_script("main/Scripts/main.script")
   local self = build_full_deal_self()
   self.auto_finishing = true -- доска "между кадрами" авто-финиша
   save_game(self)
   local got = load_saved_game()
   if got then return false, "save_game записал доску во время авто-финиша" end
   return true
end)

H.test("D3 clear_save стирает сохранение", function()
   stub.install()
   load_script("main/Scripts/main.script")
   local self = build_full_deal_self()
   save_game(self)
   if not load_saved_game() then return false, "фикстура теста сломана: сохранение не записалось" end
   clear_save()
   if load_saved_game() then return false, "clear_save не стёрло сохранение" end
   return true
end)

H.test("D3 load_saved_game не падает на файле без сохранения вовсе", function()
   stub.install()
   load_script("main/Scripts/main.script")
   local ok, got = pcall(load_saved_game)
   if not ok then return false, "load_saved_game бросил исключение на пустом диске" end
   if got then return false, "пустой диск отдал сохранение" end
   return true
end)

H.test("D3 load_saved_game отвергает сохранение чужой версии", function()
   stub.install()
   load_script("main/Scripts/main.script")
   local path = sys.get_save_file("shenzhen_solitaire", "progress")
   sys.save(path, { v = 999, data = "V1;T:||||||||;C:||;F:1,1,1;L:0" })
   local got = load_saved_game()
   if got then return false, "сохранение с чужим v принято" end
   return true
end)

H.test("D3 load_saved_game отвергает сохранение с испорченными данными", function()
   stub.install()
   load_script("main/Scripts/main.script")
   local path = sys.get_save_file("shenzhen_solitaire", "progress")
   sys.save(path, { v = 1, data = "мусор, не наш формат" })
   local ok, got = pcall(load_saved_game)
   if not ok then return false, "load_saved_game упал на испорченных данных вместо nil" end
   if got then return false, "испорченные данные приняты как сохранение" end
   return true
end)

H.test("D3 update() стирает сохранение, как только currentState стал WIN", function()
   stub.install()
   load_script("main/Scripts/main.script")
   local self = build_full_deal_self()
   save_game(self)
   if not load_saved_game() then return false, "фикстура теста сломана: сохранение не записалось" end

   self.currentState = self.states.WIN
   update(self, 0.016)

   if not self.save_cleared then return false, "update() не поднял self.save_cleared при WIN" end
   if load_saved_game() then return false, "победа не стёрла сохранение" end
   return true
end)

H.test("D3 update() не трогает сохранение debug/тутор-раскладок на WIN", function()
   stub.install()
   load_script("main/Scripts/main.script")
   local self = build_full_deal_self()
   save_game(self) -- честная партия лежит на диске
   self.is_full_deal = false -- но ЭТА игра (тутор/debug) не должна её стереть
   self.currentState = self.states.WIN
   update(self, 0.016)
   if not load_saved_game() then
      return false, "WIN туториала/debug-раскладки стёр чужую (настоящую) сохранённую партию"
   end
   return true
end)

-- ===================== game_manager: рестарт/смена уровня стирают сохранение =====================

local function fresh_manager()
   load_script("main/Scripts/game_manager.script")
   _G.html5 = nil
   msg.clear()
   local self = {}
   init(self)
   return self
end

H.test("D3 restart_level стирает сохранение ДО show()", function()
   stub.install()
   load_script("main/Scripts/main.script")
   local main_self = build_full_deal_self()
   save_game(main_self)
   if not load_saved_game() then return false, "фикстура теста сломана: сохранение не записалось" end

   local gm = fresh_manager()
   on_message(gm, hash("restart_level"), {}, "ui")

   -- load_saved_game — глобальная функция main.script; после load_script
   -- game_manager.script в fresh_manager() она по-прежнему на месте (в
   -- game_manager нет одноимённой), но сверяем напрямую через sys, чтобы не
   -- зависеть от того, что именно сейчас лежит в _G.init/on_message.
   local t = sys.load(sys.get_save_file("shenzhen_solitaire", "progress"))
   if t.data ~= "" then return false, "restart_level не стёр сохранение до show()" end
   return true
end)

H.test("D3 switch_level тоже стирает сохранение", function()
   stub.install()
   load_script("main/Scripts/main.script")
   local main_self = build_full_deal_self()
   save_game(main_self)

   local gm = fresh_manager()
   on_message(gm, hash("switch_level"), {}, "ui")

   local t = sys.load(sys.get_save_file("shenzhen_solitaire", "progress"))
   if t.data ~= "" then return false, "switch_level не стёр сохранение" end
   return true
end)

H.test("D3 start_game НЕ трогает существующее сохранение", function()
   stub.install()
   load_script("main/Scripts/main.script")
   local main_self = build_full_deal_self()
   save_game(main_self)

   local gm = fresh_manager()
   on_message(gm, hash("start_game"), {}, "ui")

   local t = sys.load(sys.get_save_file("shenzhen_solitaire", "progress"))
   if t.data == "" or t.data == nil then return false, "start_game стёр сохранение, которое должен был подхватить" end
   return true
end)

-- ─── Восстановление слотов: порядок и счёт occupy_slot ──────────────────────
--
-- Эти два теста закрывают ровно ту часть restore_cells_and_foundation, которую
-- прогон на движке НЕ достал. Замерено по снимку сценария `saveload`: там
-- восстановились цветок, живая ячейка и по ОДНОЙ двойке на каждой масти, то
-- есть цикл `for value = 2, top` отработал по одной итерации, а запечатанной
-- ячейки драконов на той доске не было вовсе. Между тем именно здесь «порядок
-- значим»: base_slot.script копит счётчик и z ПО ЧИСЛУ вызовов occupy_slot,
-- поэтому основание из четырёх карт обязано приехать четырьмя вызовами по
-- возрастанию, а не одним с готовым номиналом.
--
-- factory.create стаб отражает честно — это живое API Defold, в отличие от
-- удалённого sprite.set_constant, которого стаб НЕ объявляет.

local function restore_self()
   return { cards = {}, cursor = "cursor_go", auto_collecting = false, auto_finishing = false }
end

H.test("D3 восстановление основания: карты приезжают по возрастанию, по одной на вызов", function()
   stub.install()
   load_script("main/Scripts/main.script")
   local self = restore_self()
   msg.clear()

   -- Красная масть добрана до пятёрки, синяя пуста, зелёная — одна двойка.
   restore_cells_and_foundation(self, {
      tableau = {}, free_cells = {},
      foundation = { red = 5, blue = 1, green = 2 },
      flower = false,
   })

   local red = {}
   for _, m in ipairs(msg.log) do
      if m.id == tostring(hash("occupy_slot")) and m.to == "base_slot1" then
         red[#red + 1] = m.data.card.data.value
      end
   end
   if #red ~= 4 then
      return false, "красное основание восстановлено " .. #red .. " вызовами вместо 4 (2,3,4,5)"
   end
   for i, v in ipairs(red) do
      if v ~= i + 1 then
         return false, "порядок красных сломан: на месте " .. i .. " лежит " .. tostring(v)
      end
   end

   local blue = 0
   for _, m in ipairs(msg.log) do
      if m.id == tostring(hash("occupy_slot")) and m.to == "base_slot2" then blue = blue + 1 end
   end
   if blue ~= 0 then return false, "пустое основание получило " .. blue .. " карт" end
   return true
end)

H.test("D3 восстановление запечатанной ячейки драконов помечает её собранной", function()
   stub.install()
   load_script("main/Scripts/main.script")
   local self = restore_self()
   msg.clear()

   restore_cells_and_foundation(self, {
      tableau = {}, free_cells = {
         [1] = { card_data = { id = "d_red", value = 'd', suit = "red", is_dragon = true }, blocked = true },
         [2] = { card_data = { id = "5_blue", value = 5, suit = "blue" }, blocked = false },
      },
      foundation = { red = 1, blue = 1, green = 1 },
      flower = false,
   })

   local sealed, live
   for _, m in ipairs(msg.log) do
      if m.id == tostring(hash("occupy_slot")) then
         if m.to == "free_slot1" then sealed = m.data end
         if m.to == "free_slot2" then live = m.data end
      end
   end
   if not sealed then return false, "запечатанная ячейка не восстановлена вовсе" end
   if not sealed.complete then
      return false, "ячейка с собранными драконами восстановлена как обычная — она снова станет свободной"
   end
   if not live then return false, "живая ячейка не восстановлена" end
   if live.complete then return false, "обычная карта в ячейке помечена как собранные драконы" end
   return true
end)

-- ─── Восстановление и кнопки драконов: итоговое состояние, а не payload ─────
--
-- Тесты выше смотрят только на сообщения, которые шлёт main, и дефект мимо них
-- прошёл: дракон, припаркованный в НЕзапечатанной ячейке, после перезагрузки
-- не попадал в счётчик кнопки своей масти — у живой игры он засчитан ещё
-- верхушкой колонки, а восстановление кладёт его в ячейку сразу. Кнопка не
-- загоралась, хотя сбор масти законен.
--
-- Поэтому здесь НАСТОЯЩИЕ free_cell/dragon_button/tableau_script гоняются на
-- маленькой шине сообщений, а оракул — правила солвера, а не код кнопки:
-- для каждой масти «кнопка сказала курсору is_active» обязано совпадать с
-- «rules.legal_moves предлагает dragon_collect». Сохранение проходит через
-- encode/decode и перепись, то есть фикстура — честная доска из 40 карт.

local function restore_on_bus(snap)
   stub.install()
   local queue, current = {}, "main"
   function _G.msg.post(to, id, data)
      queue[#queue + 1] = { to = tostring(to), id = tostring(id), data = data, from = current }
   end
   -- Каждый скрипт в своём окружении: глобальные init/on_message разных
   -- скриптов не должны затирать друг друга (и _G других тестов).
   local function load_env(path)
      local env = setmetatable({}, { __index = _G })
      assert(loadfile(path, "t", env))()
      return env
   end
   local inst = {}
   local function add(id, path)
      local env = load_env(path)
      local self = {}
      current = id
      -- rawget: окружение смотрит в _G, а там может лежать init/update
      -- main.script, загруженного предыдущими тестами через load_script.
      if rawget(env, "init") then env.init(self) end
      inst[id] = { env = env, self = self }
   end
   for i = 1, 3 do add("free_slot" .. i, "main/Scripts/free_cell.script") end
   for i = 1, 3 do add("dragon_button" .. i, "main/Scripts/dragon_button.script") end
   for i = 1, 8 do add("tableau_slot" .. i, "main/Scripts/tableau_script.script") end
   local main = load_env("main/Scripts/main.script")

   -- Что кнопки в итоге сказали курсору — ровно по этому флагу hit_test
   -- решает, можно ли по кнопке кликнуть.
   local button_active = {}
   local function pump()
      for _ = 1, 50 do
         local q = queue
         queue = {}
         for _, m in ipairs(q) do
            if m.to == "cursor" and m.id == hash("set_button_state") then
               button_active[m.data.slot_id] = m.data.is_active
            end
            local t = inst[m.to]
            if t then
               current = m.to
               t.env.on_message(t.self, hash(m.id), m.data or {}, m.from)
            end
         end
         for id, t in pairs(inst) do
            if rawget(t.env, "update") then current = id; t.env.update(t.self, 1 / 60) end
         end
         if #queue == 0 then return end
      end
      error("шина не успокоилась за 50 кадров")
   end

   -- Проводка, которую на старте уровня делают cursor и main.
   current = "cursor"
   for i = 1, 3 do
      msg.post("free_slot" .. i, "set_cursor", { slot_id = "free_slot" .. i, params = config.DRAGON_BUTTON_TRACE })
   end
   for i, suit in ipairs({ "red", "blue", "green" }) do
      msg.post("dragon_button" .. i, "set_button", { data = { sprite = suit, is_active = false },
         cursor = "cursor", slot_id = "dragon_button" .. i })
   end
   pump()

   local dec = assert(main.save_decode_snapshot(assert(main.save_encode_snapshot(snap))))
   local census = main.snapshot_census_error(dec)
   if census then error("фикстура теста нечестная по переписи: " .. tostring(census)) end
   local layout = main.snapshot_to_layout(dec)
   local mself = { cursor = "cursor", cards = {}, auto_collecting = false, auto_finishing = false }
   current = "main"
   main.restore_tableau_from_layout(mself, layout)
   pump()
   current = "main"
   main.restore_cells_and_foundation(mself, layout)
   pump()
   return button_active, dec
end

-- Честная доска: всё, кроме красных драконов, разложено по кругу; четыре
-- красных дракона расставляет `place_red(tableau, free_cells)`.
local function board_with_red_dragons(place_red)
   local snap = { tableau = {}, free_cells = { {}, {}, {} },
      foundation = { red = 1, blue = 1, green = 1 }, flower = false }
   for c = 1, 8 do snap.tableau[c] = {} end
   local rest = {}
   for _, s in ipairs({ "red", "blue", "green" }) do
      for v = 3, 10 do rest[#rest + 1] = { value = v, suit = s } end
      rest[#rest + 1] = { value = 2, suit = s }
   end
   for _ = 1, 4 do rest[#rest + 1] = { value = 'd', suit = "blue" } end
   for _ = 1, 4 do rest[#rest + 1] = { value = 'd', suit = "green" } end
   rest[#rest + 1] = { value = 'f', suit = "flower" }
   -- Первая розданная в колонку карта оказывается верхушкой: 3R..10R.
   for i, c in ipairs(rest) do table.insert(snap.tableau[((i - 1) % 8) + 1], 1, c) end
   place_red(snap.tableau, snap.free_cells)
   return snap
end

local function buttons_match_rules(button_active, dec)
   local legal = {}
   for _, mv in ipairs(rules.legal_moves(bridge.from_game(dec))) do
      if mv.type == "dragon_collect" then legal[mv.suit] = true end
   end
   for suit, btn in pairs(config.DRAGON_BUTTON_TRACE) do
      local lit = button_active[btn] == true
      if lit ~= (legal[suit] == true) then
         return false, string.format("масть %s: кнопка %s, а правила сбор %s", suit,
            lit and "горит" or "не горит", legal[suit] and "разрешают" or "не разрешают")
      end
   end
   return true, legal
end

H.test("D3 восстановление: дракон в незапечатанной ячейке засчитан кнопкой своей масти", function()
   local active, dec = restore_on_bus(board_with_red_dragons(function(tableau, cells)
      for c = 1, 3 do table.insert(tableau[c], { value = 'd', suit = "red" }) end
      cells[1] = { card = { value = 'd', suit = "red" } }
   end))
   local ok, legal = buttons_match_rules(active, dec)
   if not ok then return false, legal end
   if not legal.red then return false, "фикстура сломана: правила не предлагают сбор красных" end
   return true
end)

-- Негативный контроль: тот же дракон в ячейке, но один красный закопан под
-- картой. Правило «засчитать всех драконов раскладки» зажгло бы кнопку здесь.
H.test("D3 восстановление: закопанный дракон кнопкой не засчитан", function()
   local active, dec = restore_on_bus(board_with_red_dragons(function(tableau, cells)
      for c = 1, 2 do table.insert(tableau[c], { value = 'd', suit = "red" }) end
      table.insert(tableau[3], #tableau[3], { value = 'd', suit = "red" })  -- под верхушкой
      cells[1] = { card = { value = 'd', suit = "red" } }
   end))
   local ok, legal = buttons_match_rules(active, dec)
   if not ok then return false, legal end
   if legal.red then return false, "фикстура сломана: закопанный дракон не закопан" end
   return true
end)

return H
