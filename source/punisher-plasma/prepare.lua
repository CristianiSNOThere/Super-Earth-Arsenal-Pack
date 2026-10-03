return function(api,game,D)
 for _,name in ipairs({'ScorcherARRuntime','ArsenalPreset01Runtime'})do
  local peer=rawget(_G,name)
  if peer and peer.phase~='ready'then
   assert(peer.phase~='gave_up','Installed companion failed: '..name)
   error('Native data unavailable: waiting for '..name)
  end
 end
 local function read(p,n)local s=api.read(p,n);assert(s and #s==n,'Native data unavailable');return s end
 local function ptr(p)return assert(api.pointer(read(p,8),0),'Native pointer unavailable')end
 local function u32(s,o)local a,b,c,d=s:byte(o+1,o+4);return a+b*256+c*65536+d*16777216 end
 local function accept(s,g)
  for _,candidate in ipairs(g.accepted)do if s==candidate then return true end end
  return false
 end
 for _,g in ipairs(D.code)do assert(read(game+g.rva,#g.bytes)==g.bytes,'Unsupported native code')end
 local owner=ptr(game+0x346bf98)
 local source_guards={{address=game+0x346bf98,bytes=read(game+0x346bf98,8)}}
 local stock={};local magazine_address
 for name,g in pairs(D.components)do
  local slot=owner+g.offset;local map=ptr(slot)
  source_guards[#source_guards+1]={address=slot,bytes=read(slot,8)}
  local mapping=read(map,g.count*16);local index
  for i=0,g.count-1 do
   if mapping:sub(i*16+1,i*16+8)==D.owner then
    assert(not index,'Duplicate Punisher source owner');index=u32(mapping,i*16+8)
   end
  end
  assert(index==g.index,'Punisher source mapping changed')
  local address=map+g.count*16+index*g.stride
  local bytes=read(address,g.stride);assert(bytes==g.bytes,'Punisher source changed')
  stock[name]=bytes;source_guards[#source_guards+1]={address=map,bytes=mapping}
  source_guards[#source_guards+1]={address=address,bytes=bytes}
  if name=='magazine'then magazine_address=address end
 end
 local anchors={}
 for _,rva in ipairs({0x346bf98,0x348e2f8,0x348e1f8,0x348ec88})do
  local bytes=read(game+rva,8);assert(api.pointer(bytes,0),'Resource pointer unavailable')
  anchors[#anchors+1]={address=game+rva,bytes=bytes}
 end
 for _,g in ipairs(source_guards)do if #g.bytes==8 then anchors[#anchors+1]=g end end
 local epoch='punisher-'..api.identity(game)..'-'..api.identity(owner)
 api.epoch=function()
  for _,g in ipairs(anchors)do if api.read(g.address,8)~=g.bytes then return 'changed'end end
  return epoch
 end
 local records,protected={},{}
 for name,g in pairs(D.records)do
  local slot=game+g.registry+g.id*8;local address=ptr(slot)
  assert(api.data_access(address,g.size),'Record outside private data')
  local bytes=read(address,g.size)
  if g.kind=='explosion'then
   local normalized=bytes:sub(1,40)..g.serialized:sub(41,48)..bytes:sub(49)
   assert(accept(normalized,g),'Explosion source changed: '..name)
   local array=assert(api.pointer(bytes,40),'Explosion array missing')
   assert(api.data_access(array,#g.array)and read(array,#g.array)==g.array,'Explosion array changed')
  else assert(accept(bytes,g),'Source record changed: '..name)end
  records[name]={address=address,bytes=bytes,slot=slot,id=g.id}
  if g.protect then protected[#protected+1]={name=name,address=address,bytes=bytes}end
 end
 protected[#protected+1]={name='stock_magazine',address=magazine_address,bytes=stock.magazine}
 local c={route='user-selected-loyalist-donor',epoch=epoch,ids={projectile=171,damage=305,explosion=355},
  sources={projectile=records.donor_projectile,damage=records.donor_damage,explosion=records.donor_explosion},
  originals={projectile=records.donor_projectile,damage=records.donor_damage,explosion=records.donor_explosion},
  registry_slots={},protected=protected,shake_bytes=D.records.donor_explosion.array}
 c.tuning=D.tuning
 c.next_tuning=D.next_tuning
 c.normal_flight=D.normal_flight
 c.pellet_durable=D.pellet_durable
 c.pellet_angle_ap=D.pellet_angle_ap
 c.pellet_split=D.pellet_split
 c.normal_two_shot=D.normal_two_shot
 c.normal_projectile=records.normal_projectile
 c.magazine_source={address=magazine_address,bytes=stock.magazine}
 c.magazine_tuning=D.magazine_tuning
 c.blast_burning=D.blast_burning
 c.burning_reference=records.burning_reference
 if c.tuning then
  c.tuning_sources={normal_damage=records.normal_blast_damage,normal_explosion=records.normal_blast,
   alternate_explosion=records.alternate_explosion,equivalent_damage=records.equivalent_damage,
   normal_array=D.records.normal_blast.array,alternate_array=D.records.alternate_explosion.array}
 end
 for kind,g in pairs(c.originals)do c.registry_slots[kind]=g.slot end
 c.snapshot={epoch=epoch,game=game,stock=stock,shotgun_id=171,source_guards=source_guards,code_guards=D.code,mode_index_sync=D.mode_index_sync,fast_watch=D.fast_watch,
  tuning=D.tuning,next_tuning=D.next_tuning,sway_factor=D.sway_factor,normal_single_fast=D.normal_single_fast,normal_two_shot=D.normal_two_shot}
 return c
end
