-- Donor publication + per-instance mode/spread orchestration.
-- Exact-build Windows/source/epoch adapters are separate dependencies.
local M={}
local sizes={damage=76,explosion=152,projectile=272}
local ids={damage=305,explosion=355,projectile=171}
local function read(api,p,n)
 local s=api.read(p,n);assert(type(s)=='string'and #s==n,'Donor data unreadable');return s
end
local function unchanged(api,state)
 assert(api.epoch()==state.epoch,'Donor resource epoch changed')
 for _,g in ipairs(state.protected)do assert(read(api,g.address,#g.bytes)==g.bytes,'Protected normal/Scorcher/source record changed')end
 assert(read(api,state.owned.shake_address,#state.owned.shake_bytes)==state.owned.shake_bytes,'Owned shake assets changed')
 for _,g in ipairs(state.owned.shakes or {})do assert(read(api,g.address,#g.bytes)==g.bytes,'Owned normal shake assets changed')end
 if state.config.tuning then
  local g=state.config.tuning_sources.equivalent_damage
  assert(read(api,g.slot,8)==api.pointer_bytes(g.address),'Equivalent damage315 registry slot changed')
 end
end
function M.start(api,c,modules)
 assert(c.route=='user-selected-loyalist-donor','Explicit donor policy missing')
 assert(type(c.protected)=='table','Protected records missing')
 local required={normal_projectile=true,normal_blast=true,normal_blast_damage=true,
  direct_impact=true,scorcher_projectile=true,scorcher_direct=true,
  scorcher_explosion=true,scorcher_blast=true,stock_magazine=true}
 if c.tuning then required.equivalent_damage=true end
 if c.blast_burning then required.burning_reference=true end
 for _,g in ipairs(c.protected)do
  assert(required[g.name]==true,'Unknown/duplicate protected guard')
  assert(type(g.bytes)=='string'and #g.bytes>0,'Empty protected guard')
  assert(read(api,g.address,#g.bytes)==g.bytes,'Protected source changed')
  required[g.name]=false
 end
 for name,pending in pairs(required)do assert(not pending,'Missing protected '..name)end
 assert(api.epoch()==c.epoch,'Donor epoch changed')
 local owned=modules.owned.build(api,c)
 local plan={epoch=c.epoch,approved=true,slots={}}
 for _,kind in ipairs({'damage','explosion','projectile'})do
  local original=assert(c.originals[kind]);assert(original.id==ids[kind],'Wrong donor original')
  assert(#original.bytes==sizes[kind],'Wrong donor record size')
  assert(read(api,original.address,sizes[kind])==original.bytes,'Donor source changed')
  assert(api.identity(original.slot)==api.identity(c.registry_slots[kind]),'Donor slot changed')
  plan.slots[#plan.slots+1]={kind=kind,id=ids[kind],address=original.slot,
    before=api.pointer_bytes(original.address),after=api.pointer_bytes(owned.addresses[kind]),
    original_address=original.address,original_record=original.bytes,
    replacement_address=owned.addresses[kind],replacement_record=owned.records[kind],pin=owned}
 end
 if c.tuning then
  local t=c.tuning_sources
  local function slot(kind,id,g,key)
   return {kind=kind,id=id,address=g.slot,before=api.pointer_bytes(g.address),
    after=api.pointer_bytes(owned.addresses[key]),original_address=g.address,original_record=g.bytes,
    replacement_address=owned.addresses[key],replacement_record=owned.records[key],pin=owned}
  end
  -- Preserve the alternate consumer before publishing the stronger normal311.
  local donor=plan.slots
  plan.slots={slot('explosion',377,t.alternate_explosion,'alternate_explosion'),
   slot('damage',311,t.normal_damage,'normal_damage'),donor[1],
   slot('explosion',290,t.normal_explosion,'normal_explosion'),donor[2],donor[3]}
  if c.normal_flight then
   plan.slots[#plan.slots+1]=slot('projectile',57,c.normal_projectile,'normal_projectile')
  end
 end
 local state={epoch=c.epoch,owned=owned,protected=c.protected,config=c,active=false,poisoned=false}
 unchanged(api,state)
 local registry,reason,failure=modules.registry.publish(api,plan)
 state.registry=registry or failure
 if not registry then state.poisoned=failure and failure.poisoned or false;return nil,reason,state end
 owned.published=true;state.active=true
 if c.magazine_tuning then
  local magazine,why,poisoned=assert(modules.magazine,'Magazine module missing').apply(api,c,function()return modules.registry.check(api,state.registry)end)
  if not magazine then state.active=false;state.poisoned=poisoned;return nil,why,state end
  state.magazine=magazine
 end
 return state
end
function M.tick(api,state,modules)
 assert(state.active and not state.poisoned,'Donor runtime inactive')
 local ok,result=pcall(function()
  unchanged(api,state);modules.registry.check(api,state.registry)
  local config=state.config.snapshot
  assert(config.shotgun_id==171 and config.epoch==state.epoch,'Snapshot donor policy changed')
  local snapshot=modules.snapshot.collect(api,modules.modes,config)
  local old=api.validate_snapshot
  api.validate_snapshot=function()
   local valid=pcall(unchanged,api,state)
   return valid and snapshot.validate() and modules.registry.check(api,state.registry)
  end
  local outcome={pcall(function()
   return modules.cache.commit(api,modules.cache.plan(api,state.epoch,snapshot.groups,snapshot.extra))
  end)}
  api.validate_snapshot=old
  assert(outcome[1],outcome[2])
  if not outcome[2]then
   if outcome[4]and outcome[4].poisoned then state.poisoned=true end
   error(outcome[3])
  end
  if config.fast_watch then state.watch=modules.snapshot.watch(api,config,snapshot)end
  return {instances=#snapshot.instances,writes=outcome[3],mode_observations=snapshot.instances}
 end)
 if not ok then state.active=false;state.error=tostring(result);return nil,state.error end
 return result
end
-- No automatic free/unpublish; projectiles can outlive weapon selection.
return M
