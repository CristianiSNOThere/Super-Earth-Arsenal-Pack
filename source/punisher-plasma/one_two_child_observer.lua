-- Read-only normal attachment -> independent Rounds state. Never preloads.
return function(api,game,join,expected_rounds)
 local parents,recheck=join(api,game);local out={}
 if #parents==0 then recheck();return out end
 local guards={}
 local function get(p,n)local s=api.read(p,n);assert(type(s)=='string' and #s==n,'Child read failed');guards[#guards+1]={p=p,s=s};return s end
 local function ptr(s,o)return assert(api.pointer(s,o),'Child pointer unavailable')end
 local function u32(s,o)local a,b,c,d=s:byte(o+1,o+4);assert(d,'Short child word');return a+b*256+c*65536+d*16777216 end
 local function lookup(h,o,key)
  local cap,empty,mult=u32(h,o+8),u32(h,o+12),u32(h,o+16);assert(cap>=1 and cap<=4096,'Child map capacity')
  local power=1;while power<cap do power=power*2 end;assert(power==cap and key~=empty,'Child map/sentinel')
  local p=ptr(h,o);local start=((key%cap)*(mult%cap))%cap
  for i=0,math.min(cap,128)-1 do
   local r=get(p+((start+i)%cap)*8,8);local owner,index=u32(r,0),u32(r,4)
   if owner==key then return index~=4294967295 and index or nil end
   if owner==empty then return nil end
  end
  error('Child map probe bound')
 end
 local root=ptr(get(game+0x346bf98,8),0)
 local manager=ptr(get(game+0x3326cf0,8),0);local h=get(manager,0xb0)
 for _,p in ipairs(parents)do
  assert(p.child_owner=='02cd7321cd8445f5','Wrong automatic child resource')
  local index=lookup(h,0x28,p.child_id)
  if index then
   assert(index<u32(h,0x14) and u32(h,0x14)<=4096,'Child Rounds index')
   local ref=get(ptr(get(ptr(h,0x40)+index*8,8),0),24)
   assert(type(p.child_record)=='string' and #p.child_record==24 and ref==p.child_record,'Child Rounds factory generation mismatch')
   local config;local private=lookup(h,0x68,p.child_id)
   if private then
    assert(private<u32(h,0xa0) and u32(h,0xa0)<=4096,'Private Rounds index')
    config=get(ptr(h,0xa8)+private*136,136)
   else
    local source=ptr(get(root+0xf12820,8),0);config=get(source+50*16+13*136,136)
   end
   assert(config==expected_rounds,'Effective child Rounds changed')
   local selection=get(ptr(h,0x58)+index*20,20);local active=get(ptr(h,0x50)+index*24,24)
   local loaded,other,spares=u32(active,4),u32(active,8),u32(selection,0)
   assert(loaded<=20 and other==0 and spares<=60,'Child ammo outside target limits')
   assert(u32(selection,4)==u32(active,12) and u32(active,12)==0,'Child ammo mode mismatch')
   -- Selection fields8/12 are saved/reset state; do not require them to equal
   -- continuously consumed runtime counts. Native77bc63 sets flag1 when
   -- config104 is0: the runtime flag is not an extra chambered round.
   assert(selection:byte(17)<=1 and active:byte(21)<=1,'Invalid chamber readiness flag')
   out[#out+1]={parent_id=p.parent_id,child_id=p.child_id,loaded=loaded,spares=spares,
    saved_loaded=u32(selection,8),saved_other=u32(selection,12),ready_flag=active:byte(21)}
  end
 end
 recheck();for _,g in ipairs(guards)do assert(api.read(g.p,#g.s)==g.s,'Child changed during observation')end
 return out
end
