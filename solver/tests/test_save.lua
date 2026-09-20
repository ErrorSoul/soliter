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
-- НЕ проверяется здесь (и не может быть проверено без песочницы/движка):
--   - restore_tableau_from_layout/restore_cells_and_foundation — они гоняют
--     factory.create, которого нет в defold_stub (сознательно: стаб не должен
--     выдумывать поведение движка, которого не проверял никто). Эти функции
--     собраны из ТЕХ ЖЕ примитивов (factory+set_card+update_stack/occupy_slot),
--     что уже используют deal_dragon_test и не проверяются юнитами вовсе —
--     тот же класс риска, что и у остальной раздачи.
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

return H
