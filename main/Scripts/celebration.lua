-- Bounded, one-shot GUI confetti. Deterministic variation deliberately avoids
-- math.random: cosmetic effects must never change the next shuffled deal.
local M = {}
local COLORS = {
   {1.0, 0.79, 0.28}, {0.39, 0.83, 0.65}, {0.94, 0.43, 0.36}, {1.0, 0.93, 0.69},
}
local COUNT, DURATION = 40, 2.8

function M.clear(self)
   for _, p in ipairs(self.confetti or {}) do gui.delete_node(p.node) end
   self.confetti = nil
end

function M.start(self)
   M.clear(self)
   self.confetti = {}
   self.confetti_time = 0
   for i = 1, COUNT do
      local side = i % 2 == 0 and 1 or -1
      local node = gui.new_box_node(vmath.vector3(), vmath.vector3(5 + i % 3, 3 + i % 2, 0))
      gui.set_parent(node, gui.get_node("victory_overlay"), false)
      gui.set_layer(node, "layer")
      gui.set_inherit_alpha(node, true)
      self.confetti[i] = {node = node, side = side, color = COLORS[1 + i % #COLORS],
         vx = -side * (100 + (i * 29) % 190), vy = 350 + (i * 47) % 210,
         delay = (i % 5) * 0.045, phase = i * 1.7}
      gui.set_enabled(node, false)
   end
end

function M.update(self, dt)
   if not self.confetti then return end
   if not gui.is_enabled(gui.get_node("victory_overlay")) then M.clear(self); return end
   self.confetti_time = self.confetti_time + dt
   if self.confetti_time >= DURATION then M.clear(self); return end
   for _, p in ipairs(self.confetti) do
      local t = self.confetti_time - p.delay
      gui.set_enabled(p.node, t >= 0)
      if t >= 0 then
         gui.set_position(p.node, vmath.vector3(p.side * 450 + p.vx * t,
            -240 + p.vy * t - 170 * t * t, 0))
         gui.set_rotation(p.node, vmath.vector3(0, 0, p.phase * 30 + p.side * t * 210))
         gui.set_scale(p.node, vmath.vector3(0.3 + 0.7 * math.abs(math.cos(t * 8 + p.phase)), 1, 1))
         local alpha = math.min(1, math.max(0, (DURATION - self.confetti_time) / 0.7))
         gui.set_color(p.node, vmath.vector4(p.color[1], p.color[2], p.color[3], alpha))
      end
   end
end

return M
