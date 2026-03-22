local M = {}

M.lang = "en"

M.strings = {
    en = {
        tutorial_hint_0 = "Drag RED 2 to foundation!",
        tutorial_hint_1 = "Send RED 3 to foundation!",
        tutorial_hint_2 = "Move GREEN 7 to a free cell!",
        tutorial_hint_3 = "Stack BLUE 4 on GREEN 5!",
        tutorial_hint_4 = "Press the dragon button!",
        tutorial_done = "You did it!",
        tutorial_step = "%d/5",
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
    },
    ru = {
        tutorial_hint_0 = "Перетащи КРАСНУЮ 2 в фундамент!",
        tutorial_hint_1 = "Отправь КРАСНУЮ 3 в фундамент!",
        tutorial_hint_2 = "Переложи ЗЕЛЁНУЮ 7 в свободную ячейку!",
        tutorial_hint_3 = "Положи СИНЮЮ 4 на ЗЕЛЁНУЮ 5!",
        tutorial_hint_4 = "Нажми кнопку дракона!",
        tutorial_done = "Отлично!",
        tutorial_step = "%d/5",
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
    },
    tr = {
        tutorial_hint_0 = "KIRMIZI 2'yi temele yukle!",
        tutorial_hint_1 = "KIRMIZI 3'u temele gonder!",
        tutorial_hint_2 = "YESIL 7'yi bos hucreye tasi!",
        tutorial_hint_3 = "MAVI 4'u YESIL 5'in ustune koy!",
        tutorial_hint_4 = "Ejderha dugmesine bas!",
        tutorial_done = "Basardin!",
        tutorial_step = "%d/5",
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
    },
}

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

return M
