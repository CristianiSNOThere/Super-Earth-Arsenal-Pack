-- Retained executable payload; all source writes run within native barrier.
local ffi=require('ffi')
ffi.cdef[[
typedef struct {uint32_t *address;uint32_t before,after,size,reserved;} PunisherSourcePatch039;
void GetSystemInfo(void *);
]]
local function word(v)local b=ffi.new('uint32_t[1]',v);return ffi.string(b,4)end
local function u32(s,o)local a,b,c,d=s:byte(o+1,o+4);assert(d,'Short word');return a+b*256+c*65536+d*16777216 end
return function(api,plan,helper,test_system)
 assert(plan.approved and #plan.rows==8 and #plan.busy==3,'Unapproved source plan')
 assert(type(api.retain)=='function' and api.epoch()==plan.epoch,'Source epoch expired')
 local pins={plan,helper};api.retain(pins)
 local function retain(v)pins[#pins+1]=v;return v end
 local all={};for _,g in ipairs(plan.guards)do all[#all+1]=g end
 local function guard(p,s)
  for o=0,#s-1,4096 do all[#all+1]={address=p+o,bytes=s:sub(o+1,o+4096)}end
 end
 local edits={};local seen={}
 for _,r in ipairs(plan.rows)do
  assert(#r.before==#r.after and api.read(r.address,#r.before)==r.before,'Source record changed')
  for o=0,#r.before-1,4 do
   local before,after=u32(r.before,o),u32(r.after,o)
   if before~=after then
    local p=r.address+o;local id=api.identity(p);assert(id%4==0 and not seen[id],'Overlapping patch')
    seen[id]=true;edits[#edits+1]={p=p,before=before,after=after,role=r.role,offset=o}
   end
  end
 end
 assert(#edits>0 and #edits<=1024,'Source patch count bound')
 local patches=retain(ffi.new('PunisherSourcePatch039[?]',#edits))
 for i,e in ipairs(edits)do patches[i-1].address=ffi.cast('uint32_t*',e.p);patches[i-1].before=e.before;patches[i-1].after=e.after;patches[i-1].size=4 end
 guard(ffi.cast('uint8_t*',patches),ffi.string(patches,ffi.sizeof(patches)))
 assert(type(helper.code)=='string' and #helper.code<=8192 and helper['end']<=#helper.code and #helper.unwind<=4096,'Bad source helper')
 for _,g in ipairs(all)do assert(api.read(g.address,#g.bytes)==g.bytes,'Preinstallation guard changed')end
 local k=test_system or ffi.load('kernel32');local nt=test_system or ffi.load('ntdll');local kb=test_system or ffi.load('kernelbase')
 local system=ffi.new('uint8_t[48]');k.GetSystemInfo(system)
 assert(u32(ffi.string(system,48),4)==4096,'Unsupported native page size')
 local block=k.VirtualAlloc(nil,0x4000,0x3000,4);assert(block~=nil,'Source helper allocation failed')
 block=ffi.cast('uint8_t*',block);retain(block)
 ffi.copy(block,helper.code,#helper.code);ffi.copy(block+0x2000,helper.unwind,#helper.unwind)
 local row=word(0)..word(helper['end'])..word(0x2000);ffi.copy(block+0x3000,row,12)
 local old=ffi.new('uint32_t[1]')
 assert(k.VirtualProtect(block,0x4000,0x20,old)~=0,'Source helper RX failed')
 assert(k.FlushInstructionCache(k.GetCurrentProcess(),block,0x4000)~=0,'Source helper flush failed')
 assert(nt.RtlAddFunctionTable(block+0x3000,1,api.identity(block))~=0,'Source helper unwind failed')
 guard(block,helper.code);guard(block+0x2000,helper.unwind);guard(block+0x3000,row)
 local total=0;for _,g in ipairs(all)do assert(#g.bytes>0 and #g.bytes<=4096,'Guard size');total=total+#g.bytes end
 assert(#all<=1024 and total<=1048576,'Source guard budget')
 local guards=retain(ffi.new('PunisherDeltaGuard037[?]',#all))
 for i,g in ipairs(all)do local e=retain(ffi.new('uint8_t[?]',#g.bytes));ffi.copy(e,g.bytes,#g.bytes);guards[i-1].address=g.address;guards[i-1].expected=e;guards[i-1].size=#g.bytes end
 local spec=retain(ffi.new('PunisherDeltaSpec037[1]'));local workspace=retain(ffi.new('uint8_t[9216]'))
 spec[0].workspace=ffi.cast('void*',math.floor((api.identity(workspace)+15)/16)*16)
 local names={next_thread={nt,'NtGetNextThread'},thread_id={k,'GetThreadId'},suspend={k,'SuspendThread'},resume={k,'ResumeThread'},context={k,'GetThreadContext'},capture={nt,'RtlCaptureContext'},query={k,'VirtualQuery'},read={k,'ReadProcessMemory'},protect={k,'VirtualProtect'},flush={k,'FlushInstructionCache'},close={k,'CloseHandle'},last_error={k,'GetLastError'},wait={k,'WaitForSingleObject'},same_object={kb,'CompareObjectHandles'}}
 for name,pair in pairs(names)do spec[0].api[name]=ffi.cast('void*',pair[1][pair[2]])end
 spec[0].process=k.GetCurrentProcess();spec[0].process_id=k.GetCurrentProcessId();spec[0].slot=patches;spec[0].before=#edits
 spec[0].after=ffi.new('uint64_t',0x39334f57)*ffi.new('uint64_t',4294967296)+0x54505055
 spec[0].guards=guards;spec[0].guard_count=#all
 for i,r in ipairs(plan.busy)do spec[0].busy[i-1].begin=r[1];spec[0].busy[i-1]['end']=r[2]end
 local invoke=ffi.cast('int(*)(const PunisherDeltaSpec037*)',block)
 local state={installed=false,poisoned=false,attempts=0}
 function state.install()
  assert(not state.poisoned and not state.installed,'Source transaction already attempted')
  assert(api.epoch()==plan.epoch,'Source epoch changed')
  state.attempts=state.attempts+1;assert(state.attempts<=20,'Source busy retry limit; restart required')
  spec[0].thread_id=k.GetCurrentThreadId()
  local result=test_system and test_system.invoke(spec) or invoke(spec)
  local diag=ffi.cast('uint32_t*',ffi.cast('uint8_t*',spec[0].workspace)+7376)
  state.diagnostic='stage='..tonumber(diag[0])..'; index='..tonumber(diag[10])..'; size='..tonumber(diag[11])..'; paused='..tonumber(diag[4])..'; resume_error='..tonumber(diag[15])
  local function scalar(p)return string.format('0x%08x%08x',tonumber(p[1]),tonumber(p[0]))end
  if tonumber(diag[0])==21 then
   local reasons={'descriptor','duplicate target','page query','page state','page type','page protection','page bounds','read failed','short read','old word mismatch'}
   local e=edits[tonumber(diag[10])+1]
   local address=ffi.cast('uint64_t*',diag+16)
   local page=ffi.cast('uint64_t*',diag+20)
   state.diagnostic=state.diagnostic..'; reason='..(reasons[tonumber(diag[12])] or 'unknown')..
    '; role='..tostring(e and e.role)..'; offset='..tostring(e and e.offset)..
    '; address='..scalar(diag+16)..'; expected='..tonumber(diag[13])..'; observed='..tonumber(diag[14])..
    '; read_bytes='..tonumber(diag[1])..'; error='..tonumber(diag[5])..
    '; page_base='..scalar(diag+20)..'; allocation='..scalar(diag+22)..'; region_size='..scalar(diag+24)..
    '; allocation_protect='..tonumber(diag[26])..'; page_state='..tonumber(diag[27])..
    '; protection='..tonumber(diag[28])..'; type='..tonumber(diag[29])..
    '; query_size='..tonumber(diag[30])..'; query_error='..tonumber(diag[31])
  end
  if tonumber(diag[0])>=25 or result==-27 then
   state.diagnostic=state.diagnostic..'; address='..scalar(diag+16)..'; error='..tonumber(diag[5])..
    '; restore_error='..tonumber(diag[13])..'; restore_index='..tonumber(diag[14])..
    '; current_protection='..tonumber(diag[40])..'; current_type='..tonumber(diag[41])
  end
  if result==2 then return false,'Native source lifecycle busy'end
  if result~=1 then state.poisoned=true;error('Source installation refused: '..result..'; '..state.diagnostic..'; restart required')end
  state.installed=true
  for _,r in ipairs(plan.rows)do if api.read(r.address,#r.after)~=r.after then state.poisoned=true;error('Source readback failed; restart required')end end
  return true
 end
 return state
end
