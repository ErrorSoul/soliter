local yandex = require("main.Scripts.yandex")

local M = {}

M.lang = "en"

M.strings = {
    en = {
        music_on = "MUSIC ON",
        music_off = "MUSIC OFF",
        -- v3: подсказка считается от доски, поэтому ключ — ТИП хода, а не номер
        -- шага. Текст обязан быть верным для любой карты этого типа: называть
        -- конкретную карту («перетащи КРАСНУЮ 2») больше нельзя — подсветка
        -- показывает какую, а ход зависит от того, что игрок уже натворил.
        tutorial_goal = "Collect all four dragons",
        tutorial_hint_foundation = "This one goes up to the foundation",
        tutorial_hint_free_cell = "Nowhere to put it? A free cell holds one card",
        tutorial_hint_stack = "Stack it on the next card up, of another suit",
        tutorial_hint_empty_column = "An empty column takes any card",
        tutorial_hint_dragon = "All four dragons are out - press the button",
        tutorial_stuck = "No moves left - press SKIP",
        tutorial_moves_left = "%d to win",
        skip = "SKIP",
        restart = "RESTART",
        tutorial = "TUTORIAL",
        play = "PLAY",
        title = "Shenzhen Solitaire",
        victory = "Victory!",
        well_done = "Well done!",
        play_again = "PLAY AGAIN",
        play_now = "PLAY NOW",
        menu = "MENU",
        menu_eyebrow = "A MOMENT OF FOCUS",
        menu_caption = "Three suits. Four dragons. One clear table.",
        menu_footer = "Your game is saved automatically",
        board_complete = "Every card in its place. Beautifully done.",
        practice_complete = "You know the moves. Your game is waiting.",
        victory_footer = "Take a breath. Then try another deal.",
    },
    ru = {
        music_on = "МУЗ. ВКЛ",
        music_off = "МУЗ. ВЫКЛ",
        tutorial_goal = "Собери четырёх драконов",
        tutorial_hint_foundation = "Эта карта уходит наверх, в основание",
        tutorial_hint_free_cell = "Некуда положить? Ячейка держит одну карту",
        tutorial_hint_stack = "Клади на карту старше на единицу, другой масти",
        tutorial_hint_empty_column = "Пустая колонка примет любую карту",
        tutorial_hint_dragon = "Все четыре дракона на виду — жми кнопку",
        tutorial_stuck = "Ходов не осталось — жми ПРОПУСК",
        tutorial_moves_left = "до победы: %d",
        skip = "ПРОПУСК",
        restart = "ЗАНОВО",
        tutorial = "ОБУЧЕНИЕ",
        play = "ИГРАТЬ",
        title = "Шэньчжэнь Солитер",
        victory = "Победа!",
        well_done = "Отлично!",
        play_again = "ЕЩЁ РАЗ",
        play_now = "ИГРАТЬ",
        menu = "МЕНЮ",
        menu_eyebrow = "ВРЕМЯ СОСРЕДОТОЧИТЬСЯ",
        menu_caption = "Три масти. Четыре дракона. Чистый стол.",
        menu_footer = "Партия сохраняется автоматически",
        board_complete = "Каждая карта на своём месте. Красиво!",
        practice_complete = "Правила освоены. Ваша партия ждёт.",
        victory_footer = "Немного выдохнуть — и новая раздача.",
    },
    tr = {
        music_on = "MUZIK ACIK",
        music_off = "MUZIK KAPALI",
        tutorial_goal = "Dort ejderhayi topla",
        tutorial_hint_foundation = "Bu kart temele gider",
        tutorial_hint_free_cell = "Yer yok mu? Bos hucre bir kart tutar",
        tutorial_hint_stack = "Bir buyuk ve baska renk kartin ustune koy",
        tutorial_hint_empty_column = "Bos sutun her karti alir",
        tutorial_hint_dragon = "Dort ejderha da acikta - dugmeye bas",
        tutorial_stuck = "Hamle kalmadi - ATLA'ya bas",
        tutorial_moves_left = "%d hamle kaldi",
        skip = "ATLA",
        restart = "YENIDEN",
        tutorial = "EGITIM",
        play = "OYNA",
        title = "Shenzhen Solitaire",
        victory = "Zafer!",
        well_done = "Harika!",
        play_again = "TEKRAR OYNA",
        play_now = "SIMDI OYNA",
        menu = "MENU",
        menu_eyebrow = "ODAKLANMA ZAMANI",
        menu_caption = "Uc renk. Dort ejderha. Tertemiz bir masa.",
        menu_footer = "Oyununuz otomatik kaydedilir",
        board_complete = "Her kart yerinde. Harika oynadiniz.",
        practice_complete = "Artik hazirsiniz. Oyununuz sizi bekliyor.",
        victory_footer = "Bir nefes alin. Sonra yeniden deneyin.",
    },
}

