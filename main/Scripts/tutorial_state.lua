-- Состояние туториала, общее для трёх коллекций (main, cursor, ui.gui_script).
-- Обычный Lua-модуль вместо сообщений — тот же обходной путь через общий
-- require, что и у звука (docs/sounds.md): GUI живёт в своей коллекции и
-- сообщения уровня не видит, поэтому опрашивает флаги отсюда.
--
-- v3: сценарного списка шагов больше нет. Подсказка считается ОТ ДОСКИ
-- (solver/hint.lua) после каждого осевшего хода, а этот модуль — только почтовый
-- ящик между тем, кто её посчитал (main), и теми, кто рисует (ui) и подсвечивает
-- (cursor). Прежние EXPECTED_MOVES/HIGHLIGHTS/step были привязаны к НОМЕРУ шага:
-- любой законный, но «не тот» ход игрока (увести 5_green в ячейку первым ходом)
-- делал следующую подсказку невыполнимой навсегда — выход только по SKIP.
local M = {}
M.is_tutorial = false
M.ui_dirty = false      -- flag for UI polling (cross-collection workaround)
M.show_victory = false  -- flag for victory screen
M.highlight_dirty = false -- flag for cursor to apply highlights
M.block_play_input = false -- sticky: UI consumes show_victory, cards must stay dead

-- Текущая подсказка. Пишет main (единственный, у кого есть зеркало доски),
-- читают ui.gui_script и cursor.
--   M.hint = { kind = "foundation"|"free_cell"|"stack"|"empty_column"|"dragon",
--              distance = <ходов до победы>,
--              cards = { <id игровых объектов> },   -- что подсветить
--              slots = { <id слотов/кнопок> } }
--   M.hint_status = "found" | "stuck"
-- nil в hint при статусе "found" невозможен; "stuck" — доска встала, подсказывать
-- нечего, и UI предлагает начать заново.
M.hint = nil
M.hint_status = nil

-- Подсказку ставим ЦЕЛИКОМ и одним вызовом: и текст (ui_dirty), и подсветка
-- (highlight_dirty) обязаны обновиться от одной и той же доски. Раздельные
-- присваивания однажды разъедутся — текст про ячейку поверх подсвеченного
-- основания читается как ошибка игры.
function M.set_hint(hint, status)
   M.hint = hint
   M.hint_status = status
   M.ui_dirty = true
   M.highlight_dirty = true
end

function M.clear_hint()
   M.set_hint(nil, nil)
end

function M.reset()
    M.ui_dirty = false
    M.show_victory = false
    M.highlight_dirty = false
    M.block_play_input = false
    M.hint = nil
    M.hint_status = nil
end

-- Pulse show_victory for the UI poll; keep play input blocked after the pulse is consumed.
function M.request_victory()
    M.show_victory = true
    M.block_play_input = true
end

function M.is_play_input_blocked()
    return M.block_play_input == true
end

return M
