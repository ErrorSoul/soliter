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
    -- The drop must land on a RUNNING cycle, or the check below would be vacuous.
    -- Today it does (deleting stop_dragon from drop_failed fails here, measured
    -- 2026-11-08), but only because of the current hold delays; the precondition
    -- keeps it so if the timing changes. The repeat comes within 2-6 s.
    for _=1,80 do
        if self.motion.age then break end
        update(self,.1)
    end
    assert(self.motion.age,"precondition: no running portrait cycle to cancel")
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

-- Owner decision 2026-11-06: while a card is held, a finished cycle repeats after
-- 2-6 s; an idle portrait waits 18-32 s and keeps a 7 s hover cooldown.
H.test("Portrait repeat timing: 2-6 s while held, 18-32 s idle",function()
    local function finish_cycle(held)
        local lo,hi=math.huge,-math.huge
        for i=1,30 do
            local s=motion.new("repeat-"..tostring(held)..i)
            if held then motion.hold(s) end
            local done=false
            for _=1,400 do
                if motion.update(s,.1,true,held)==0 then done=true; break end
            end
            assert(done,"cycle never finished")
            assert(not s.age,"finished cycle still running")
            lo=math.min(lo,s.wait); hi=math.max(hi,s.wait)
            if held then
                assert(s.cooldown==0,"held repeat kept the idle cooldown")
            else
                assert(s.cooldown==7,"idle cycle lost its 7 s cooldown")
            end
        end
        return lo,hi
    end
    local lo,hi=finish_cycle(true)
    assert(lo>=2 and hi<=6,("held repeat outside 2-6 s: %.2f..%.2f"):format(lo,hi))
    lo,hi=finish_cycle(false)
    assert(lo>=18 and hi<=32,("idle repeat outside 18-32 s: %.2f..%.2f"):format(lo,hi))
    return true
end)

-- Owner decision 2026-11-05: compact indices only on covered cards of a long
-- column; the exposed (last) card keeps the large index and is the only one that
-- may animate. Asserted from the rule, not from config.stack_offset_y.
H.test("Tableau layout: only covered cards of a long column are compact",function()
    local stub=require("solver.tests.defold_stub")
    stub.install()
    assert(loadfile("main/Scripts/tableau_script.script"))()
    local function layout(n)
        stub.go_self_pos=vmath.vector3(169,299,0)
        local self={stack={},index=2,cursor="cursor",visible_cards={}}
        for i=1,n do
            self.stack[i]={id="c"..i,data={value=2+(i%8),suit=(i%2==0) and "red" or "green"}}
        end
        msg.clear()
        update_visible_cards(self)
        local got={}
        for _,m in ipairs(msg.log) do
            if m.id=="index_layout" then got[m.to]=m.data end
        end
        for i=1,n do assert(got["c"..i],"no index_layout for card "..i.." of "..n) end
        return got
    end
    for _,n in ipairs({3,5}) do
        local got=layout(n)
        for i=1,n do
            assert(got["c"..i].compact~=true,("short column of %d: card %d compact"):format(n,i))
            assert((got["c"..i].exposed~=false)==(i==n),("short column of %d: card %d exposed=%s"):format(n,i,tostring(got["c"..i].exposed)))
        end
    end
    local n=12
    local got=layout(n)
    for i=1,n-1 do
        assert(got["c"..i].compact==true,"long column: covered card "..i.." keeps the large index")
        assert(got["c"..i].exposed==false,"long column: covered card "..i.." may animate")
    end
    assert(got["c"..n].compact~=true,"long column: exposed card got the compact index")
    assert(got["c"..n].exposed~=false,"long column: exposed card cannot animate")
    return true
end)

-- Owner decision 2026-11-06: collected dragons do not animate. Two layers guard
-- it: free_cell marks a completed landing as not exposed, and the card itself
-- ignores motion once collected. Each layer is pinned on its own (contract), and
-- the whole path end to end (behaviour): removing both layers stayed green before.
H.test("Collected dragons stay still: free cell contract, card contract, whole path",function()
    local stub=require("solver.tests.defold_stub")
    stub.install()
    assert(loadfile("main/Scripts/free_cell.script"))()
    local cell_message=on_message
    local trace={red="dragon_button1",blue="dragon_button2",green="dragon_button3"}
    local function cell_layout(complete)
        local cell={is_occupied=false,is_blocked=false,cursor="cursor",slot_id="free_slot1",
            dragon_button_trace=trace}
        msg.clear()
        cell_message(cell,hash("occupy_slot"),{complete=complete,animation=false,
            card={id="d1",data={value="d",suit="red",is_dragon=true}},position=vmath.vector3(65,457,0)},"d1")
        for _,m in ipairs(msg.log) do
            if m.id=="index_layout" and m.to=="d1" then return m.data end
        end
        error("free cell sent no index_layout")
    end
    assert(cell_layout(true).exposed==false,"free cell: collected dragon marked exposed")
    assert(cell_layout(false).exposed~=false,"free cell: parked dragon lost its exposure")

    assert(loadfile("main/Scripts/card.script"))()
    local card_init,card_message,card_update=init,on_message,update
    local function animated(card)
        msg.clear()
        card_message(card,hash("dragon_hover"),{})
        for _=1,450 do card_update(card,.1) end
        for _,m in ipairs(msg.log) do
            if m.id=="play_animation" and tostring(m.data.id):match("_motion_") then return true end
        end
        return false
    end
    local function dragon()
        local card={}; card_init(card)
        card_message(card,hash("set_card"),{data={value="d",suit="red",is_dragon=true},slot_id="column"})
        return card
    end
    local function land(card,complete)
        msg.clear()
        card_message(card,hash("drop_success"),{position=vmath.vector3(65,457,0),slot_id="free_slot1",
            card={id="d1",data={value="d",suit="red",is_dragon=true}},complete=complete})
    end

    -- Positive control: an exposed dragon parked by the player does animate.
    local parked=dragon(); land(parked,false)
    card_message(parked,hash("index_layout"),{compact=false,exposed=true})
    assert(animated(parked),"control: parked dragon never animates, test is blind")

    -- Card contract: collected, even if a slot wrongly reports it exposed.
    local collected=dragon(); land(collected,true)
    card_message(collected,hash("index_layout"),{compact=false,exposed=true})
    assert(not animated(collected),"card: collected dragon animates when reported exposed")

    -- Whole path: the card's landing message reaches the real free cell, and the
    -- cell's reply reaches the card.
    local real=dragon(); land(real,true)
    local posted={}
    for _,m in ipairs(msg.log) do posted[#posted+1]=m end
    local cell={is_occupied=false,is_blocked=false,cursor="cursor",slot_id="free_slot1",dragon_button_trace=trace}
    for _,m in ipairs(posted) do
        if m.id=="occupy_slot" then
            msg.clear()
            cell_message(cell,hash("occupy_slot"),m.data,"d1")
            for _,r in ipairs(msg.log) do
                if r.to=="d1" then card_message(real,hash(r.id),r.data or {}) end
            end
        end
    end
    assert(not animated(real),"collected dragon in a sealed cell animates")
    return true
end)
return H
