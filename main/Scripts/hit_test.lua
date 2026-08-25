-- hit_test.lua — проверки попадания курсора в игровые объекты
-- Все функции принимают cursor state (self из cursor.script).
local config = require("main.Scripts.config")
local tutorial_state = require("main.Scripts.tutorial_state")
local M = {}

function M.is_point_in_rect(x, y, rect_pos, half_size)
   return (x > rect_pos.x - half_size.x and
           x < rect_pos.x + half_size.x and
           y > rect_pos.y - half_size.y and
           y < rect_pos.y + half_size.y)
end

local function is_card_in_stack(card_id, stack_cards)
    if not stack_cards then return false end
    for _, stack_card in ipairs(stack_cards) do
        if stack_card.id == card_id then
            return true
        end
    end
    return false
end

function M.check_tableau_slots(state, cursor_x, cursor_y)
   for stack_index, stack in ipairs(state.tableau_stacks) do
      -- H6: колонку, чья верхушка вот-вот улетит сама, не отдаём вообще —
      -- ни верхушку, ни карты под ней. Под ней потому, что любой захват группы
      -- тянется ДО верхушки (см. цикл ниже: от найденной карты до #stack), то
      -- есть улетающая карта всё равно оказалась бы в руке.
      --
      -- Верхушка — это stack[#stack]: курсор получает набор от
      -- tableau_script.update_visible_cards уже развёрнутым (reverse_table), и
      -- last_card_to_slot берёт ту же самую карту.
      local leaving = #stack > 0
         and config.auto_flies_from_tableau(stack[#stack].data, tutorial_state.is_tutorial)
      if #stack > 0 and not leaving then
         local last_card_index = #stack
         local last_card = stack[last_card_index]
         local last_card_pos = go.get_position(last_card.id)

         if M.is_point_in_rect(cursor_x, cursor_y, last_card_pos, config.CARD_HALF_SIZE) then
            return {
               type = "tableau",
               id = last_card.id,
               stack_index = stack_index,
               card_index = last_card_index,
               is_single = true,
               pos = last_card_pos,
               slot_id = last_card.slot_id,
               source = last_card
            }
         end

         for card_index = last_card_index - 1, 1, -1 do
            local card = stack[card_index]
            local card_pos = go.get_position(card.id)

            if M.is_point_in_rect(cursor_x, cursor_y, card_pos, config.CARD_HALF_SIZE) then
               local selected_stack = {}
               local base_pos = card_pos

               for i = card_index, #stack do
                   local stack_card = stack[i]
                   local relative_pos = go.get_position(stack_card.id) - base_pos
                   table.insert(selected_stack, {
                       id = stack_card.id,
                       source = stack_card,
                       relative_pos = relative_pos
                   })
               end

               return {
                  type = "tableau",
                  id = card.id,
                  stack_index = stack_index,
                  card_index = card_index,
                  stack = selected_stack,
                  is_stack = true,
                  pos = card_pos,
                  slot_id = card.slot_id,
                  source = card
               }
            end
         end
      end
   end
   return nil
end

function M.check_last_cards(state, cursor_x, cursor_y)
   for stack_index, card in pairs(state.last_cards) do
        local card_pos = go.get_position(card.id)
      if card.id ~= state.selected_card and
         not is_card_in_stack(card.id, state.stack_cards) and
         M.is_point_in_rect(cursor_x, cursor_y, card_pos, config.CARD_HALF_SIZE) then

         return {
            type = "tableau",
            id  = card.id,
            stack_index = stack_index,
            card_data = card.data,
            data_id = card.data.id,
            slot_id = card.slot_id,
            pos = card_pos,
            source = card
         }
      end
   end
   return nil
end

function M.check_free_slots(state, cursor_x, cursor_y)
   for slot_id, slot in pairs(state.free_slots) do
      if M.is_point_in_rect(cursor_x, cursor_y, slot.pos, config.CARD_HALF_SIZE) then
         return {slot_id = slot_id, slot_pos = slot.pos}
      end
   end
end

function M.check_flower_slot(state, cursor_x, cursor_y)
   local slot_id = 'flower_slot'
   if M.is_point_in_rect(cursor_x, cursor_y, state.flower_slot[slot_id], config.CARD_HALF_SIZE) then
      return {slot_id = slot_id, slot_pos = state.flower_slot[slot_id]}
   end
end

function M.check_base_slots(state, cursor_x, cursor_y)
   for slot_id, slot in pairs(state.base_slots) do
      if M.is_point_in_rect(cursor_x, cursor_y, slot.pos, config.CARD_HALF_SIZE) then
         return {slot_id = slot_id, slot_pos = slot.pos}
      end
   end
end

function M.check_free_tableau_slots(state, cursor_x, cursor_y)
   for slot_id, slot in pairs(state.tableau_slots) do
      if slot.is_empty and M.is_point_in_rect(cursor_x, cursor_y, slot.pos, config.CARD_HALF_SIZE) then
         return {slot_id = slot_id, slot_pos = slot.pos}
      end
   end
end

function M.check_dragon_buttons(state, cursor_x, cursor_y)
   for btn_id, btn in pairs(state.dragon_buttons) do
      if btn.is_active and M.is_point_in_rect(cursor_x, cursor_y, btn.pos, config.BTN_HALF_SIZE) then
         return {slot_id = btn_id, color = btn.sprite}
      end
   end
end

return M
