local M = {}
M.is_tutorial = false
M.step = 0
M.ui_dirty = false      -- flag for UI polling (cross-collection workaround)
M.show_victory = false  -- flag for victory screen

-- Expected moves per step: {card_id, target}
-- target: "base", "free", "tableau_card"
-- Step 3 (dragon button) is validated by button activation, not here
M.EXPECTED_MOVES = {
    [0] = {card_id = "2_red", target = "base"},
    [1] = {card_id = "3_red", target = "base"},
    [2] = {card_id = "7_green", target = "free"},
    [3] = {card_id = "4_blue", target = "tableau_card", target_card_id = "5_green"},
    -- step 4 = dragon button, validated by button activation
}

function M.check_move(card_data_id, target_type, target_card_id)
    if not M.is_tutorial then return true end
    local expected = M.EXPECTED_MOVES[M.step]
    if not expected then return true end
    if expected.card_id ~= card_data_id then return false end
    if expected.target ~= target_type then return false end
    if expected.target_card_id and expected.target_card_id ~= target_card_id then return false end
    return true
end

function M.advance()
    M.step = M.step + 1
    M.ui_dirty = true
end

function M.reset()
    M.step = 0
    M.ui_dirty = false
    M.show_victory = false
end

return M
