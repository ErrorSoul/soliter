local H=require("solver.tests.harness")()
local motion=require("main.Scripts.dragon_motion")
H.test("Dragon motion: rare, bounded, interruptible and independent of gameplay RNG",function()
    local a=motion.new("dragon-red-1")
    local b=motion.new("dragon-blue-2")
    assert(a.wait>=12 and a.wait<=28 and a.interval>=18)
    assert(a.wait~=b.wait,"dragons breathe in lockstep")
    local random=math.random
    math.random=function() error("decorative effect consumed game RNG") end
    local ok,err=pcall(function()
        assert(motion.start(a))
        assert(not motion.start(a),"hover restarts a running effect")
        local frame=motion.update(a,.6,true)
        assert(frame and frame>0)
        assert(motion.update(a,.1,false)==0,"drag/covered/highlight did not stop effect")
        assert(not motion.start(a),"hover bypassed cooldown")
        motion.update(a,8,true)
        assert(motion.start(a))
        assert(motion.update(a,3,true)==0 and not a.age,"animation never settles")
        for _=1,40 do motion.update(a,.1,false) end
        assert(not a.age and a.wait==a.interval,"covered dragon animates")
    end)
    math.random=random
    assert(ok,err)
    return true
end)
H.test("Held portraits: delayed varied cycles without game RNG",function()
    local a=motion.new("fox")
    local lo,hi=3,0
    for i=1,40 do
        local sample=motion.new("card-"..i); motion.hold(sample)
        lo=math.min(lo,sample.wait); hi=math.max(hi,sample.wait)
    end
    assert(hi-lo>1.5,"first hold delays cluster instead of spreading out")
    local old=math.random
    math.random=function() error("consumed gameplay RNG") end
    local ok,err=pcall(function()
        motion.hold(a)
        local first=a.wait
        assert(first>=.7 and first<=3)
        assert(motion.update(a,.1,true,true)==nil,"hold starts instantly")
        local began=false
        for _=1,30 do if motion.update(a,.1,true,true) then began=true end end
        assert(began,"held portrait never moves")
        for _=1,24 do motion.update(a,.1,true,true) end
        motion.stop(a); motion.hold(a)
        assert(a.wait~=first,"repeat holds use identical delay")
    end)
    math.random=old
    assert(ok,err)
    return true
end)
H.test("Real animal card: animates while held, cancels on drop and covered layout",function()
    local stub=require("solver.tests.defold_stub")
    stub.install()
    assert(loadfile("main/Scripts/card.script"))()
    local self={}; init(self)
    on_message(self,hash("set_card"),{data={value=7,suit="red"},slot_id="column"})
    on_message(self,hash("start_drag"),{})
    local portrait_tint
    local old_set=go.set
    go.set=function(url,prop,value)
        if url=="#portrait" and prop=="tint" then portrait_tint=value end
        old_set(url,prop,value)
    end
    msg.clear()
    for _=1,35 do update(self,.1) end
    local seen=false
    for _,m in ipairs(msg.log) do
        if m.id=="play_animation" and tostring(m.data.id):match("animal_red_motion_") then seen=true end
    end
    assert(seen,"ordinary animal never animates while held")
    assert(portrait_tint and portrait_tint.x==1.15 and portrait_tint.w==1,
        "animated portrait lost the held card tint")
    on_message(self,hash("drop_failed"),{position=vmath.vector3(65,159,0.03)})
    assert(not self.motion.age,"failed drop retained animated portrait")
    on_message(self,hash("index_layout"),{compact=true,exposed=false})
    msg.clear()
    for _=1,400 do update(self,.1) end
    assert(#msg.log==0,"covered card animated over its compact index")
    return true
end)
H.test("Foundation: landed and restored cards stay still, including covered ranks",function()
    local stub=require("solver.tests.defold_stub")
    stub.install()
    assert(loadfile("main/Scripts/card.script"))()
    local card_init,card_message,card_update=init,on_message,update
    assert(loadfile("main/Scripts/base_slot.script"))()
    local base_message=on_message
    local base={}; init(base)
    base.cursor="cursor"; base.slot_id="foundation_red"
    local cards={}
    for _,restored in ipairs({false,true}) do
        for value=2,3 do
            local card={}; card_init(card)
            local id="card_"..tostring(restored)..value
            card_message(card,hash("set_card"),{data={value=value,suit="red"},slot_id="column"})
            if not restored then
                card_message(card,hash("drop_success"),{position=vmath.vector3(585,457,0),
                    slot_id="foundation_red",card={id=id,data={value=value,suit="red"}},animation=value==3})
            end
            msg.clear()
            base_message(base,hash("occupy_slot"),{card={id=id,data={value=value,suit="red"}},animation=value==3})
            local posted={}
            for _,m in ipairs(msg.log) do posted[#posted+1]=m end
            for _,m in ipairs(posted) do
                if m.to==id then card_message(card,hash(m.id),m.data or {}) end
            end
            cards[#cards+1]=card
        end
    end
    msg.clear()
    for _,card in ipairs(cards) do
        card_message(card,hash("dragon_hover"),{})
        for _=1,450 do card_update(card,.1) end
    end
    for _,m in ipairs(msg.log) do
        assert(m.id~="play_animation","foundation card started portrait animation")
    end
    return true
end)
return H
