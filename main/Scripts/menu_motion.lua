-- Menu-only decoration; no timers, input hooks or gameplay random numbers.
local M={}
function M.update(self,dt)
    if self.game_started then return end
    self.menu_time=(self.menu_time or 0)+dt
    local t=self.menu_time
    gui.set_position(gui.get_node("menu_left"),vmath.vector3(7*math.sin(t*.24),9*math.sin(t*.19),0))
    gui.set_position(gui.get_node("menu_right"),vmath.vector3(-7*math.sin(t*.21),-9*math.sin(t*.17),0))
    gui.set_position(gui.get_node("menu_mist_left"),vmath.vector3(-280+42*math.sin(t*.13),-35+18*math.sin(t*.18),0))
    gui.set_position(gui.get_node("menu_mist_right"),vmath.vector3(280-38*math.sin(t*.11),55+22*math.sin(t*.15),0))
    self.menu_frames=self.menu_frames or {}
    for i,suit in ipairs({"red","green","blue"}) do
        local phase=(t+(i-1)*3.1)%13
        local frame=phase<2.4 and math.min(18,1+math.floor(phase/2.4*18)) or 0
        if self.menu_frames[suit]~=frame then
            local name="d_"..suit..(frame>0 and "_motion_"..frame or "")
            gui.play_flipbook(gui.get_node("start_card_"..suit),name)
            self.menu_frames[suit]=frame
        end
    end
end
return M
