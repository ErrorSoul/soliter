-- Minimal Defold API stubs so .script files can be loadfile'd in host Lua.
-- Not a simulator: enough for on_message / check_* unit tests.

local M = {}

function M.install()
   _G.hash = function(s) return tostring(s) end

   _G.vmath = {
      vector3 = function(x, y, z) return { x = x or 0, y = y or 0, z = z or 0 } end,
      vector4 = function(x, y, z, w) return { x = x or 0, y = y or 0, z = z or 0, w = w or 0 } end,
      quat = function() return {} end,
   }

   _G.msg = { log = {} }
   function _G.msg.post(to, id, data)
      _G.msg.log[#_G.msg.log + 1] = { to = to, id = tostring(id), data = data }
   end
   function _G.msg.clear()
      _G.msg.log = {}
   end

   _G.go = {
      get_id = function() return "self_go" end,
      get_position = function() return { x = 0, y = 0, z = 0 } end,
      set_position = function() end,
      animate = function() end,
      cancel_animations = function() end,
      set = function() end,
   }

   _G.sprite = { set_constant = function() end }
   _G.sound = { play = function() end }

   _G.timer = { pending = {} }
   function _G.timer.delay(_t, _repeat, cb)
      _G.timer.pending[#_G.timer.pending + 1] = cb
   end
   function _G.timer.flush()
      local q = _G.timer.pending
      _G.timer.pending = {}
      for i = 1, #q do q[i]() end
   end

   _G.window = {
      get_size = function() return 960, 540 end,
   }
end

function M.msg_count(id)
   local n = 0
   for _, e in ipairs(_G.msg.log) do
      if e.id == tostring(id) then n = n + 1 end
   end
   return n
end

function M.load_script(path)
   local chunk, err = loadfile(path)
   if not chunk then error("loadfile " .. path .. ": " .. tostring(err)) end
   return chunk()
end

return M
