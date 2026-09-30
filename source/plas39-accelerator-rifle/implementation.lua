local make_api = (function()
return function()
    local ffi = require('ffi')
    assert(ffi.abi('64bit'), 'Requires Windows x64 LuaJIT')
    ffi.cdef [[
        void *GetModuleHandleA(const char *);
        void *GetCurrentProcess(void);
        uint32_t GetCurrentProcessId(void);
        uint64_t GetTickCount64(void);
        uint32_t GetModuleFileNameW(void *, uint16_t *, uint32_t);
        int ReadProcessMemory(void *, const void *, void *, size_t, size_t *);
        int WriteProcessMemory(void *, void *, const void *, size_t, size_t *);
        size_t VirtualQuery(const void *, void *, size_t);
        int VirtualProtect(void *, size_t, uint32_t, uint32_t *);
        void *CreateFileW(const uint16_t *, uint32_t, uint32_t, void *, uint32_t, uint32_t, void *);
        int ReadFile(void *, void *, uint32_t, uint32_t *, void *);
        int CloseHandle(void *);
        int32_t BCryptOpenAlgorithmProvider(void **, const uint16_t *, const uint16_t *, uint32_t);
        int32_t BCryptCloseAlgorithmProvider(void *, uint32_t);
        int32_t BCryptCreateHash(void *, void **, void *, uint32_t, const void *, uint32_t, uint32_t);
        int32_t BCryptHashData(void *, const void *, uint32_t, uint32_t);
        int32_t BCryptFinishHash(void *, void *, uint32_t, uint32_t);
        int32_t BCryptDestroyHash(void *);
        typedef struct {
            void *base; void *allocation; uint32_t initial_protection;
            uint16_t partition; uint16_t reserved; size_t size;
            uint32_t state; uint32_t protection; uint32_t kind;
        } Plas39QuickShotMemoryInfoV1;
    ]]
    local k, b = ffi.load('kernel32'), ffi.load('bcrypt')
    local self = k.GetCurrentProcess()
    local api = {}
    function api.byte_pointer(value) return ffi.cast('uint8_t *',value) end
    -- Canonical user addresses are below 2^47 and exactly representable as doubles.
    -- The game may hide every cdata value behind the same tostring result.
    function api.identity(p) return tonumber(ffi.cast('uintptr_t',p)) end
    function api.now() return tonumber(k.GetTickCount64()) end
    function api.module(name) return k.GetModuleHandleA(name) end
    function api.distance(a,c) return tonumber(ffi.cast('intptr_t',a)-ffi.cast('intptr_t',c)) end
    function api.pointer(s,o)
        if not s or o<0 or o+8>#s then return nil end
        local v=ffi.new('uintptr_t[1]'); ffi.copy(v,s:sub(o+1,o+8),8)
        if v[0] < 65536 or v[0] >= 0x800000000000 then return nil end
        return ffi.cast('uint8_t *',v[0])
    end
    function api.read(p,n)
        local buf,got=ffi.new('uint8_t[?]',n),ffi.new('size_t[1]')
        if k.ReadProcessMemory(self,p,buf,n,got)==0 or tonumber(got[0])~=n then return nil end
        return ffi.string(buf,n)
    end
    function api.writable(p,n)
        local info=ffi.new('Plas39QuickShotMemoryInfoV1[1]')
        local cursor=ffi.cast('uint8_t *',p)
        while n>0 do
            if k.VirtualQuery(cursor,ffi.cast('void *',info),ffi.sizeof(info[0]))~=ffi.sizeof(info[0]) then return false end
            if info[0].state~=0x1000 or info[0].kind~=0x20000 or info[0].protection~=4 then return false end
            local remaining=tonumber(info[0].size)-api.distance(cursor,info[0].base)
            if remaining<=0 then return false end
            local take=math.min(n,remaining); cursor=cursor+take; n=n-take
        end
        return true
    end
    function api.write(p,s)
        if not api.writable(p,#s) then return false end
        local count=ffi.new('size_t[1]')
        return k.WriteProcessMemory(self,p,s,#s,count)~=0 and tonumber(count[0])==#s
    end
    function api.data_access(p,n)
        local info=ffi.new('Plas39QuickShotMemoryInfoV1[1]')
        local cursor=ffi.cast('uint8_t *',p)
        while n>0 do
            if k.VirtualQuery(cursor,ffi.cast('void *',info),ffi.sizeof(info[0]))~=ffi.sizeof(info[0]) then return false end
            if info[0].state~=0x1000 or info[0].kind~=0x20000 or (info[0].protection~=2 and info[0].protection~=4) then return false end
            local remaining=tonumber(info[0].size)-api.distance(cursor,info[0].base)
            if remaining<=0 then return false end
            local take=math.min(n,remaining);cursor=cursor+take;n=n-take
        end
        return true
    end
    function api.write_protected(p,s)
        assert(#s==4 or #s==8,'Only validated 4-byte or 8-byte data edits may be written')
        local info=ffi.new('Plas39QuickShotMemoryInfoV1[1]')
        if k.VirtualQuery(p,ffi.cast('void *',info),ffi.sizeof(info[0]))~=ffi.sizeof(info[0]) then return false end
        if not api.data_access(p,#s) or api.distance(p,info[0].base)+#s>tonumber(info[0].size) then return false end
        local old=tonumber(info[0].protection)
        if old==4 then return api.write(p,s) end
        if old~=2 then return false end
        local previous,ignored=ffi.new('uint32_t[1]'),ffi.new('uint32_t[1]')
        if k.VirtualProtect(p,#s,4,previous)==0 then return false end
        local ok,result=pcall(api.write,p,s)
        local restored=k.VirtualProtect(p,#s,previous[0],ignored)~=0
        assert(restored,'Attachment page protection restoration failed')
        assert(ok,result)
        return result
    end
    local function digest(feed)
        local algorithm,hash=ffi.new('void *[1]'),ffi.new('void *[1]')
        local ok,result=pcall(function()
            local name=ffi.new('uint16_t[7]',{83,72,65,50,53,54,0})
            assert(b.BCryptOpenAlgorithmProvider(algorithm,name,nil,0)==0,'SHA256 provider failed')
            assert(b.BCryptCreateHash(algorithm[0],hash,nil,0,nil,0,0)==0,'SHA256 initialization failed')
            feed(function(p,n) assert(b.BCryptHashData(hash[0],p,n,0)==0,'SHA256 input failed') end)
            local out=ffi.new('uint8_t[32]')
            assert(b.BCryptFinishHash(hash[0],out,32,0)==0,'SHA256 finalization failed')
            local hex={}; for i=0,31 do hex[#hex+1]=string.format('%02X',out[i]) end
            return table.concat(hex)
        end)
        if hash[0]~=nil then b.BCryptDestroyHash(hash[0]) end
        if algorithm[0]~=nil then b.BCryptCloseAlgorithmProvider(algorithm[0],0) end
        assert(ok,result); return result
    end
    function api.sha256(s) return digest(function(add) add(s,#s) end) end
    function api.module_hash(module)
        local path=ffi.new('uint16_t[32768]')
        local length=k.GetModuleFileNameW(module,path,32768)
        assert(length>0 and length<32768,'Module path unavailable')
        local file=k.CreateFileW(path,0x80000000,7,nil,3,0,nil)
        assert(file~=ffi.cast('void *',-1),'Module file unavailable')
        local ok,result=pcall(digest,function(add)
            local buf,n=ffi.new('uint8_t[65536]'),ffi.new('uint32_t[1]')
            while true do
                assert(k.ReadFile(file,buf,65536,n,nil)~=0,'Module read failed')
                if n[0]==0 then break end
                add(buf,n[0])
                if api.checkpoint then api.checkpoint('Checking game version') end
            end
        end)
        k.CloseHandle(file); assert(ok,result); return result
    end
    local function u16(s,o) local a,c=s:byte(o+1,o+2);return a+c*256 end
    local function u32(s,o) local a,c,d,e=s:byte(o+1,o+4);return a+c*256+d*65536+e*16777216 end
    function api.private_regions(include_readonly)
        local regions={}
        local info=ffi.new('Plas39QuickShotMemoryInfoV1[1]')
        local cursor=ffi.cast('uint8_t *',65536)
        while ffi.cast('uintptr_t',cursor)<0x800000000000 do
            if k.VirtualQuery(cursor,ffi.cast('void *',info),ffi.sizeof(info[0]))~=ffi.sizeof(info[0]) then break end
            local size=tonumber(info[0].size)
            local next_address=ffi.cast('uint8_t *',info[0].base)+size
            assert(size>0 and next_address>cursor,'Invalid memory-region layout')
            if info[0].state==0x1000 and info[0].kind==0x20000 and (info[0].protection==4 or (include_readonly and info[0].protection==2)) then
                regions[#regions+1]={base=ffi.cast('uint8_t *',info[0].base),size=size,protection=tonumber(info[0].protection)}
            end
            cursor=next_address
            if api.checkpoint then api.checkpoint('Enumerating writable private data') end
        end
        return regions
    end
    function api.scan_private(signature,row_offset,include_readonly)
        assert(type(signature)=='string' and #signature>=8 and #signature<=256,'Invalid data signature')
        local regions=api.private_regions(include_readonly)
        local total,scanned,matches=0,0,0
        local result,seen={},{}
        for _,region in ipairs(regions) do total=total+region.size end
        assert(total<=8589934592,'Private-data scan exceeds 8 GiB bounds. No edit applied.')
        for _,region in ipairs(regions) do
            local tail=''
            for offset=0,region.size-1,65536 do
                local length=math.min(65536,region.size-offset)
                local data=api.read(region.base+offset,length)
                if data then
                    local block=tail..data
                    local from=1
                    while true do
                        local at=block:find(signature,from,true)
                        if not at then break end
                        matches=matches+1
                        local address=region.base+offset-#tail+at-1-row_offset
                        local key=api.identity(address)
                        if not seen[key] then seen[key]=true;result[#result+1]=address end
                        from=at+1
                    end
                    tail=block:sub(-(#signature-1))
                else tail='' end
                scanned=scanned+length
                if api.progress then api.progress(scanned,total,matches) end
                if api.checkpoint then api.checkpoint('Searching private data for exact flag record') end
            end
        end
        return result
    end
    function api.scan_private_many(patterns,include_readonly)
        assert(type(patterns)=='table' and #patterns>0 and #patterns<=8,'Invalid multi-signature scan')
        local regions=api.private_regions(include_readonly)
        local total,scanned=0,0
        local results,seen={},{}
        local max_signature=0
        for i,pattern in ipairs(patterns) do
            assert(type(pattern.signature)=='string' and #pattern.signature>=8 and #pattern.signature<=256,'Invalid data signature')
            assert(type(pattern.row_offset)=='number' and pattern.row_offset>=0,'Invalid record offset')
            results[i],seen[i]={},{}
            max_signature=math.max(max_signature,#pattern.signature)
        end
        for _,region in ipairs(regions) do total=total+region.size end
        assert(total<=8589934592,'Private-data scan exceeds 8 GiB bounds. No edit applied.')
        for _,region in ipairs(regions) do
            local tail=''
            for offset=0,region.size-1,65536 do
                local length=math.min(65536,region.size-offset)
                local data=api.read(region.base+offset,length)
                if data then
                    local block=tail..data
                    for i,pattern in ipairs(patterns) do
                        local from=1
                        while true do
                            local at=block:find(pattern.signature,from,true)
                            if not at then break end
                            local address=region.base+offset-#tail+at-1-pattern.row_offset
                            local key=api.identity(address)
                            if not seen[i][key] then
                                seen[i][key]=true
                                results[i][#results[i]+1]=address
                            end
                            from=at+1
                        end
                    end
                    tail=block:sub(-(max_signature-1))
                else tail='' end
                scanned=scanned+length
                local matches=0
                for i=1,#results do matches=matches+#results[i] end
                if api.progress then api.progress(scanned,total,matches) end
                if api.checkpoint then api.checkpoint('Searching private data for PLAS-39 records') end
            end
        end
        return results
    end
    function api.candidates(module,signature,row_offset,header)
        local base=ffi.cast('uint8_t *',module)
        local dos=assert(api.read(base,64),'Cannot read module header')
        assert(dos:sub(1,2)=='MZ','Unexpected module header')
        local ntOffset=u32(dos,60); assert(ntOffset<1048576,'Invalid PE offset')
        local nt=assert(api.read(base+ntOffset,264),'Cannot read PE header')
        assert(nt:sub(1,4)=='PE\0\0' and u16(nt,24)==0x20b,'Requires PE64')
        local count,optional=u16(nt,6),u16(nt,20)
        assert(count>0 and count<=96 and optional>=112 and optional<=512,'Invalid PE layout')
        local imageSize=u32(nt,80)
        local sections=assert(api.read(base+ntOffset+24+optional,count*40),'Cannot read module sections')
        local result,seen,total={}, {},0
        for i=0,count-1 do
            local o=i*40
            local size,rva,flags=u32(sections,o+8),u32(sections,o+12),u32(sections,o+36)
            if bit.band(flags,0x40000000)~=0 and bit.band(flags,0x80000000)~=0
              and bit.band(flags,0x20000000)==0 then
                -- The supported game.dll has a 17.61 MiB writable section.
                -- Read small blocks, including initialized globals in its zero-fill tail.
                assert(size<=33554432 and rva+size<=imageSize,'Data section exceeds scan bounds')
                total=total+size; assert(total<=33554432,'Module data exceeds scan bounds')
                for offset=0,size-1,65536 do
                    local length=math.min(65536,size-offset)
                    local data=assert(api.read(base+rva+offset,length),'Module data unavailable')
                    -- Filter zero and noncanonical slots without allocating a cdata per slot.
                    local words=ffi.cast('const uintptr_t *',ffi.cast('const char *',data))
                    for index=0,math.floor(length/8)-1 do
                        local v=words[index]
                        if v>=65536 and v<0x800000000000 then
                            local key=tonumber(v)
                            if not seen[key] then
                                seen[key]=true
                                local p=ffi.cast('uint8_t *',v)
                                -- Read only a header at a module-owned pointer target.
                                local h=api.read(p,16)
                                if h and ((header and h==header) or (not header and u32(h,0)==2 and h:sub(5,8)=='LDLD' and u32(h,12)==3943969754)) then
                                    result[#result+1]=p
                                end
                            end
                        end
                        if api.checkpoint and index%256==255 then api.checkpoint('Scanning damage table') end
                    end
                    if api.progress then api.progress(total-size+offset+length,total,#result) end
                    if api.checkpoint then api.checkpoint('Scanning damage table',true) end
                end
            end
        end
        if #result==0 and signature then
            if api.checkpoint then api.checkpoint('No module pointer found; searching private data',true) end
            return api.scan_private(signature,row_offset)
        end
        return result
    end
    -- Keep external memory-region state and pointer arithmetic interpreted.
    -- Hot-loop optimization can otherwise skip the high-address read-only cache.
    local runtime_jit=rawget(_G,'jit')
    if runtime_jit and runtime_jit.off then
        runtime_jit.off(api.private_regions,true)
        runtime_jit.off(api.scan_private,true)
        runtime_jit.off(api.scan_private_many,true)
    end
    return api
end

end)()
local patch = (function()
local patch = {}

local function unhex(s)
    return (s:gsub('..', function(pair) return string.char(tonumber(pair, 16)) end))
end

local function u32(s, o)
    if not s or o < 0 or o + 4 > #s then return nil end
    local a,b,c,d = s:byte(o + 1, o + 4)
    return a + b*256 + c*65536 + d*16777216
end

local function word(v)
    return string.char(v%256, math.floor(v/256)%256,
        math.floor(v/65536)%256, math.floor(v/16777216)%256)
end

local WEAPON_HEADER = unhex('b1dbe4884c444c4401000000b1dbe488000f07000100000000000000')
local CHARGE_HEADER = unhex('a135c3ea4c444c4401000000a135c3ea880a00000100000000000000')
local WEAPON_TOTAL = 462620
local CHARGE_TOTAL = 2724
local WEAPON_MAP_COUNT = 730
local CHARGE_MAP_COUNT = 20
local WEAPON_MAP_INDEX = 162
local CHARGE_MAP_INDEX = 2
local WEAPON_RECORD_INDEX = 185
local CHARGE_RECORD_INDEX = 2
local WEAPON_STRIDE = 1232
local CHARGE_STRIDE = 216
local OWNER = unhex('5e7f47af911f0630')
local CHARGE_STOCK = unhex('6666e63e00000000000000000000000000000000000000000000003f00000000000000000000000000000000000000006666663f00000000000000000000000000000000000000003333333f0000803f0000803f000020400000803f0000803f3333333f3333b33f3333333f33331340cdcc4c3f0000c03f9449ce947c2a05f09c3d939d3a21c9ec000000002302edf2009970c900000000b48fce4ba631d98203e950a2daf744200000000000000000000000000000000000010000020000008fc2f53df22b8a6d46010000020000000000000000000000')
local CHARGE_MIN_STOCK = unhex('6666e63e')
local CHARGE_MIN_QUICK = unhex('0ad7233c')

local function rollback(api, attempted)
    local ok = true
    for i = #attempted, 1, -1 do
        local item = attempted[i]
        local current = api.read(item.address, 4)
        if current == item.after then
            local wrote = pcall(api.write_protected, item.address, item.before)
            if not wrote or api.read(item.address, 4) ~= item.before then ok = false end
        elseif current ~= item.before then
            ok = false
        end
    end
    return ok
end

local function apply_edits(api, edits)
    local attempted = {}
    local ok, reason = pcall(function()
        for _, edit in ipairs(edits) do
            assert(api.data_access(edit.address, 4), 'target field is no longer readable private data')
            local current = api.read(edit.address, 4)
            assert(current == edit.before, 'target field changed externally; refusing mode change')
            if current~=edit.after then
                attempted[#attempted + 1] = edit
                assert(api.write_protected(edit.address, edit.after), 'write was incomplete')
                assert(api.read(edit.address, 4) == edit.after, 'write verification failed')
            end
        end
    end)
    if ok then return true end
    if not rollback(api, attempted) then
        return false, 'change failed and rollback was incomplete: ' .. tostring(reason)
    end
    return false, 'change refused; original values restored: ' .. tostring(reason)
end

local function group_record(api, address, header, total, map_count, map_index,
                            record_index, stride, record_name)
    assert(api.data_access(address, total), record_name .. ' group is not supported private data')
    assert(api.read(address, #header) == header, record_name .. ' group header changed')
    local map = assert(api.read(address + 28 + map_index * 16, 16), 'Resource map unreadable')
    assert(map:sub(1,8) == OWNER and u32(map,8) == record_index,
        record_name .. ' resource owner/index changed')
    local offset = 28 + map_count * 16 + record_index * stride
    assert(offset + stride <= total, record_name .. ' row outside group')
    return address + offset, assert(api.read(address + offset,stride), record_name .. ' row unreadable')
end

local function add(api, edits, seen, address, before, after)
    local key = api.identity(address)
    if seen[key] then
        if seen[key].clone then
            assert(seen[key].after==before,'Cloned override row changed during configuration')
            seen[key].after=after
            return
        end
        assert(seen[key].after == after, 'PLAS-39 instances share charge data with different modes; no edit applied')
        return
    end
    local item = { address=address, before=before, after=after }
    seen[key] = item
    if before ~= after then edits[#edits+1] = item end
end

local function configure_weapon(api,address,edits,seen)
    local row = assert(api.read(address,192),'PLAS-39 firing fields unreadable')
    local burst,primary,secondary=u32(row,140),u32(row,144),u32(row,148)
    assert(burst==3 or burst==1,'PLAS-39 burst limit changed externally')
    assert((primary==2 and secondary==0) or (primary==3 and secondary==2),
        'PLAS-39 fire-mode slots changed externally')
    assert(u32(row,152)==0 and u32(row,156)==0,'PLAS-39 extra modes changed externally')
    local left,right=u32(row,184),u32(row,188)
    assert((left==0 and right==3) or (left==3 and right==0),'PLAS-39 function selector changed externally')
    -- The charge system emits the three physical rounds. A native Burst limit
    -- of three would nest another burst around that sequence; keep it at one.
    for _,v in ipairs({{140,1},{144,3},{148,2},{184,3},{188,0}}) do
        add(api,edits,seen,address+v[1],row:sub(v[1]+1,v[1]+4),word(v[2]))
    end
end

local function configure_charge(api,address,quick,edits,seen,cloned_row)
    local row = cloned_row or assert(api.read(address,CHARGE_STRIDE),'PLAS-39 charge fields unreadable')
    local minimum=row:sub(1,4)
    local repeats=u32(row,188)
    assert(minimum==CHARGE_MIN_STOCK or minimum==CHARGE_MIN_QUICK,'PLAS-39 charge minimum changed externally')
    assert(repeats==2 or repeats==0,'PLAS-39 charge repetitions changed externally')
    local canonical=CHARGE_MIN_STOCK .. row:sub(5,188) .. word(2) .. row:sub(193)
    assert(canonical==CHARGE_STOCK,'PLAS-39 charge data changed externally')
    add(api,edits,seen,address,minimum,quick and CHARGE_MIN_QUICK or CHARGE_MIN_STOCK)
    -- Exact-build release routine 0x73d8c0 schedules two additional firing
    -- events using +0xbc, with the +0xc0 interval. Zero disables repetitions.
    add(api,edits,seen,address+188,word(repeats),word(quick and 0 or 2))
end

local RPM_STOCK=unhex('00800944') -- 550 RPM
local RPM_SEMI=unhex('00004843') -- 200 RPM
local INTERVAL_STOCK=unhex('0e6bdf3d') -- float32(60/550)
local INTERVAL_SEMI=unhex('9a99993e') -- float32(60/200)
local function configure_cadence(api,address,quick,edits,seen)
    assert(address,'Native projectile cadence state unavailable')
    local interval=assert(api.read(address+12,4),'Native firing interval unreadable')
    assert(interval==INTERVAL_STOCK or interval==INTERVAL_SEMI,
        'Native firing interval changed externally; no edit applied')
    -- Initialization 0x611c4c computes this once from component RPM. Firing
    -- 0x612cfd adds it to remaining cooldown +8; charge release 0x73ce6e
    -- checks that cooldown. Keep the interval synchronized with the private
    -- component, without resetting or repeatedly extending remaining cooldown.
    add(api,edits,seen,address+12,interval,quick and INTERVAL_SEMI or INTERVAL_STOCK)
end
local function configure_projectile(api,address,quick,edits,seen,cloned_row)
    local row=cloned_row or assert(api.read(address,264),'PLAS-39 projectile settings unreadable')
    assert(u32(row,0)==155,'PLAS-39 projectile type changed')
    local rate=row:sub(9,12)
    assert(rate==RPM_STOCK or rate==RPM_SEMI,'PLAS-39 fire rate changed externally')
    local audio=row:sub(237,240)
    assert(audio==unhex('01010000') or audio==unhex('01000000'),'PLAS-39 MIDI flags changed externally')
    add(api,edits,seen,address+8,rate,quick and RPM_SEMI or RPM_STOCK)
    -- Native Burst's MIDI branch schedules three notes per charge release.
    -- Ordinary event posting avoids multiplying those three physical releases.
    add(api,edits,seen,address+236,audio,quick and unhex('01010000') or unhex('01000000'))
end

function patch.prepare(api,native)
    local targets=native.prepare(api)
    local weapon_address,weapon_row=group_record(api,targets.weapon_group,WEAPON_HEADER,
        WEAPON_TOTAL,WEAPON_MAP_COUNT,WEAPON_MAP_INDEX,WEAPON_RECORD_INDEX,WEAPON_STRIDE,'WeaponDataComponent')
    local charge_address,charge_row=group_record(api,targets.charge_group,CHARGE_HEADER,
        CHARGE_TOTAL,CHARGE_MAP_COUNT,CHARGE_MAP_INDEX,CHARGE_RECORD_INDEX,CHARGE_STRIDE,'WeaponChargeComponent')
    assert(u32(weapon_row,140)==3,'PLAS-39 stock burst limit changed; no edit applied')
    assert(charge_row==CHARGE_STOCK,'PLAS-39 stock charge data changed; no edit applied')
    local edits,seen={},{}
    configure_weapon(api,weapon_address,edits,seen)
    local applied,reason=apply_edits(api,edits)
    assert(applied,reason)
    return { weapon_address=weapon_address,charge_address=charge_address,native=targets,projectile_address=targets.projectile_address,last_modes={} }
end

function patch.synchronize(api,plan,native)
    local instances=native.instances(api,plan)
    local edits,seen,modes={}, {}, {}
    native.isolate(api,plan,instances,edits,seen)
    configure_weapon(api,plan.weapon_address,edits,seen)
    local quick_count,burst_count=0,0
    for _,item in ipairs(instances) do
        local quick=item.mode==2
        if quick then quick_count=quick_count+1 else burst_count=burst_count+1 end
        configure_weapon(api,item.weapon,edits,seen)
        configure_charge(api,item.charge,quick,edits,seen,item.charge_row)
        configure_projectile(api,item.projectile,quick,edits,seen,item.projectile_row)
        configure_cadence(api,item.projectile_state,quick,edits,seen)
        modes[item.id]=item.mode
        if quick and plan.last_modes[item.id]~=2 and item.charge_state then
            local queued=assert(api.read(item.charge_state+20,8),'Charge repetition state unreadable')
            local counter=u32(queued,0)
            assert(counter<=2,'Charge repetition counter changed')
            add(api,edits,seen,item.charge_state+20,queued:sub(1,4),word(0))
            add(api,edits,seen,item.charge_state+24,queued:sub(5,8),word(0))
        end
        assert(api.read(item.entity,24)==item.identity
            and u32(api.read(item.mode_address,4),0)==item.mode,'Native weapon mode changed before write')
    end
    native.validate(api,plan,instances)
    local applied,reason=apply_edits(api,edits)
    if not applied then return false,reason end
    plan.last_modes=modes
    local label='Waiting for a PLAS-39 instance'
    if quick_count>0 and burst_count==0 then label='Semi: one shot; min_charge=0.01s; charge_repetitions=0; rate=200 RPM; firing_interval=0.30s'
    elseif burst_count>0 and quick_count==0 then label='Burst: three charged shots; min_charge=0.45s; charge_repetitions=2; audio=ordinary firing event'
    elseif quick_count>0 then label='Separate native PLAS-39 modes synchronized' end
    return true,label,#edits>0,quick_count+burst_count
end

return patch


end)()
local native = (function()
local native = {}
local OWNER = '5e7f47af911f0630'
local GUARDS = {{rva=5281136,bytes='4885c97471488b051c2af602448bc14c8b90d82bf10048b8379f711660f3196748f7e1488bc1482bc248d1e84803c248'},{rva=5262720,bytes='4885c9746c488b050c72f602448bc14c8b90d82af10048b8cdcccccccccccccc48f7e148c1ea048d0492c1e002442bc0'},{rva=7694280,bytes='8bc8498b4260488d14498b049048'},{rva=7592314,bytes='498bcde83e79dcff488bf88b88bc00000083f901762e418b44ee143bc173208b8fc000000041894cee188d480141894cee14eb103bc87582438b44c304eb80418974ee14418b4508'},{rva=7695008,bytes='443ba88c0000000f92c04883c420415e415d'},{rva=5327888,bytes='4885c97471488b057c73f502448bc14c8b90802ef10048b8fb99d3e0ce8bd4f148f7e148c1ea0969c21e020000442bc0'},{rva=5329152,bytes='4883ec284c8bd14885c9750733c04883c428c38b41083b0508ebf6020f84a30000004c8b1daf15e1024533c048895c24'},{rva=6376742,bytes='8b45a80f57ffffc8f20f5af8a9fdffffff0f84c0000000'},{rva=6376525,bytes='4180b8ed000000000f84f5030000'},{rva=7588168,bytes='3953100f862c0f00004889b4'},{rva=7597496,bytes='488b05f975be02ba001b0000488b0dad75be0241b808000000c74304200000004c8b485841ffd18b4b0433d24c69c1d8000000488bc848898390000000e8a6bc9401'},{rva=7599818,bytes='8bab880000004c8d7350ffcd4c897c2458498bce89ab88000000e8b701ff004c8d7b708bd5498bcfe8a901ff003bee0f8439'},{rva=6395126,bytes='488b05bbced002ba00340100488b0d6fced00241b808000000c74330800000004c8b485841ffd18b4b3033d24c69c168020000488bc8488983d0'},{rva=6398105,bytes='8babc80000004c89742450ffcd4c897c24584c8dbb90000000498bcf89abc8000000e8e05711018bd5488d8bb0000000e8d25711013bef0f84620100004c'},{rva=5264064,bytes='4883ec284c8bd14885c9750733c04883c428c38b41083b0548e9f7020f84930000004c8b1d3719e2024533c048895c243048896c24384889742440458b4b58418b5b600fafd848897c2420418d69ff4585c9742c498b7b50418b735c0f1f40008bcd418d14184823d1488d0cd78b14d73bd6740e3bd0740a41ffc0453bc172e033c9488b7c2420488b742440488b6c2438488b5c24303901751b8b410483f8ff74134869c0d8000000490383900000004883c428c3498b0a4883c428e9'},{rva=24311696,bytes='48895c2408488974241048897c2418448b510833c0448b5910418bf0440fafda448bca418d7aff4585d274274c8b018b590c8bcf428d14184823d1498d0cd0418b14d03bd3740e413bd17409ffc0413bc272df33c9488b5c2408488bc1488b7c2418897104488b742410448909c3'},{rva=24311968,bytes='48895c2418488974242057448b59088bda0faf59104533c0448bd2418d73ff4585db7427488b39660f1f840000000000418d14188bc64823d0443914d74c8d0cd7741641ffc0453bc372e533c0488b5c2420488b7424285fc38b410c418901440faf51108b510848896c2410418b69044c897424188d72ff478d340241ba01000000418bfe23fe413bd2765f0f1f40004c8b19478d0c164423ce4a8d1ccd00000000468b041b443b410c743f440faf41108bc22bd74103d123d64423c6412bc04103c123c63bd077174a8b041b8bd7418bf9498904d34c8b018b510c428914038b510841ffc2443bd272a54c8b7424188bc5488b6c2410488b5c2420488b7424285fc3'},{rva=6364083,bytes='498b6f78498bce8bc34869f8a800000048894424304803ef4889bc24d000000048896c2440'},{rva=6364236,bytes='f3410f594d08488b05af46d102f30f1005df5adb014489651cf30f5ec1f30f11450c'},{rva=6368504,bytes='488b442478f30f10400cf30f584008f30f114008'},{rva=7589458,bytes='438b44c30483f8ff741a4869d0a8000000488b056e98be02488b4878440f2f6c0a08720d488b4c2458488bd6e83d0a0000'}}
local function unhex(s) return (s:gsub('..', function(p) return string.char(tonumber(p,16)) end)) end
OWNER = unhex(OWNER)
local function u32(s,o)
    assert(s and o >= 0 and o+4 <= #s, 'Native field unreadable')
    local a,b,c,d=s:byte(o+1,o+4)
    return a+b*256+c*65536+d*16777216
end
local function read(api,p,n) return assert(api.read(p,n), 'Native data unavailable') end
local function pointer(api,s,o) return assert(api.pointer(s,o), 'Native pointer unavailable') end
local function lookup(api,h,o,key)
    local cap,empty,mult=u32(h,o+8),u32(h,o+12),u32(h,o+16)
    assert(cap <= 4096 and (cap == 0 or bit.band(cap,cap-1) == 0), 'Native map capacity changed')
    if cap == 0 then return nil end
    local array=pointer(api,h,o)
    -- Split multiplication to preserve exact 32-bit wraparound in Lua numbers.
    local product=((key%65536)*mult + math.floor(key/65536)*(mult%65536)*65536)%4294967296
    for probe=0,math.min(cap,64)-1 do
        local row=read(api,array+bit.band(product+probe,cap-1)*8,8)
        local identity,index=u32(row,0),u32(row,4)
        if identity == key then return index ~= 4294967295 and index or nil end
        if identity == empty then return nil end
    end
    error('Native map probe bound reached')
end

function native.prepare(api)
    local game=api.byte_pointer(api.module('game.dll'))
    for _,g in ipairs(GUARDS) do
        local bytes=unhex(g.bytes)
        assert(read(api,game+g.rva,#bytes)==bytes,'Unsupported native weapon code; no edit applied')
    end
    local owner=pointer(api,read(api,game+0x346bf98,8),0)
    local weapon_map=pointer(api,read(api,owner+0xf12bd8,8),0)
    local charge_map=pointer(api,read(api,owner+0xf12ad8,8),0)
    local projectile_map=pointer(api,read(api,owner+0xf12e80,8),0)
    local mapping=read(api,projectile_map+290*16,16)
    assert(mapping:sub(1,8)==OWNER and u32(mapping,8)==136,'Projectile resource owner/index changed')
    return { game=game, owner=owner, weapon_group=weapon_map-28, charge_group=charge_map-28,
        projectile_map=projectile_map, projectile_address=projectile_map+542*16+136*616 }
end

function native.instances(api,plan)
    assert(api.pointer(read(api,plan.native.game+0x346bf98,8),0)==plan.native.owner,
        'Native entity tables changed; restart required')
    assert(api.pointer(read(api,plan.native.owner+0xf12bd8,8),0)==plan.native.weapon_group+28
        and api.pointer(read(api,plan.native.owner+0xf12ad8,8),0)==plan.native.charge_group+28,
        'Native component tables changed; restart required')
    local manager=pointer(api,read(api,plan.native.game+0x3326ce0,8),0)
    local h=read(api,manager,192)
    local count=u32(h,0x1c)
    assert(count <= 512 and count <= u32(h,0x10), 'Native weapon instance count changed')
    local array=pointer(api,h,0x48)
    local modes=pointer(api,h,0x60)
    local charge_manager=pointer(api,read(api,plan.native.game+0x3326c20,8),0)
    local ch=read(api,charge_manager,160)
    local projectile_manager=pointer(api,read(api,plan.native.game+0x33266d8,8),0)
    local ph=read(api,projectile_manager,224)
    assert(pointer(api,read(api,plan.native.owner+0xf12e80,8),0)==plan.native.projectile_map,
        'Native projectile table changed')
    local owned=u32(ch,0x10)
    assert(owned<=u32(ch,0xc) and u32(ch,0xc)<=512, 'Native owned charge count changed')
    local references=owned>0 and read(api,pointer(api,ch,0x38),owned*8) or ''
    local result={}
    for slot=0,owned-1 do
        local entity=pointer(api,references,slot*8)
        local identity=read(api,entity,24)
        if identity:sub(1,8)==OWNER and bit.band(u32(identity,20),1)==1 then
            local id=u32(identity,8)
            local i=lookup(api,h,0x30,id)
            assert(i and i<count,'Native weapon slot changed')
            assert(read(api,array+i*8,8)==references:sub(slot*8+1,slot*8+8),'Native firing owner changed')
            local mode_address=modes+i*12
            local mode=u32(read(api,mode_address,4),0)
            if mode==2 or mode==3 then
                local weapon=plan.weapon_address
                local wi=lookup(api,h,0x70,id)
                if wi then
                    assert(wi < u32(h,0xa8),'Native weapon settings index changed')
                    weapon=pointer(api,h,0xb0)+wi*1232
                end
                local charge=plan.charge_address
                local ci=lookup(api,ch,0x50,id)
                if ci then
                    assert(ci < u32(ch,0x88),'Native charge settings index changed')
                    charge=pointer(api,ch,0x90)+ci*216
                end
                local projectile=plan.projectile_address
                local pi=lookup(api,ph,0x90,id)
                if pi then
                    assert(pi < u32(ph,0xc8) and pi<512,'Native projectile settings index changed')
                    projectile=pointer(api,ph,0xd0)+pi*616
                end
                local charge_state
                local psi=lookup(api,ph,0x50,id)
                assert(psi and psi<u32(ph,0x38) and u32(ph,0x38)<=512,
                    'Native projectile state index changed')
                assert(read(api,pointer(api,ph,0x68)+psi*8,8)==references:sub(slot*8+1,slot*8+8),
                    'Native projectile state owner changed')
                local projectile_state=pointer(api,ph,0x78)+psi*168
                local si=lookup(api,ch,0x20,id)
                if si then
                    assert(si == slot,'Native charge state index changed')
                    assert(read(api,pointer(api,ch,0x38)+si*8,8)==references:sub(slot*8+1,slot*8+8),
                        'Native charge instance owner changed')
                    charge_state=pointer(api,ch,0x40)+si*40
                end
                -- Only the owned charge prefix is advanced by the native firing loop.
                -- Dropped/preview WeaponData instances must never select shared firing settings.
                if si and si<u32(ch,0x10) then
                result[#result+1]={ id=id, mode=mode, mode_address=mode_address,
                    entity=entity, identity=identity, weapon=weapon, charge=charge,
                    charge_state=charge_state, projectile=projectile, projectile_state=projectile_state,
                    charge_cached=ci~=nil, projectile_cached=pi~=nil }
                end
            end
        end
    end
    -- A game update may swap arrays; reject stale snapshots before any writes.
    assert(read(api,manager+0x48,8)==h:sub(0x49,0x50)
        and read(api,manager+0x60,8)==h:sub(0x61,0x68),'Native weapon arrays changed')
    plan.instance_snapshot={data_manager=manager,data_header=h,charge_manager=charge_manager,
        charge_header=ch,projectile_manager=projectile_manager,projectile_header=ph}
    return result
end


local function word(v)
    return string.char(v%256,math.floor(v/256)%256,math.floor(v/65536)%256,math.floor(v/16777216)%256)
end

-- Use the engine's already allocated override rows and both index maps.
-- No new allocation, source-table edit, native call or code patch is required.
-- Native destructors remove these entries and compact the rows on entity removal.
function native.isolate(api,plan,instances,edits,seen)
    local snapshot=assert(plan.instance_snapshot,'Native instance snapshot unavailable')
    local function stage(address,after,clone)
        local key=api.identity(address)
        assert(not seen[key],'Override reservation overlaps another edit')
        local entry={address=address,before=read(api,address,4),after=after,clone=clone}
        seen[key]=entry
        edits[#edits+1]=entry
    end
    local function reserve(group,key,index,reserved)
        local cap,empty,mult=u32(group.header,group.offset+8),u32(group.header,group.offset+12),u32(group.header,group.offset+16)
        assert(cap>0 and cap<=4096 and bit.band(cap,cap-1)==0,'Override map capacity changed')
        local array=pointer(api,group.header,group.offset)
        local product=((key%65536)*mult+math.floor(key/65536)*(mult%65536)*65536)%4294967296
        local tombstone
        for probe=0,math.min(cap,64)-1 do
            local address=array+bit.band(product+probe,cap-1)*8
            local identity=api.identity(address)
            local row=reserved[identity] or read(api,address,8)
            if u32(row,0)==key then
                assert(u32(row,4)==4294967295,'Override key already registered')
            end
            if u32(row,4)==4294967295 and not tombstone then tombstone=address end
            if u32(row,0)==empty or u32(row,0)==key then
                local target=tombstone or address
                reserved[api.identity(target)]=word(key)..word(index)
                return target
            end
        end
        if cap<=64 and tombstone then
            reserved[api.identity(tombstone)]=word(key)..word(index)
            return tombstone
        end
        error('No bounded override map slot available; no edit applied')
    end
    local function isolate(manager,header,capacity_offset,count_offset,forward_offset,reverse_offset,array_offset,stride,field,cached)
        local count,capacity=u32(header,count_offset),u32(header,capacity_offset)
        assert(count<=capacity and capacity<=512,'Override row capacity changed')
        local rows=pointer(api,header,array_offset)
        local next_index=count
        local reserved,publications={},{}
        for _,item in ipairs(instances) do
            if not item[cached] then
                assert(next_index<capacity,'Preallocated override rows exhausted; no edit applied')
                local forward=reserve({header=header,offset=forward_offset},item.id,next_index,reserved)
                local reverse=reserve({header=header,offset=reverse_offset},next_index,item.id,reserved)
                local source=read(api,item[field],stride)
                local target=rows+next_index*stride
                assert(api.data_access(target,stride),'Override row is not writable private data')
                for offset=0,stride-4,4 do stage(target+offset,source:sub(offset+1,offset+4),true) end
                -- Reverse map and count precede the forward key publication.
                stage(reverse+4,word(item.id));stage(reverse,word(next_index))
                publications[#publications+1]={address=forward,index=next_index,id=item.id}
                item[field]=target
                item[field..'_row']=source
                next_index=next_index+1
            end
        end
        if next_index~=count then
            stage(manager+count_offset,word(next_index))
            for _,entry in ipairs(publications) do
                stage(entry.address+4,word(entry.index));stage(entry.address,word(entry.id))
            end
        end
    end
    isolate(snapshot.charge_manager,snapshot.charge_header,4,0x88,0x50,0x70,0x90,216,'charge','charge_cached')
    isolate(snapshot.projectile_manager,snapshot.projectile_header,0x30,0xc8,0x90,0xb0,0xd0,616,'projectile','projectile_cached')
end

function native.validate(api,plan,instances)
    local s=assert(plan.instance_snapshot)
    assert(read(api,s.data_manager,192)==s.data_header
        and read(api,s.charge_manager,160)==s.charge_header
        and read(api,s.projectile_manager,224)==s.projectile_header,
        'Native manager changed before override publication; no edit applied')
    for _,item in ipairs(instances) do
        assert(read(api,item.entity,24)==item.identity
            and u32(read(api,item.mode_address,4),0)==item.mode,'Native weapon changed before override publication')
    end
end

return native

end)()
local start = (function()
return function(make_api, patch, native)
    if rawget(_G,'Plas39FireModeV1') then return end
    local state={version='1.1.8',status='Waiting for game data',mode='Reading native selection',
        scanned=0,candidates=0,instances=0,diagnostics={}}
    _G.Plas39FireModeV1=state
    local previous=update
    local callback,plan,api
    local deadline=0
    local last_message
    local function log()
        pcall(function()
            local loader=rawget(_G,'CowboyBingusModLoader')
            local file=loader and loader.open_log and loader.open_log('Plas39FireMode.log')
            if file then
                file:write('Plas39FireMode v'..state.version..'\nstatus='..state.status
                    ..'\nmode='..state.mode..'\nnative_instances='..state.instances
                    ..'\nscanned_bytes=0\nselection_source=native WeaponDataComponent state\n'
                    ..table.concat(state.diagnostics,'\n')..'\n')
                file:close()
            end
        end)
    end
    local worker=coroutine.create(function()
        api=make_api()
        api.checkpoint=function(stage)
            state.status=stage
            if os.clock()>=deadline then coroutine.yield() end
        end
        local exe,game=api.module(nil),api.module('game.dll')
        assert(exe and game,'Game modules unavailable')
        assert(api.module_hash(exe)=='F5FEE03DCFDB2E553A4752C283590950AC13316B376D8196AA556FF0400D5F06',
            'Unsupported executable; no edit applied')
        assert(api.module_hash(game)=='2E2C3B7C2500646DADD5F2B4C6E0504DBB7E7896139F64CDDC0D1813C718F51E',
            'Unsupported game module; no edit applied')
        for attempt=1,60 do
            local ok,result=pcall(patch.prepare,api,native)
            if ok then return result end
            local detail=tostring(result)
            local transient=detail:find('Native pointer unavailable',1,true)
                or detail:find('Native data unavailable',1,true)
            if not transient or attempt==60 then error(result) end
            state.status='Waiting for native component tables; attempt '..attempt..'/60'
            log()
            local retry=api.now()+1000
            repeat coroutine.yield() until api.now()>=retry
        end
    end)
    local function synchronize()
        if not plan then return end
        local ok,applied,label,changed,count=pcall(patch.synchronize,api,plan,native)
        local message
        if ok and applied then
            state.mode=label
            state.instances=count
            state.status='Native mode synchronized; left-side selector active'
            message=label
        else
            state.status=ok and label or tostring(applied)
            message=state.status
        end
        if message~=last_message then
            last_message=message
            print('[PLAS-39 Fire Mode] '..message)
            log()
        end
    end
    local function tick()
        if plan then synchronize()
        elseif coroutine.status(worker)~='dead' then
            deadline=os.clock()+0.0007
            local ok,result=coroutine.resume(worker)
            if not ok then
                state.status=tostring(result);log()
                print('[PLAS-39 Fire Mode] '..state.status)
                if update==callback then update=previous or function() end end
            elseif coroutine.status(worker)=='dead' then
                plan=result
                synchronize()
            end
        end
    end
    local function pack(...) return {n=select('#',...),...} end
    callback=function(...)
        tick()
        local results
        if previous then results=pack(previous(...)) end
        -- Read the native selection again after the game processes this frame.
        synchronize()
        if results then return unpack(results,1,results.n) end
    end
    update=callback
    log()
end

end)()
start(make_api, patch, native)
