-- Pure timing for decorative portrait animation. Never consumes gameplay RNG.
local M = { DURATION=2.4, FRAMES=18 }
function M.new(identity)
    local seed=0
    for i=1,#identity do seed=(seed*31+identity:byte(i))%997 end
    return {seed=(seed+1)*104729, wait=12+seed%17, interval=18+seed%15, cooldown=0, age=nil, frame=0}
end
-- Private PRNG: cosmetic timing never changes shuffled deals or solver randomness.
local function random(s)
    s.seed=(s.seed*48271)%2147483647
    return s.seed/2147483647
end
function M.hold(s)
    s.wait=.7+random(s)*2.3
    s.cooldown=0
end
function M.start(s)
    if s.age or s.cooldown>0 then return false end
    s.age=0; s.frame=0; s.cooldown=7
    return true
end
function M.stop(s)
    if not s then return false end
    local was=s.age~=nil
    s.age=nil; s.frame=0; s.wait=s.interval
    return was
end
-- nil = unchanged; 0 = restore still face; 1..18 = illustration frame.
function M.update(s,dt,eligible,held)
    s.cooldown=math.max(0,s.cooldown-dt)
    if not eligible then
        if M.stop(s) then return 0 end
        return nil
    end
    if not s.age then
        s.wait=s.wait-dt
        if s.wait<=0 then M.start(s) end
    end
    if s.age then
        s.age=s.age+dt
        if s.age>=M.DURATION then
            M.stop(s)
            s.wait=held and (2+random(s)*4) or (18+random(s)*14)
            s.cooldown=held and 0 or 7
            return 0
        end
        local frame=math.min(M.FRAMES,1+math.floor(s.age/M.DURATION*M.FRAMES))
        if frame~=s.frame then s.frame=frame; return frame end
    end
end
return M
