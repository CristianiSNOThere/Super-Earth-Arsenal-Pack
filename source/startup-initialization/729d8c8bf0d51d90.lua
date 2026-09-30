-- HD2-Addon: mods/codex/flag_damage_prototype
local make_api=(function()
return function()
    local ffi = require('ffi')
    assert(ffi.abi('64bit'), 'Requires Windows x64 LuaJIT')
    ffi.cdef [[
        void *GetModuleHandleA(const char *);
        void *GetCurrentProcess(void);
        uint64_t GetTickCount64(void);
        uint32_t GetModuleFileNameW(void *, uint16_t *, uint32_t);
        int ReadProcessMemory(void *, const void *, void *, size_t, size_t *);
        int WriteProcessMemory(void *, void *, const void *, size_t, size_t *);
        size_t VirtualQuery(const void *, void *, size_t);
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
        } FlagDamageMemoryInfoV1;
    ]]
    local k, b = ffi.load('kernel32'), ffi.load('bcrypt')
    local self = k.GetCurrentProcess()
    local api = {}
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
        local info=ffi.new('FlagDamageMemoryInfoV1[1]')
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
    function api.private_regions()
        local regions={}
        local allocations={}
        local info=ffi.new('FlagDamageMemoryInfoV1[1]')
        local cursor=ffi.cast('uint8_t *',65536)
        while ffi.cast('uintptr_t',cursor)<0x800000000000 do
            if k.VirtualQuery(cursor,ffi.cast('void *',info),ffi.sizeof(info[0]))~=ffi.sizeof(info[0]) then break end
            local size=tonumber(info[0].size)
            local next_address=ffi.cast('uint8_t *',info[0].base)+size
            assert(size>0 and next_address>cursor,'Invalid memory-region layout')
            if info[0].state==0x1000 and info[0].kind==0x20000 and info[0].protection==4 then
                local allocation=ffi.cast('uint8_t *',info[0].allocation)
                local identity=api.identity(allocation)
                if allocations[identity]==nil then
                    local head=identity>=0x80000000 and api.read(allocation,32) or nil
                    local eligible=false
                    if head then
                        for offset=0,12,4 do
                            if head:sub(offset+1,offset+4)=='LDLD' and u32(head,offset+4)==1 then eligible=true;break end
                        end
                    end
                    allocations[identity]=eligible
                end
                if allocations[identity] then
                    regions[#regions+1]={base=ffi.cast('uint8_t *',info[0].base),size=size}
                end
            end
            cursor=next_address
            if api.checkpoint then api.checkpoint('Enumerating writable private data') end
        end
        return regions
    end
    function api.scan_private(signature,row_offset)
        assert(type(signature)=='string' and #signature==76,'Invalid flag signature')
        local regions=api.private_regions()
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
                    tail=block:sub(-75)
                else tail='' end
                scanned=scanned+length
                if api.progress then api.progress(scanned,total,matches) end
                if api.checkpoint then api.checkpoint('Searching private data for exact flag record') end
            end
        end
        return result
    end
    function api.candidates(module,signature,row_offset)
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
                                if h and u32(h,0)==2 and h:sub(5,8)=='LDLD' and u32(h,12)==3943969754 then
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
    return api
end

end)()
local patch=(function()
local patch = {}
local SIZE, COUNT, STRIDE = 49424, 649, 76
local TABLE_SHA = '7BDD751C1336E5BEA8023B5C12A6A8FC60E1EE0BF50132D6BAFDA9D44AD1F72A'
local FLAG = '2d020000c800000064000000030000000000000000000000000000000a000000230000001e00000000000000270000000000a040000000000000000000000000000000000000000000000000'
local function u32(s, o)
    if not s or o < 0 or o + 4 > #s then return nil end
    local a,b,c,d = s:byte(o+1,o+4)
    return a+b*256+c*65536+d*16777216
end
local function set(s,o,b) return s:sub(1,o)..b..s:sub(o+#b+1) end
local function pack32(v)
    return string.char(v%256,math.floor(v/256)%256,math.floor(v/65536)%256,math.floor(v/16777216)%256)
end
function patch.damage_values(settings)
    settings=settings or {}
    assert(type(settings)=='table','Invalid damage settings')
    local normal=0
    for _,digit in ipairs({{'thousands',1000,0},{'hundreds',100,300},{'tens',10,0},{'ones',1,0}}) do
        local value=settings[digit[1]]
        if value==nil then value=digit[3] end
        assert(type(value)=='number' and value>=0 and value<=9*digit[2] and value%digit[2]==0,'Invalid '..digit[1]..' setting')
        normal=normal+value
    end
    local ratio=settings.durable_ratio or 50
    assert(ratio==50 or ratio==100,'Invalid durable damage ratio')
    return normal,math.floor(normal*ratio/100)
end
local SIGNATURE = FLAG:gsub('..',function(hex) return string.char(tonumber(hex,16)) end)

local function identify(api, address)
    if not api.writable(address, SIZE) then return nil,'not writable private data' end
    local s = api.read(address, SIZE)
    if not s or #s ~= SIZE then return nil,'full table read failed' end
    if u32(s,0) ~= 2 then return nil,'not a two-group table' end
    for _, h in ipairs({{4,3943969754,32},{60,3769052400,49340}}) do
        if u32(s,h[1]) ~= 0x444c444c or u32(s,h[1]+4) ~= 1
          or u32(s,h[1]+8) ~= h[2] or u32(s,h[1]+12) ~= h[3]
          or u32(s,h[1]+16) ~= 1 or u32(s,h[1]+20) ~= 0 then return nil,'group header mismatch at '..h[1] end
    end
    if u32(s,92) ~= COUNT or u32(s,96) ~= 0 then return nil,'row count mismatch' end
    local ptr = api.pointer(s,84)
    if not ptr or api.distance(ptr,address) ~= 100 then return nil,'relocated pointer mismatch: '..tostring(ptr and api.distance(ptr,address)) end
    -- Accept only the exact companion SAI v0.1 edit; hash every other byte.
    local normalized=s
    if u32(s,4208)==90 and u32(s,4212)==21 then
        normalized=set(s,4208,pack32(80)..pack32(4))
    end
    local hash=api.sha256(normalized:sub(101))
    if hash ~= TABLE_SHA then return nil,'rows hash mismatch: '..hash end
    local offset, seen = nil, {}
    for i=0,COUNT-1 do
        local o = 100+i*STRIDE
        local kind = u32(s,o)
        if not kind or seen[kind] then return nil,'duplicate or invalid row '..i end
        seen[kind] = true
        if kind == 557 then
            local hex = s:sub(o+1,o+STRIDE):gsub('.',function(c) return string.format('%02x',c:byte()) end)
            if hex ~= FLAG then return nil,'flag record mismatch: '..hex end
            offset = o+4
        end
    end
    if not offset then return nil,'flag row missing' end
    return {address=address, source=s, offset=offset}
end

function patch.apply(api, module)
    local ok, result = pcall(function()
        local normal,durable=patch.damage_values(rawget(_G,'FlagDamageOptionsV1'))
        local NEW_DAMAGE=pack32(normal)..pack32(durable)
        local candidates, seen = {}, {}
        for _,address in ipairs(api.candidates(module,SIGNATURE,41976)) do
            local identity = api.identity(address)
            if not seen[identity] then
                seen[identity] = true
                local plan,reason = identify(api,address)
                if api.note then api.note(string.format('address=%.0f',identity)..': '..(reason or 'fully validated table')) end
                if plan then candidates[#candidates+1] = plan end
            end
        end
        assert(#candidates == 1, 'Expected one supported damage table; found '..#candidates..'. No edit applied.')
        local p = candidates[1]
        assert(api.read(p.address,SIZE) == p.source, 'Damage data changed before edit. No edit applied.')
        local expected = set(p.source,p.offset,NEW_DAMAGE)
        local before = p.source:sub(p.offset+1,p.offset+8)
        local applied, reason = pcall(function()
            assert(api.write(p.address+p.offset,NEW_DAMAGE), 'Damage write was incomplete')
            assert(api.read(p.address,SIZE) == expected, 'Full damage-table verification failed')
        end)
        if not applied then
            local now = api.read(p.address,SIZE)
            local recoverable = now and #now == SIZE and set(now,p.offset,before) == p.source
            if recoverable then
                for i=1,8 do
                    local b=now:byte(p.offset+i)
                    if b ~= before:byte(i) and b ~= NEW_DAMAGE:byte(i) then recoverable=false end
                end
            end
            local recovered = recoverable and api.write(p.address+p.offset,before)
              and api.read(p.address,SIZE) == p.source
            error(tostring(reason)..'; restored='..tostring(not not recovered))
        end
        return 'Applied: flag damage 200 -> '..normal..'; durable damage 100 -> '..durable..'.'
    end)
    return ok, tostring(result)
end
return patch

end)()
local start=(function()
return function(make_api,patch)
    if rawget(_G,'FlagDamagePrototypeV1') then return end
    local state={version='0.9',active=false,status='Waiting for first game update',scanned=0,candidates=0,diagnostics={}}
    _G.FlagDamagePrototypeV1=state
    local previous=update
    local callback
    local function log()
        pcall(function()
            local logger=rawget(_G,'CowboyBingusModLoader')
            local file=logger and logger.open_log and logger.open_log('FlagDamagePrototype.log')
            if file then
                file:write('FlagDamagePrototype v0.9 CONFIGURABLE DAMAGE\nstatus='..state.status..'\nscanned_bytes='..state.scanned..'\ncandidates='..state.candidates..'\n'..table.concat(state.diagnostics,'\n')..'\n')
                file:close()
            end
        end)
    end
    local deadline=0
    local logged_mb=-1
    local worker=coroutine.create(function()
            local api=make_api()
            api.note=function(message)
                if #state.diagnostics>=12 then table.remove(state.diagnostics,1) end
                state.diagnostics[#state.diagnostics+1]='validation='..message
            end
            api.checkpoint=function(stage,force)
                state.status=stage
                if force or os.clock()>=deadline then coroutine.yield() end
            end
            api.progress=function(scanned,total,candidates)
                state.scanned,state.candidates=scanned,candidates
                local mb=math.floor(scanned/16777216)
                if mb~=logged_mb then logged_mb=mb;log() end
            end
            local exe,game=api.module(nil),api.module('game.dll')
            assert(exe~=nil and game~=nil,'Game modules unavailable')
            assert(api.module_hash(exe)=='F5FEE03DCFDB2E553A4752C283590950AC13316B376D8196AA556FF0400D5F06','Unsupported executable. No edit applied.')
            assert(api.module_hash(game)=='2E2C3B7C2500646DADD5F2B4C6E0504DBB7E7896139F64CDDC0D1813C718F51E','Unsupported game module. No edit applied.')
            local function wait_for_loading(milliseconds,attempt)
                if not api.now then return end
                state.status='Waiting for game data to load; attempt '..attempt..'/6'
                log()
                local until_time=api.now()+milliseconds
                repeat coroutine.yield() until api.now()>=until_time
            end
            for attempt=1,6 do
                wait_for_loading(attempt==1 and 15000 or 10000,attempt)
                local applied,reason=patch.apply(api,game)
                if applied then return reason end
                if not reason:find('found 0. No edit applied.',1,true) or attempt==6 then error(reason) end
                state.status='Damage table not ready; retrying after loading'
                log()
            end
    end)
    local function init()
        if coroutine.status(worker)=='dead' then return end
        deadline=os.clock()+0.0007
        local ok,message=coroutine.resume(worker)
        if not ok or coroutine.status(worker)=='dead' then
            state.active,state.status=ok,tostring(message)
            print('[FlagDamagePrototype] '..state.status)
            log()
            if update==callback then update=previous or function() end end
        end
    end
    local function finish(...) init();return ... end
    callback=function(...)
        if previous then return finish(previous(...)) end
        init()
    end
    update=callback
    log()
end

end)()
start(make_api,patch)
