-- Own every pointer-bearing allocation in the first-stage pellet profile.
-- Does not reserve IDs or publish native registry entries. Caller supplies
-- current validated source records/array and resource epoch, never old pointers.
local ffi=require('ffi')
local M={}
local function u32(s,o)
 local b=ffi.new('uint32_t[1]');ffi.copy(b,s:sub(o+1,o+4),4);return tonumber(b[0])
end
local function change(s,edits)
 local b=ffi.new('uint64_t[?]',math.ceil(#s/8));ffi.copy(b,s,#s)
 local p=ffi.cast('uint8_t*',b)
 for offset,value in pairs(edits)do ffi.cast('uint32_t*',p+offset)[0]=value end
 return b,p,ffi.string(p,#s)
end
local function read(api,p,n)
 local s=api.read(p,n);assert(type(s)=='string'and #s==n,'Source read failed');return s
end
function M.build(api,c)
 assert(type(c.epoch)=='string'and api.epoch()==c.epoch,'Profile epoch changed')
 assert(type(c.ids)=='table','Missing construction IDs')
 local pi,di,ei=c.ids.projectile,c.ids.damage,c.ids.explosion
 for _,v in ipairs({pi,di,ei})do assert(type(v)=='number'and v==math.floor(v),'Invalid construction ID')end
 assert(pi>=1 and pi<=350 and pi~=57,'Unsafe projectile construction ID')
 local loyalist=c.route=='user-selected-loyalist-donor'
 if loyalist then
  assert(pi==171 and di==305 and ei==355,'Loyalist donor policy changed')
 else
  assert(di>=1 and di<=649 and di~=57 and di~=305 and di~=311,'Unsafe damage construction ID')
  assert(ei>=1 and ei<=422 and ei~=290 and ei~=355 and ei~=377,'Unsafe explosion construction ID')
 end
 local guards={}
 for kind,size in pairs({projectile=272,damage=76,explosion=152})do
  local g=assert(c.sources[kind]);assert(#g.bytes==size,'Source size changed')
  assert(read(api,g.address,size)==g.bytes,'Source bytes changed');guards[#guards+1]=g
 end
 local pr,dr,er=c.sources.projectile.bytes,c.sources.damage.bytes,c.sources.explosion.bytes
 if loyalist then
  assert(u32(pr,0)==171 and u32(pr,28)==1 and u32(pr,60)==56 and u32(pr,144)==355,'Unexpected Loyalist projectile')
 else
  assert(u32(pr,0)==57 and u32(pr,28)==1 and u32(pr,60)==57 and u32(pr,144)==290,'Unexpected projectile')
 end
 assert(u32(dr,0)==305 and u32(dr,4)==25 and u32(dr,8)==25,'Unexpected small blast damage')
 assert(u32(er,0)==355 and u32(er,4)==305,'Unexpected small explosion')
 local count=u32(er,48);assert(count>0 and count<=512 and u32(er,52)==0,'Array count changed')
 local array=assert(c.shake_bytes);assert(#array==count*8,'Array size changed')
 local source_pointer=api.pointer(er,40)
 assert(read(api,source_pointer,#array)==array,'Shake assets changed')
 local shake=ffi.new('uint64_t[?]',count);ffi.copy(shake,array,#array)
 local db,dp,dbytes=change(dr,{[0]=di,[4]=50,[8]=18})
 if c.pellet_durable then
  assert(c.pellet_durable==25,'Unexpected pellet durable tuning')
  ffi.cast('uint32_t*',dp+8)[0]=25;dbytes=ffi.string(dp,76)
 end
 if c.next_tuning then
  ffi.cast('uint32_t*',dp+32)[0]=25;ffi.cast('uint32_t*',dp+36)[0]=25
  dbytes=ffi.string(dp,76)
 end
 if c.pellet_split then
  assert(c.pellet_split=='direct25-9-blast25-9','Unexpected pellet split')
  ffi.cast('uint32_t*',dp+4)[0]=25;ffi.cast('uint32_t*',dp+8)[0]=9
  dbytes=ffi.string(dp,76)
 end
 if c.pellet_angle_ap then
  assert(c.pellet_angle_ap==3 and c.pellet_split=='direct25-9-blast25-9','Unexpected pellet angle penetration')
  assert(u32(dr,12)==3 and u32(dr,16)==0 and u32(dr,20)==0 and u32(dr,24)==0,'Pellet source angle penetration changed')
  -- Owned damage305 supplies impact and blast; preserve strength3 at every angle.
  for offset=12,24,4 do ffi.cast('uint32_t*',dp+offset)[0]=3 end
  dbytes=ffi.string(dp,76)
 end
 local eb,ep=change(er,{[0]=ei,[4]=di})
 ffi.copy(ep+40,api.pointer_bytes(ffi.cast('uint8_t*',shake)),8)
 local ebytes=ffi.string(ep,152)
 if c.tuning then
  ffi.cast('float*',ep+16)[0]=0.5
  ffi.cast('float*',ep+20)[0]=0.5
  ffi.cast('float*',ep+24)[0]=0.5
  ebytes=ffi.string(ep,152)
 end
 -- Preserve Loyalist particle hashes, speed, gravity and all other flight
 -- fields. Shared damage56 belongs to Scorcher too; select existing zero
 -- direct-impact damage57 so each pellet deals only the requested50/18 blast.
 local pb,pp,pbytes=change(pr,{[0]=pi,[28]=9,[60]=57,[144]=ei})
 if c.pellet_split then
  -- The same owned25/9 physical DamageInfo supplies direct hit and blast;
  -- protected normal direct-impact57 remains zero. Both halves retain AP
  -- and ForceStrength/Impulse; the direct half only applies on actual hits.
  ffi.cast('uint32_t*',pp+60)[0]=di;pbytes=ffi.string(pp,272)
 end
 if c.visual_particle_bytes then
  assert(loyalist and c.visual_particle_bytes==string.char(0x76,0xdd,0xce,0x10,0x4c,0xec,0xe4,0x07),'Unexpected private pellet effect')
  ffi.copy(pp+72,c.visual_particle_bytes,8)
  pbytes=ffi.string(pp,272)
 end
 for _,g in ipairs(guards)do assert(read(api,g.address,#g.bytes)==g.bytes,'Source changed during construction')end
 assert(read(api,source_pointer,#array)==array and api.epoch()==c.epoch,'Array/epoch changed during construction')
 local result={epoch=c.epoch,records={damage=dbytes,explosion=ebytes,projectile=pbytes},
  addresses={damage=dp,explosion=ep,projectile=pp},pins={db,eb,pb,shake},
  shake_address=ffi.cast('uint8_t*',shake),shake_bytes=array,ids=c.ids,
  registry_ownership_verified=false,published=false,route=c.route,
  loyalist_behavior_preserved=not loyalist}
 if c.tuning then
  local t=assert(c.tuning_sources,'Normal tuning sources missing')
  if c.normal_flight then
   local g=assert(c.normal_projectile,'Normal flight source missing')
   assert(read(api,g.address,272)==g.bytes and u32(g.bytes,0)==57,'Normal flight source changed')
   local fb,fp=change(g.bytes,{})
   ffi.cast('float*',fp+40)[0]=1.2
   ffi.cast('float*',fp+44)[0]=1
   result.records.normal_projectile=ffi.string(fp,272);result.addresses.normal_projectile=fp
   result.pins[#result.pins+1]=fb
  end
  local nd,ne,ae=t.normal_damage,t.normal_explosion,t.alternate_explosion
  for _,g in ipairs({nd,ne,ae,t.equivalent_damage})do
   assert(read(api,g.address,#g.bytes)==g.bytes,'Normal tuning source changed')
  end
  assert(u32(nd.bytes,0)==311 and u32(ne.bytes,0)==290 and u32(ne.bytes,4)==311,
   'Normal tuning chain changed')
  assert(u32(ae.bytes,0)==377 and u32(ae.bytes,4)==311,'Alternate chain changed')
  assert(u32(t.equivalent_damage.bytes,0)==315 and nd.bytes:sub(5)==t.equivalent_damage.bytes:sub(5),
   'Stock315 no longer equivalent to stock311')
  local nb,np,nbytes=change(nd.bytes,{[4]=350,[32]=25})
  if c.normal_two_shot then
   ffi.cast('uint32_t*',np+4)[0]=350;ffi.cast('uint32_t*',np+8)[0]=225;nbytes=ffi.string(np,76)
  end
  if c.next_tuning then ffi.cast('uint32_t*',np+28)[0]=30;nbytes=ffi.string(np,76)end
  if c.blast_burning then
   local fire=assert(c.burning_reference,'Burning reference missing')
   assert(read(api,fire.address,76)==fire.bytes and u32(fire.bytes,44)==5,'Burning reference changed')
   assert(u32(nd.bytes,44)==0 and nd.bytes:sub(45)==string.rep('\0',32),'Existing normal status effects')
   -- Copy stock blast's standard Fire type and buildup strength, not its
   -- damage/element or any global burning template. Native blast falloff
   -- scales this strength throughout the approved outer damage radius.
   ffi.copy(np+44,fire.bytes:sub(45,52),8);nbytes=ffi.string(np,76)
  end
  result.records.normal_damage=nbytes;result.addresses.normal_damage=np
  result.pins[#result.pins+1]=nb;result.shakes={}
  for _,item in ipairs({{key='normal_explosion',source=ne,array=t.normal_array},
                       {key='alternate_explosion',source=ae,array=t.alternate_array}})do
   local g=item.source;local count=u32(g.bytes,48)
   assert(count>0 and count<=512 and #item.array==count*8,'Normal shake array size changed')
   assert(read(api,api.pointer(g.bytes,40),#item.array)==item.array,'Normal shake assets changed')
   local sb=ffi.new('uint64_t[?]',count);ffi.copy(sb,item.array,#item.array)
   local eb,ep=change(g.bytes,item.key=='alternate_explosion' and {[4]=315} or {})
   ffi.copy(ep+40,api.pointer_bytes(ffi.cast('uint8_t*',sb)),8)
   if item.key=='normal_explosion' then
    ffi.cast('float*',ep+16)[0]=3.5;ffi.cast('float*',ep+20)[0]=6.5;ffi.cast('float*',ep+24)[0]=8
   end
   result.records[item.key]=ffi.string(ep,152);result.addresses[item.key]=ep
   result.pins[#result.pins+1]=eb;result.pins[#result.pins+1]=sb
   result.shakes[#result.shakes+1]={address=ffi.cast('uint8_t*',sb),bytes=item.array}
  end
 end
 -- Retain as a single object so the explosion and its child array cannot
 -- outlive one another. Publication must additionally enforce approved slots.
 api.retain(result)
 return result
end
return M
