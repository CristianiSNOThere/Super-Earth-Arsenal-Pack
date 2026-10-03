-- Wrap the data-only Windows API; image writes limited to seven exact slots.
return function(make_api,game,test_system)
 local ffi=require('ffi');local api=make_api()
 local k=test_system or ffi.load('kernel32');local process=k.GetCurrentProcess()
 local pins={};api.retain=function(v)pins[#pins+1]=v end
 api.pointer_bytes=function(p)local b=ffi.new('uintptr_t[1]',ffi.cast('uintptr_t',p));return ffi.string(b,8)end
 local permitted={}
 for kind,entry in pairs({projectile={0x37c7670,{171,57}},damage={0x37c60c0,{305,311}},explosion={0x37cc920,{355,290,377}}})do
  permitted[kind]={}
  for _,id in ipairs(entry[2])do permitted[kind][id]=game+entry[1]+id*8 end
 end
 api.slot_allowed=function(kind,id,address)
  local g=permitted[kind];return g and g[id] and api.identity(g[id])==api.identity(address)
 end
 api.write_slot=function(kind,id,p,s)
  assert(#s==8 and api.slot_allowed(kind,id,p),'Registry write outside donor scope')
  local info=ffi.new('Plas39QuickShotMemoryInfoV1[1]')
  assert(k.VirtualQuery(p,info,ffi.sizeof(info[0]))==ffi.sizeof(info[0]),'Registry page unavailable')
  assert(info[0].state==0x1000 and info[0].kind==0x1000000,'Registry is not committed image data')
  local old=tonumber(info[0].protection)
  assert((old==2 or old==4)and api.distance(p,info[0].base)+8<=tonumber(info[0].size),'Registry protection changed')
  local previous,ignored=ffi.new('uint32_t[1]'),ffi.new('uint32_t[1]')
  if old==2 then assert(k.VirtualProtect(p,8,4,previous)~=0,'Registry data protection failed')end
  local ok,result=pcall(function()
   local count=ffi.new('size_t[1]');return k.WriteProcessMemory(process,p,s,8,count)~=0 and tonumber(count[0])==8
  end)
  if old==2 then assert(k.VirtualProtect(p,8,previous[0],ignored)~=0,'Registry protection restoration failed')end
  assert(ok,result);return result
 end
 api.write_word=function(p,s)assert(#s==4,'Invalid cache edit');return api.write_protected(p,s)end
 api.state_access=function(p,n)return (n==8 or n==4) and api.data_access(p,n)end
 return api
end
