-- Discover current source storage and prove target entities absent BEFORE
-- installing profiles. No retained live cache pointers or native game calls.
return function(api,game,c,D,profiles)
 local guards,rows={},{}
 local function get(p,n)local s=api.read(p,n);assert(type(s)=='string' and #s==n,'Source data unavailable');return s end
 local function u32(s,o)local a,b,c,d=s:byte(o+1,o+4);assert(d,'Short plan word');return a+b*256+c*65536+d*16777216 end
 local function ptr(p)return assert(api.pointer(get(p,8),0),'Source pointer unavailable')end
 local function guard(p,s)for o=0,#s-1,4096 do guards[#guards+1]={address=p+o,bytes=s:sub(o+1,o+4096)}end end
 local root=ptr(game+0x346bf98);guard(game+0x346bf98,get(game+0x346bf98,8))
 -- Include the same resource-owner anchors used by prepare's epoch closure
 -- in the NATIVE paused guard set, not only the preceding Lua check.
 for _,rva in ipairs({0x348e2f8,0x348e1f8,0x348ec88})do
  local s=get(game+rva,8);assert(api.pointer(s,0),'Resource owner unavailable');guard(game+rva,s)
 end
 local countbytes=get(root+0xf12470,4);local count=u32(countbytes,0);assert(count>0 and count<=128,'Source ledger count')
 local buffers=get(root+0xf11c70,count*8);local sizes=get(root+0xf12070,count*4)
 guard(root+0xf12470,countbytes);guard(root+0xf11c70,buffers);guard(root+0xf12070,sizes);guard(root+0xf12270,get(root+0xf12270,count*4))
 local emptybytes=get(game+0x348456c,4);guard(game+0x348456c,emptybytes);local empty=u32(emptybytes,0)
 for offset=0,2047,170 do
  local n=math.min(170,2048-offset);local bytes=get(root+0xf32f18+offset*24,n*24)
  guard(root+0xf32f18+offset*24,bytes)
  for i=0,n-1 do
   local row=bytes:sub(i*24+1,i*24+24)
   if u32(row,8)~=empty then
    local owner=row:sub(1,8)
    assert(owner~=D.owner and owner~=D.child_owner and owner~=D.one_two_owner,
     'Target weapon already exists; restart with another primary equipped')
   end
  end
 end
 for _,r in ipairs(profiles)do
  local slot=root+r.offset;local map=ptr(slot);guard(slot,get(slot,8))
  local mapping=get(map,r.count*16);local found,owners=0,0
  for i=0,r.count-1 do
   local owner=mapping:sub(i*16+1,i*16+8);local index=u32(mapping,i*16+8)
   if owner==r.owner then assert(index==r.index,'Source index changed');found=found+1 end
   if index==r.index and owner~=string.rep('\0',8) then owners=owners+1 end
  end
  assert(found==1 and owners==1,'Shared/ambiguous source target')
  local p=map+r.count*16+r.index*r.stride;assert(api.identity(p)%4==0,'Source alignment')
  local id=api.identity(p);local owned=false
  for i=0,count-1 do
   local b=api.pointer(buffers,i*8);local size=u32(sizes,i*4)
   assert(b and size>0 and size<=67108864,'Invalid source ledger buffer')
   local first=api.identity(b)
   if id>=first and id+#r.before<=first+size then owned=true end
  end
  assert(owned,'Source target outside loader ledger')
  assert(get(p,#r.before)==r.before,'Source target changed: '..r.role)
  guard(map,mapping);guard(p,r.before)
  rows[#rows+1]={role=r.role,address=p,before=r.before,after=r.after}
 end
 for _,g in ipairs(D.code)do assert(get(game+g.rva,#g.bytes)==g.bytes,'Source build changed');guard(game+g.rva,g.bytes)end
 for _,g in ipairs(D.attachment_code)do assert(get(game+g.rva,#g.bytes)==g.bytes,'Attachment build changed');guard(game+g.rva,g.bytes)end
 for _,g in ipairs(c.protected)do guard(g.address,g.bytes)end
 local epoch_guards={}
 for _,g in ipairs(guards)do if #g.bytes==8 then epoch_guards[#epoch_guards+1]=g end end
 local old_epoch=api.epoch;local epoch=c.epoch
 api.epoch=function()
  if old_epoch()~=epoch then return 'changed'end
  for _,g in ipairs(epoch_guards)do if api.read(g.address,8)~=g.bytes then return 'changed'end end
  return epoch
 end
 local base=api.identity(game)
 return {approved=true,rows=rows,guards=guards,epoch=epoch,
  busy={{base+0x4f0000,base+0x7f0000},{base+0xab0000,base+0xaf0000},{base+0xfd0000,base+0xfe0000}}}
end
