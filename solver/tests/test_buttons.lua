local H = require("solver.tests.harness")()
local stub = require("solver.tests.defold_stub")
local button = require("main.Scripts.button")

H.test("Buttons: release activates once; outside, hidden and changed screen cancel", function()
    stub.install()
    local old_gui, poses = gui, {}
    local disabled = false
    gui = {
        get_node=function(id) return id end,
        is_enabled=function() return not disabled end,
        pick_node=function(_,x) return x == 1 end,
        cancel_animations=function() end,
        animate=function(n,_,v) poses[#poses+1]=v.x end,
        EASING_OUTQUAD=0, EASING_OUTBACK=1,
    }
    local state, ids = {}, {"play"}
    local function input(a) return button.input(state,a,ids) end
    local ok,err=pcall(function()
        local clicked,consumed=input({pressed=true,x=1})
        assert(not clicked and consumed and poses[#poses]==0.94)
        clicked,consumed=input({released=true,x=1})
        assert(clicked=="play" and consumed and poses[#poses]==1)
        assert(not input({released=true,x=1}), "duplicate release activated")
        input({pressed=true,x=1})
        assert(not input({released=true,x=2}), "release outside activated")
        input({pressed=true,x=1})
        ids={"menu"}
        assert(not input({released=true,x=1}), "hidden old screen activated")
        ids={"play"}; disabled=true
        local _,caught=input({pressed=true,x=1})
        assert(not caught, "disabled button consumed press")
        disabled=false
        input({pressed=true,x=1})
        button.cancel(state)
        assert(not state.pressed and poses[#poses]==1)
    end)
    gui=old_gui
    assert(ok,err)
    return true
end)

H.test("Card indices: compact column switches face; short column restores large index", function()
    stub.install()
    assert(loadfile("main/Scripts/card.script"))()
    local self={}; init(self)
    on_message(self,hash("set_card"),{data={value=10,suit="blue"},slot_id="column"})
    msg.clear()
    on_message(self,hash("index_layout"),{compact=true})
    assert(msg.log[#msg.log].data.id==hash("10_blue_compact"))
    on_message(self,hash("index_layout"),{compact=false})
    assert(msg.log[#msg.log].data.id==hash("10_blue"))
    return true
end)
return H