local wildlife_strings = {
    en = {tutorial_goal = "Collect four crowned guardians", tutorial_hint_dragon = "Four crowned guardians are out - press their button", menu_caption = "Three suits. Four guardians. One clear table."},
    ru = {tutorial_goal = "Собери четырёх стражей с коронами", tutorial_hint_dragon = "Четыре стража с коронами на виду — жми кнопку", menu_caption = "Три масти. Четыре стража. Чистый стол."},
    tr = {tutorial_goal = "Dort tacli muhafizi topla", tutorial_hint_dragon = "Dort tacli muhafiz acikta - dugmeye bas", menu_caption = "Uc renk. Dort muhafiz. Tertemiz bir masa."},
}

if require("main.Scripts.theme").wildlife then
    for lang, strings in pairs(wildlife_strings) do
        for key, value in pairs(strings) do M.strings[lang][key] = value end
    end
end

function M.t(key)
    local lang_strings = M.strings[M.lang]
    if lang_strings and lang_strings[key] then
        return lang_strings[key]
    end
    return M.strings.en[key] or key
end

function M.set_lang(lang)
    if M.strings[lang] then
        M.lang = lang
    end
end

-- H2: определить язык. Порядок намеренный.
--
-- 1. SDK Я.Игр (`ysdk.environment.i18n.lang`, через мост D1). Единственный
--    источник, который знает язык ИГРОКА, а не его браузера: в iframe платформы
--    русский игрок с английским Chrome обязан получить русскую игру. Приезжает
--    асинхронно — пока промис не разрешился, тут пусто и работают пункты ниже,
--    а game_manager по готовности шлёт `language_ready` и подписи перекрашиваются.
-- 2. `?lang=xx` в адресе. Способ переключить язык без SDK — обычным html5.run;
--    сценарий стенда `i18n` пользуется именно им. Что платформа кладёт язык ещё
--    и в URL, по первоисточнику НЕ проверялось, поэтому ниже SDK.
-- 3. Язык системы/браузера — разумный дефолт вне Я.Игр.
-- 4. Английский.
--
-- Незнакомый код молча игнорируем: set_lang сам отсеет то, чего нет в strings.
local function two_letters(s)
    if type(s) ~= "string" then return nil end
    local code = s:match("^%s*([A-Za-z][A-Za-z])")
    return code and code:lower() or nil
end

function M.detect()
    local sdk_lang = two_letters(yandex.lang())
    if sdk_lang and M.strings[sdk_lang] then
        return sdk_lang
    end
    if html5 then
        local ok, search = pcall(html5.run, "window.location.search")
        if ok and type(search) == "string" then
            local code = two_letters(search:match("[?&]lang=([^&]+)"))
            if code and M.strings[code] then return code end
        end
    end
    local ok, info = pcall(sys.get_sys_info)
    if ok and info then
        local code = two_letters(info.device_language) or two_letters(info.language)
        if code and M.strings[code] then return code end
    end
    return "en"
end

return M
