-- Fresh bounded native metadata only. No writes, native calls or engine handles.
return function(api,base)
 local guards={};local reads,bytes=0,0
 local function u32(s,o)
  assert(o>=0 and o+4<=#s,'Short integer')
  local a,b,c,d=s:byte(o+1,o+4);return a+b*256+c*65536+d*16777216
 end
 local function hex64(s,o)
  assert(o>=0 and o+8<=#s,'Short hash');local out={}
  for i=o+8,o+1,-1 do out[#out+1]=string.format('%02x',s:byte(i))end
  return table.concat(out)
 end
 local function ptr(s,o)return assert(api.pointer(s,o),'Invalid native pointer')end
 local function get(p,n,guard)
  reads=reads+1;bytes=bytes+n
  assert(reads<=4096 and bytes<=524288 and n>0 and n<=4096,'Native read budget')
  local address=api.identity(p);assert(address>=65536 and address<140737488355328,'Invalid read address')
  local s=api.read(p,n);assert(type(s)=='string'and #s==n,'Native read failed')
  if guard then guards[#guards+1]={p=p,s=s}end
  return s
 end
 local function lookup(h,o,key)
  local p=ptr(h,o);local cap,empty,mult=u32(h,o+8),u32(h,o+12),u32(h,o+16)
  assert(cap>=1 and cap<=4096 and cap==2^math.floor(math.log(cap)/math.log(2)+0.5),'Invalid map capacity')
  assert(key~=empty,'Sentinel identity')
  -- Reduce operands first: all arithmetic stays exact, including high uint32 IDs.
  local start=((key%cap)*(mult%cap))%cap
  for probe=0,math.min(cap,64)-1 do
   local row=get(p+8*((start+probe)%cap),8,true)
   local owner,index=u32(row,0),u32(row,4)
   if owner==key then if index==4294967295 then return nil end;return index end
   if owner==empty then return nil end
  end
  error('Map probe bound')
 end
 local root=ptr(get(base+0x346bf98,8,true),0)
 local manager=ptr(get(base+0x3326a38,8,true),0)
 local h=get(manager,0x300,true)
 local count=u32(h,0x268);assert(count<=512,'Parent count bound')
 local refs=count>0 and get(ptr(h,0x290),count*8,true)or ''
 local factory=get(root+0xf1aeb0,24,true)
 local parents,links={},{}
 for slot=0,count-1 do
  local entity=get(ptr(refs,slot*8),24,true)
  local id,owner=u32(entity,8),hex64(entity,0)
  assert(lookup(h,0x278,id)==slot,'Parent map/ref mismatch')
  -- Validate the reference against the current factory, including generation bytes.
  local pi=lookup(factory,0,id);assert(pi and pi<2048,'Parent factory index')
  assert(get(root+0xf32f18+pi*24,24,true)==entity,'Parent factory/ref mismatch')
  local childid=u32(get(ptr(h,0x2a0)+slot*128+0x64,4,true),0)
  if childid~=32767 and childid~=4294967295 then
   links[childid]=(links[childid]or 0)+1
   if owner=='05d8d8c073b9d502'or owner=='a8a91eb54892b6b2'then
    local private=lookup(h,0x2b8,id);local path
    if private then
     assert(private<u32(h,0x2f0),'Private customization bound')
     path=hex64(get(ptr(h,0x2f8)+private*4872+192,8,true),0)
    end
    local ci=lookup(factory,0,childid);assert(ci and ci<2048,'Child factory index')
    local child=get(root+0xf32f18+ci*24,24,true)
    assert(u32(child,8)==childid,'Child factory identity')
    parents[#parents+1]={parent_id=id,parent_owner=owner,parent_active=u32(entity,20)%2==1,
     child_id=childid,child_owner=hex64(child,0),child_active=u32(child,20)%2==1,child_record=child,
     parent_unit_index=u32(entity,12),child_unit_index=u32(child,12),private_path=path}
   end
  end
 end
 local selected={}
 for _,row in ipairs(parents)do
  row.unique_parent=links[row.child_id]==1
  if row.parent_owner=='05d8d8c073b9d502'and row.parent_active then
   assert(row.child_active and row.unique_parent,'Inactive/ambiguous Punisher child')
   assert(row.parent_unit_index~=row.child_unit_index,'Parent equals child unit index')
   assert(row.private_path==row.child_owner,'Customization path/child mismatch')
   selected[#selected+1]=row
  end
 end
 local function recheck()
  for _,g in ipairs(guards)do assert(get(g.p,#g.s)==g.s,'Native ownership changed during callback')end
  return reads,bytes,#guards
 end
 recheck()
 return selected,recheck
end
