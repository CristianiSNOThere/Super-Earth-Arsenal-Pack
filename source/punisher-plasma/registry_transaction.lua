-- Dependency-injected publication core. No game discovery, native calls or
-- Windows API here. The adapter must validate exact build, slot ownership,
-- pointed record bytes, allocation lifetime and resource epoch before use.
local M={}
local function read(api,address,size)
    local result=api.read(address,size)
    assert(type(result)=='string' and #result==size,'Registry read failed')
    return result
end
local function validate(api,plan)
    assert(plan.approved==true,'Registry slot ownership is not approved')
    assert(type(plan.epoch)=='string' and #plan.epoch>0,'Missing registry resource epoch')
    assert(api.epoch()==plan.epoch,'Registry resource epoch changed')
    assert(#plan.slots==3 or #plan.slots==4 or #plan.slots==6 or #plan.slots==7,'Unexpected registry publication plan')
    local kinds=#plan.slots==7 and {'explosion','damage','damage','explosion','explosion','projectile','projectile'}
      or (#plan.slots==6 and {'explosion','damage','damage','explosion','explosion','projectile'}
      or (#plan.slots==4 and {'damage','damage','explosion','projectile'} or {'damage','explosion','projectile'})
      )
    local keys={}
    for i,slot in ipairs(plan.slots) do
        assert(slot.kind==kinds[i],'Registry dependency order changed')
        assert(type(slot.before)=='string' and #slot.before==8
            and type(slot.after)=='string' and #slot.after==8,'Invalid registry pointer bytes')
        assert(slot.before~=slot.after,'Replacement must have separate owned storage')
        assert(slot.pin~=nil,'Replacement allocation is not retained')
        assert(type(slot.original_record)=='string' and type(slot.replacement_record)=='string'
            and #slot.original_record==#slot.replacement_record,'Invalid registry record')
        local size=({damage=76,explosion=152,projectile=272})[slot.kind]
        assert(#slot.original_record==size,'Registry record size changed')
        local key=api.identity(slot.address)
        assert(not keys[key],'Overlapping registry slots');keys[key]=true
        assert(api.slot_allowed(slot.kind,slot.id,slot.address),'Unapproved registry address')
        assert(read(api,slot.original_address,size)==slot.original_record,'Original registry record changed')
        assert(read(api,slot.replacement_address,size)==slot.replacement_record,'Replacement record changed')
        assert(api.pointer_bytes(slot.original_address)==slot.before
            and api.pointer_bytes(slot.replacement_address)==slot.after,'Registry pointer encoding mismatch')
        assert(read(api,slot.address,8)==slot.before,'Registry slot was changed externally')
    end
    assert(api.epoch()==plan.epoch,'Registry resource epoch changed during validation')
end

function M.publish(api,plan)
    validate(api,plan)
    local state={epoch=plan.epoch,slots=plan.slots,pins={},active=false,poisoned=false}
    -- Pin first and retain even on failure: a partially published pointer must
    -- never outlive its allocation. Adapter retain is process-lifetime storage.
    for i,slot in ipairs(plan.slots) do state.pins[i]=slot.pin end
    api.retain(state)
    local attempted={}
    local ok,reason=pcall(function()
        for _,slot in ipairs(plan.slots) do
            assert(api.epoch()==plan.epoch,'Resource epoch changed before publication')
            assert(read(api,slot.address,8)==slot.before,'Registry pointer changed before publication')
            attempted[#attempted+1]=slot -- write can partly succeed before failure
            assert(api.write_slot(slot.kind,slot.id,slot.address,slot.after),'Registry pointer write failed')
            assert(read(api,slot.address,8)==slot.after,'Registry pointer readback failed')
        end
        assert(api.epoch()==plan.epoch,'Resource epoch changed after publication')
    end)
    if not ok then
        local rollback=true
        -- A resource reload may destroy the old registry allocation. Never put
        -- stale pointers back into the new epoch, even to attempt rollback.
        if api.epoch()~=plan.epoch then rollback=false
        else
            for i=#attempted,1,-1 do
                local slot=attempted[i]
                local restored,success=pcall(function()
                    assert(api.epoch()==plan.epoch,'Epoch changed during rollback')
                    local now=read(api,slot.address,8)
                    assert(now==slot.after or now==slot.before,'Foreign registry edit prevents rollback')
                    if now~=slot.before then
                        assert(api.write_slot(slot.kind,slot.id,slot.address,slot.before),'Rollback write failed')
                    end
                    assert(read(api,slot.address,8)==slot.before,'Rollback readback failed')
                    return true
                end)
                if not restored or not success then rollback=false end
            end
        end
        state.poisoned=not rollback
        return nil,tostring(reason),state
    end
    state.active=true
    return state
end

function M.check(api,state)
    assert(state.active and not state.poisoned,'Registry publication is not active')
    assert(api.epoch()==state.epoch,'Registry resource epoch changed')
    for _,slot in ipairs(state.slots) do
        assert(read(api,slot.address,8)==slot.after,'Published registry pointer changed')
        assert(read(api,slot.replacement_address,#slot.replacement_record)==slot.replacement_record,
            'Published registry record changed')
    end
    return true
end
-- No automatic unpublish/free: in-flight projectiles may still hold pointers.
-- Native registry cleanup/reset must be handled by a separately verified epoch
-- adapter. Retained allocations remain alive for the process lifetime.
return M
