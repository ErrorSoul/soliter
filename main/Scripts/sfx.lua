local M = {}

-- Pending sounds from GUI (cross-collection workaround)
M.pending = nil

function M.play(sound_id)
    sound.play("sound_manager#" .. sound_id)
end

-- Queue a sound from GUI script (polled by main.script update)
function M.queue(sound_id)
    M.pending = sound_id
end

function M.card_pick()      M.play("card_pick") end
function M.card_drop()      M.play("card_drop") end
function M.card_error()     M.play("card_error") end
function M.card_deal()      M.play("card_deal") end
function M.dragon_collect() M.play("dragon_collect") end
function M.button_click()   M.queue("button_click") end
function M.victory()        M.play("victory") end
function M.flower_auto()    M.play("flower_auto") end
function M.auto_finish()    M.play("auto_finish") end

return M
