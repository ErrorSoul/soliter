local H = require("solver.tests.harness")()

H.test("Music: one persistent voice, pause/resume without stacking, final stops it", function()
    local calls = {}
    local env = setmetatable({
        hash = function(s) return s end,
        print = function() end,
        sound = {
            play = function(url, opts) assert(opts.gain == 0); calls[#calls+1] = "play:" .. url end,
            set_gain = function(url, gain) assert(gain >= 0 and gain <= 1) end,
            pause = function(url, pause) calls[#calls+1] = pause and "pause" or "resume" end,
            stop = function(url) calls[#calls+1] = "stop:" .. url end,
        },
    }, {__index = _G})
    assert(loadfile("main/Scripts/music.script", "t", env))()
    local self = {}
    env.init(self)
    assert(#calls == 0, "music must wait for a gesture")
    env.on_message(self, "music_state", {enabled=false})
    assert(#calls == 0, "saved mute must not start audio")
    for _=1,10 do env.on_message(self, "music_state", {enabled=true}) end
    assert(table.concat(calls,",") == "play:#ambient", "repeated taps stacked voices")
    env.update(self, 1)
    assert(self.level == 1)
    env.on_message(self, "music_state", {enabled=false})
    env.update(self, 0.09)
    assert(self.level > 0 and self.level < 1, "mute must fade")
    env.on_message(self, "music_state", {enabled=false})
    env.update(self, 0.2)
    env.on_message(self, "music_state", {enabled=true})
    env.update(self, 0.4)
    assert(self.level > 0 and self.level < 1, "resume must fade")
    env.on_message(self, "music_state", {enabled=false})
    env.update(self, 0.03)
    env.on_message(self, "music_state", {enabled=true})
    env.update(self, 1)
    assert(self.level == 1, "rapid toggles must not strand audio")
    env.final(self)
    assert(table.concat(calls,",") == "play:#ambient,pause,resume,stop:#ambient")
    return true
end)

return H
