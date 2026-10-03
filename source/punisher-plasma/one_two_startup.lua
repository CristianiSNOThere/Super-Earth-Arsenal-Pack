-- Source installation before normal native equipment creation. No manual
-- native factory calls, inventory writes or per-frame mode/cache mutation.
return function(make_api,bridge,prepare,D,modules,helper)
 assert(not rawget(_G,'PunisherPlasmaFirstTest'),'Another Punisher runtime is active; restart required')
 local state={version=D.version,status='Preparing',source_installed=false,children=0,native_20_60_observed=false,gameplay_verified=false,observations={},retained={}}
 _G.PunisherPlasmaFirstTest=state
 local previous=update;local live,deadline,last,next_check
 local function log()
  print('[Punisher One-Two] '..state.status)
  pcall(function()
   local loader=rawget(_G,'CowboyBingusModLoader');local f=loader and loader.open_log and loader.open_log('PunisherOneTwoTest.log')
   if f then
    f:write('version='..state.version..'\nstatus='..state.status..'\nsource_installed='..tostring(state.source_installed)..'\nchildren='..state.children..'\nnative_20_60_observed='..tostring(state.native_20_60_observed)..'\ngameplay_verified=false\nnormal=350/225 blast;60RPM;17 capacity;one spare17 magazine;refill one;LEFT NORMAL/SHOTGUN\npellets=9;25/9 direct+25/9 blast;100RPM;100/90MRAD;AP3 all angles;20 capacity;60 loose spares\nOneTwo child sacrificed; grip replaced; original asset bytes retained\n'..table.concat(state.observations,'\n')..'\n');f:close()
   end
  end)
 end
 local worker=coroutine.create(function()
  local basic=make_api();basic.checkpoint=function()if os.clock()>=deadline then coroutine.yield()end end
  local exe=assert(basic.module(nil),'Engine unavailable');local module=assert(basic.module('game.dll'),'Game unavailable')
  assert(basic.module_hash(exe)==D.exe_hash and basic.module_hash(module)==D.game_hash,'Unsupported game build')
  local game=basic.byte_pointer(module);local api=bridge(make_api,game);local c
  -- Root api.retain's entire allocation graph in the global state BEFORE any
  -- publication/helper allocation. An errored/dead worker must not be the
  -- last owner of native projectile/guard/unwind storage after a refusal.
  state.retained[#state.retained+1]={api=api,basic=basic,D=D,modules=modules,helper=helper}
  for attempt=1,240 do
   local ok,result=pcall(prepare,api,game,D)
   if ok then c=result;break end
   local why=tostring(result);assert(why:find('unavailable',1,true) and attempt<240,why)
   local until_time=api.now()+1000;repeat coroutine.yield() until api.now()>=until_time
  end
  assert(c,'Source preparation failed')
  local profiles=modules.profile(D.source_rows,modules.modes,c.snapshot.stock,D.child_reload_template)
  local plan=modules.plan(api,game,c,D,profiles) -- proves target absence first
  c.magazine_tuning=false
  local run,why=modules.runtime.start(api,c,modules);assert(run,why)
  state.retained[#state.retained+1]={run=run,c=c,plan=plan}
  local function guard(p,s)for o=0,#s-1,4096 do plan.guards[#plan.guards+1]={address=p+o,bytes=s:sub(o+1,o+4096)}end end
  for _,g in ipairs(run.registry.slots)do guard(g.address,g.after);guard(g.replacement_address,g.replacement_record)end
  guard(run.owned.shake_address,run.owned.shake_bytes)
  for _,g in ipairs(run.owned.shakes or {})do guard(g.address,g.bytes)end
  local registration=modules.registration(api,plan,helper)
  api.retain({run,plan,registration,profiles,D,modules,helper})
  for attempt=1,20 do
   local ok,message=registration.install()
   if ok then break end
   state.status='Waiting: '..tostring(message);log()
   assert(attempt<20,'Source installation busy; restart required')
   local when=api.now()+100;repeat coroutine.yield()until api.now()>=when
  end
  assert(registration.installed,'Source transaction incomplete')
  local rounds
  for _,r in ipairs(plan.rows)do
   if r.role=='child_rounds' then rounds=r.after end
   if r.role=='parent_magazine' then
    for _,g in ipairs(c.protected)do if g.name=='stock_magazine' then g.bytes=r.after end end
   end
  end
  assert(rounds,'Missing child Rounds profile')
  state.source_installed=true
  return {api=api,game=game,run=run,c=c,plan=plan,rounds=rounds}
 end)
 local function tick()
  if state.stopped then return end
  if not live then
   deadline=os.clock()+0.0007
   local ok,result=coroutine.resume(worker)
   if not ok then state.status='Stopped: '..tostring(result);state.stopped=true
   elseif coroutine.status(worker)=='dead' then live=result;state.status='Ready: select Punisher Plasma; normal attachment initialization enabled' end
  elseif not next_check or live.api.now()>=next_check then
   next_check=live.api.now()+250
   local ok,rows=pcall(function()
    assert(live.api.epoch()==live.plan.epoch,'Source epoch expired')
    assert(modules.registry.check(live.api,live.run.registry),'Owned tuning expired')
    for _,r in ipairs(live.plan.rows)do assert(live.api.read(r.address,#r.after)==r.after,'Source profile changed: '..r.role)end
    for _,g in ipairs(live.c.protected)do assert(live.api.read(g.address,#g.bytes)==g.bytes,'Protected record changed')end
    if not live.api.pointer(live.api.read(live.game+0x3326a38,8),0) or
       not live.api.pointer(live.api.read(live.game+0x3326cf0,8),0)then return {} end
    return modules.observe(live.api,live.game,modules.join,live.rounds)
   end)
   if not ok then
    state.status='Observation stopped: '..tostring(rows)..'; restart required';state.stopped=true
   else
    state.children=#rows
    local texts={}
    for _,r in ipairs(rows)do
     texts[#texts+1]='parent='..r.parent_id..'; child='..r.child_id..'; loaded='..r.loaded..'; spares='..r.spares
     if r.loaded==20 and r.spares==60 then state.native_20_60_observed=true end
    end
    local text=table.concat(texts,' | ')
    if text~=state.last_ammo then
     state.last_ammo=text
     -- Bounded recent history; retain later low-reserve/refill tests as well.
     if #state.observations>=100 then table.remove(state.observations,1)end
     state.observations[#state.observations+1]='tick_ms='..live.api.now()..'; '..text
    end
    state.status=#rows>0 and 'Automatic child observed; native ammo '..text or 'Ready: awaiting Punisher native child'
   end
  end
  local signature=state.status..':'..state.children..':'..#state.observations
  if signature~=last then last=signature;log()end
 end
 local function pack(...)return {n=select('#',...),...}end
 update=function(...)
  local ok,why=pcall(tick)
  if not ok then state.status='Stopped: '..tostring(why)..'; restart required';state.stopped=true;log()end
  local values=previous and pack(previous(...))
  if values then return unpack(values,1,values.n)end
 end
 log();return state
end
