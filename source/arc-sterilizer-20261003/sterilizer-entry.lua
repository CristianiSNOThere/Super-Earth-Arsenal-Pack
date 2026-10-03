-- HD2-Addon: mods/codex/sterilizer_armor_control
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
        } SaiFocusMemoryInfoV1;
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
    function api.record_candidates(module)
        local function u32(s,o)
            if not s or #s < o+4 then return nil end
            local a,b,c,d=s:byte(o+1,o+4)
            return a+b*256+c*65536+d*16777216
        end
        local base=ffi.cast('uint8_t *',module)
        local owner=assert(api.pointer(api.read(base+0x346bf98,8),0),'Entity owner pointer unavailable')
        local map=assert(api.pointer(api.read(owner+0xf12bd8,8),0),'Entity source table unavailable')
        local entities=map-26151684
        local magazine,health=entities+576052,entities+9520532
        local status={}
        local seen={}
        for _,region in ipairs(api.private_regions(true)) do
            local head=api.read(region.base,56)
            if head then
                for offset=0,12,4 do
                    if head:sub(offset+1,offset+4)=='LDLD' and u32(head,offset+4)==1
                      and u32(head,offset+8)==0xc63e0b22 and u32(head,offset+12)==11888 then
                        local address=region.base+offset+8248
                        if u32(api.read(address,4),0)==55 and not seen[api.identity(address)] then
                            seen[api.identity(address)]=true;status[#status+1]=address
                        end
                    end
                end
            end
            if api.checkpoint then api.checkpoint('Resolving status allocation header') end
        end
        return {{magazine},status,{health}}
    end
    function api.writable(p,n)
        local info=ffi.new('SaiFocusMemoryInfoV1[1]')
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
        local info=ffi.new('SaiFocusMemoryInfoV1[1]')
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
        local info=ffi.new('SaiFocusMemoryInfoV1[1]')
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
        local allocations={}
        local info=ffi.new('SaiFocusMemoryInfoV1[1]')
        local cursor=ffi.cast('uint8_t *',65536)
        while ffi.cast('uintptr_t',cursor)<0x800000000000 do
            if k.VirtualQuery(cursor,ffi.cast('void *',info),ffi.sizeof(info[0]))~=ffi.sizeof(info[0]) then break end
            local size=tonumber(info[0].size)
            local next_address=ffi.cast('uint8_t *',info[0].base)+size
            assert(size>0 and next_address>cursor,'Invalid memory-region layout')
            if info[0].state==0x1000 and info[0].kind==0x20000 and (info[0].protection==4 or (include_readonly and info[0].protection==2)) then
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
                if api.checkpoint then api.checkpoint('Searching private data for Sterilizer records') end
            end
        end
        return results
    end
    function api.candidates(module,signature,row_offset,header)
        if not header then
            local slot=ffi.cast('uint8_t *',module)+0x348e1f8
            local target=api.pointer(api.read(slot,8),0)
            local head=target and api.read(target,16)
            if head and u32(head,0)==2 and head:sub(5,8)=='LDLD' and u32(head,12)==3943969754 then
                return {target}
            end
        end
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
local patch=(function()
local patch = {}

local DAMAGE_SIZE, DAMAGE_ROWS, DAMAGE_STRIDE = 49424, 649, 76
local MAGAZINE_SIZE, ACID_STATUS_SIZE, HELLDIVER_HEALTH_SIZE = 160, 152, 22096
local DAMAGE_SHA = '7BDD751C1336E5BEA8023B5C12A6A8FC60E1EE0BF50132D6BAFDA9D44AD1F72A'
local HELLDIVER_HEALTH_SHA = '62D225DF29B43193E042A38FBB44051642819F66297B4E7560D8FE3618A00AF0'
local DAMAGE_SIGNATURE_HEX = '1c000000010000000100000005000000050000000500000000000000050000000a00000005000000050000002b0000000000003f2d0000000000003f00000000000000000000000000000000'
local MAGAZINE_SIGNATURE_HEX = '000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000007d0000000300000006000000040000000000000000000000'
local ACID_DURATION_SIGNATURE_HEX = '00000000000000009db958bdd7e7bc960000c03f0000803f0000803f'
local HELLDIVER_HEALTH_SIGNATURE_HEX = '7d000000000000000000000000000000010000000000000000000000000000bf000000000000003f000000000000000000000000000000400000403f00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000'
local PLAYER_GAS_MULTIPLIER_HEX = 'bcbb3b3f'

local function u32(s,o)
    if not s or o<0 or o+4>#s then return nil end
    local a,b,c,d=s:byte(o+1,o+4)
    return a+b*256+c*65536+d*16777216
end
local function pack32(v)
    return string.char(v%256,math.floor(v/256)%256,math.floor(v/65536)%256,math.floor(v/16777216)%256)
end
local function replace(s,o,b) return s:sub(1,o)..b..s:sub(o+#b+1) end
local function unhex(s) return (s:gsub('..',function(h) return string.char(tonumber(h,16)) end)) end
local DAMAGE_SIGNATURE = unhex(DAMAGE_SIGNATURE_HEX)
local MAGAZINE_SIGNATURE = unhex(MAGAZINE_SIGNATURE_HEX)
local ACID_DURATION_SIGNATURE = unhex(ACID_DURATION_SIGNATURE_HEX)
local HELLDIVER_HEALTH_SIGNATURE = unhex(HELLDIVER_HEALTH_SIGNATURE_HEX)
local PLAYER_GAS_MULTIPLIER = unhex(PLAYER_GAS_MULTIPLIER_HEX)

local DAMAGE_STATUS_OFFSET = 2304 + 44
local GAS_DOT_OFFSET = 40152
local HELLDIVER_ELEMENT_DAMAGE_OFFSET = 21500
local HELLDIVER_GAS_ELEMENT = 5
local FLAG_DAMAGE_OFFSET = 41980
local SAI_DAMAGE_OFFSET = 4208
local AR11_DAMAGE_OFFSET = 10592
local AR11_STAGGER_OFFSET = 12672
local ARC_DAMAGE_OFFSET = 15072

local ARC_V09_STATUS = 'Applied: ARC-3 range 55 -> 40 m; charge 1.0/1.1/1.2 -> 0.20/0.22/0.24 s; damage 250/100 -> 163/65; Stun Medium buildup 8 -> 0.8; demolition/force strength/impulse 20/35/10 -> 4/25/2; camera climb 1.0/1.0 -> 0.4/0.4.'
local ARC_V10_STATUS='Applied: ARC-3 range 55 -> 45 m; charge 1.0/1.1/1.2 -> 0.307692/0.338462/0.369231 s; damage 250/100 -> 226/90; Stun Medium buildup 8 -> 0.8; demolition/force strength/impulse 20/35/10 -> 4/25/2; camera climb 1.0/1.0 -> 0.4/0.4.'
local ARC_V11_STATUS='Applied: ARC-3 range 55 -> 45 m; charge 1.0/1.1/1.2 -> 0.307692/0.338462/0.369231 s; damage 250/100 -> 226/90; Stun Medium buildup 8 -> 1.2; demolition/force strength/impulse 20/35/10 -> 4/25/2; camera climb 1.0/1.0 -> 0.4/0.4.'

local function peer_damage(state,kind)
    if not state or not state.active then return nil end
    if kind=='flag' then
        local normal,durable=state.status:match('^Applied: flag damage 200 %-> (%d+); durable damage 100 %-> (%d+)%.?$')
        normal,durable=tonumber(normal),tonumber(durable)
        assert(normal and durable,'Flag companion status is not a supported v0.9 result')
        return normal,durable
    end
    if kind=='ar11' then
        assert(state.status=='Applied: AR-11 rifle damage 70 -> 80; rifle magazine 45 -> 65; underbarrel magazine remains 4 and reserve ammo 20 -> 30; stagger 20 -> 25 with push force 20 unchanged; ergonomics 29 -> 40 with the default optic.','AR-11 companion status is not a supported v0.2 result')
        return 80,25
    end
    local normal,durable=state.status:match('^Applied: SAI normal damage 80 %-> (%d+); durable damage 4 %-> (%d+); Focus Lens spread 75 %-> 0%.5 MRAD on both axes%.?$')
    normal,durable=tonumber(normal),tonumber(durable)
    assert(normal and durable,'SAI companion status is not a supported v0.4 result')
    return normal,durable
end

local function peer_arc(state)
    if not state or not state.active then return false end
    if state.version=='0.9' and state.status==ARC_V09_STATUS then return 163,65,'cdcc4c3f' end
    if state.version=='0.10' and state.status==ARC_V10_STATUS then return 226,90,'cdcc4c3f' end
    if state.version=='0.11' and state.status==ARC_V11_STATUS then return 226,90,'9a99993f' end
    error('ARC-3 companion status is not a supported v0.9/v0.10/v0.11 result')
end

local function validate_damage(api,address)
    if not api.writable(address,DAMAGE_SIZE) then return nil,'damage table is not writable private data' end
    local s=api.read(address,DAMAGE_SIZE)
    if not s or #s~=DAMAGE_SIZE or u32(s,0)~=2 then return nil,'damage table layout mismatch' end
    for _,h in ipairs({{4,3943969754,32},{60,3769052400,49340}}) do
        if u32(s,h[1])~=0x444c444c or u32(s,h[1]+4)~=1 or u32(s,h[1]+8)~=h[2]
          or u32(s,h[1]+12)~=h[3] or u32(s,h[1]+16)~=1 or u32(s,h[1]+20)~=0 then
            return nil,'damage table header mismatch'
        end
    end
    if u32(s,92)~=DAMAGE_ROWS or u32(s,96)~=0 then return nil,'damage row count mismatch' end
    local data=api.pointer(s,84)
    if not data or api.distance(data,address)~=100 then return nil,'damage row pointer mismatch' end
    if s:sub(2305,2380)~=DAMAGE_SIGNATURE then return nil,'Sterilizer attack record mismatch' end
    if u32(s,GAS_DOT_OFFSET)~=532 or u32(s,GAS_DOT_OFFSET+4)~=25 or u32(s,GAS_DOT_OFFSET+8)~=25 then
        return nil,'Gas MKII damage record mismatch'
    end

    local normalized=s
    local flag=rawget(_G,'FlagDamagePrototypeV1')
    local flag_normal,flag_durable=peer_damage(flag,'flag')
    local expected_flag_normal,expected_flag_durable=flag_normal or 200,flag_durable or 100
    if u32(s,FLAG_DAMAGE_OFFSET)~=expected_flag_normal or u32(s,FLAG_DAMAGE_OFFSET+4)~=expected_flag_durable then
        return nil,'Flag companion values mismatch'
    end
    if flag_normal then normalized=replace(normalized,FLAG_DAMAGE_OFFSET,pack32(200)..pack32(100)) end

    local sai=rawget(_G,'SaiFocusModV1')
    local sai_normal,sai_durable=peer_damage(sai,'sai')
    local expected_sai_normal,expected_sai_durable=sai_normal or 80,sai_durable or 4
    if u32(s,SAI_DAMAGE_OFFSET)~=expected_sai_normal or u32(s,SAI_DAMAGE_OFFSET+4)~=expected_sai_durable then
        return nil,'SAI companion values mismatch'
    end
    if sai_normal then normalized=replace(normalized,SAI_DAMAGE_OFFSET,pack32(80)..pack32(4)) end

    local ar11=rawget(_G,'AR11ArbitratorModV1')
    local ar11_damage,ar11_stagger=peer_damage(ar11,'ar11')
    if u32(s,AR11_DAMAGE_OFFSET)~=(ar11_damage or 70) or u32(s,AR11_STAGGER_OFFSET)~=(ar11_stagger or 20) then
        return nil,'AR-11 companion values mismatch'
    end
    if ar11_damage then
        normalized=replace(normalized,AR11_DAMAGE_OFFSET,pack32(70))
        normalized=replace(normalized,AR11_STAGGER_OFFSET,pack32(20))
    end

    local arc=rawget(_G,'RapidArcThrowerV1')
    local arc_normal,arc_durable,arc_buildup=peer_arc(arc)
    if u32(s,ARC_DAMAGE_OFFSET)~=197 or u32(s,ARC_DAMAGE_OFFSET+44)~=37 then
        return nil,'ARC-3 damage record identity mismatch'
    end
    if arc_normal then
        if u32(s,ARC_DAMAGE_OFFSET+4)~=arc_normal or u32(s,ARC_DAMAGE_OFFSET+8)~=arc_durable
          or u32(s,ARC_DAMAGE_OFFSET+28)~=4 or u32(s,ARC_DAMAGE_OFFSET+32)~=25
          or u32(s,ARC_DAMAGE_OFFSET+36)~=2
          or s:sub(ARC_DAMAGE_OFFSET+49,ARC_DAMAGE_OFFSET+52)~=unhex(arc_buildup) then
            return nil,'ARC-3 companion values mismatch'
        end
        normalized=replace(normalized,ARC_DAMAGE_OFFSET+4,pack32(250)..pack32(100))
        normalized=replace(normalized,ARC_DAMAGE_OFFSET+28,pack32(20)..pack32(35)..pack32(10))
        normalized=replace(normalized,ARC_DAMAGE_OFFSET+48,unhex('00000041'))
    end

    if api.sha256(normalized:sub(101))~=DAMAGE_SHA then return nil,'damage rows checksum mismatch' end
    local desired_statuses=unhex('2b0000000000403f2d0000000000403f370000000000803f0000000000000000')
    return {address=address,size=DAMAGE_SIZE,source=s,writes={
        {offset=DAMAGE_STATUS_OFFSET,bytes=desired_statuses,write='normal'},
        {offset=GAS_DOT_OFFSET+4,bytes=pack32(45)..pack32(45),write='normal'},
    }}
end

local function validate_magazine(api,address)
    if not api.data_access(address,MAGAZINE_SIZE) then return nil,'magazine record permissions unsupported' end
    if api.writable(address,MAGAZINE_SIZE) then return nil,'writable signature copy; not the read-only game table' end
    local s=api.read(address,MAGAZINE_SIZE)
    if not s or #s~=MAGAZINE_SIZE or s~=MAGAZINE_SIGNATURE then return nil,'Sterilizer magazine record mismatch' end
    if u32(s,136)~=125 or u32(s,140)~=3 or u32(s,144)~=6 or u32(s,148)~=4 then
        return nil,'Sterilizer magazine values mismatch'
    end
    return {address=address,size=MAGAZINE_SIZE,source=s,writes={{offset=136,bytes=pack32(175),write='protected'}}}
end

local function validate_acid_status(api,address)
    if not api.data_access(address,ACID_STATUS_SIZE) then return nil,'Acid Storm status record permissions unsupported' end

    local s=api.read(address,ACID_STATUS_SIZE)
    if not s or #s~=ACID_STATUS_SIZE or u32(s,0)~=55 then return nil,'Acid Storm status record mismatch' end
    if s:sub(17,44)~=ACID_DURATION_SIGNATURE then return nil,'Acid Storm status fields mismatch' end
    if u32(s,44)~=0 or s:byte(49)~=0 or s:sub(57,97)~=string.rep('\0',41) then
        return nil,'Acid Storm status payload mismatch'
    end
    if s:sub(41,44)~=unhex('0000803f') then return nil,'Acid Storm duration is not the expected 1 second' end
    return {address=address,size=ACID_STATUS_SIZE,source=s,writes={{offset=40,bytes=unhex('00007041'),write='protected'}}}
end

local function validate_helldiver_health(api,address)
    if not api.data_access(address,HELLDIVER_HEALTH_SIZE) then return nil,'Helldiver health record permissions unsupported' end
    if api.writable(address,HELLDIVER_HEALTH_SIZE) then return nil,'writable signature copy; not the read-only Helldiver health record' end
    local s=api.read(address,HELLDIVER_HEALTH_SIZE)
    if not s or #s~=HELLDIVER_HEALTH_SIZE or s:sub(1,#HELLDIVER_HEALTH_SIGNATURE)~=HELLDIVER_HEALTH_SIGNATURE then
        return nil,'Helldiver health record signature mismatch'
    end
    if api.sha256(s)~=HELLDIVER_HEALTH_SHA then return nil,'Helldiver health record checksum mismatch' end

    local gas_offset=nil
    for i=0,3 do
        local element_offset=HELLDIVER_ELEMENT_DAMAGE_OFFSET+i*8
        if u32(s,element_offset)==HELLDIVER_GAS_ELEMENT then
            if gas_offset then return nil,'duplicate Gas element in Helldiver health record' end
            gas_offset=element_offset
        end
    end
    if not gas_offset or s:sub(gas_offset+5,gas_offset+8)~=unhex('6666a63f') then
        return nil,'Helldiver Gas damage multiplier mismatch'
    end
    return {address=address,size=HELLDIVER_HEALTH_SIZE,source=s,writes={
        {offset=gas_offset+4,bytes=PLAYER_GAS_MULTIPLIER,write='protected'},
    }}
end

local function validate_one(api,addresses,validator,kind)
    local plans,seen={},{}
    for _,address in ipairs(addresses) do
        local key=api.identity(address)
        if not seen[key] then
            seen[key]=true
            local plan,reason=validator(api,address)
            if api.note then api.note(kind..' address='..string.format('%.0f',key)..': '..(reason or 'validated')) end
            if plan then plans[#plans+1]=plan end
        end
    end
    assert(#plans==1,'Expected one supported '..kind..' record; found '..#plans..'. No edit applied.')
    return plans[1]
end
local function find_damage(api,module)
    return validate_one(api,api.candidates(module,DAMAGE_SIGNATURE,2304),validate_damage,'damage')
end

local function apply_plan(api,p)
    for _,edit in ipairs(p.writes) do
        local before=api.read(p.address,p.size)
        assert(before and #before==p.size and before==p.current,'Data changed before write')
        local expected=replace(before,edit.offset,edit.bytes)
        p.attempted[#p.attempted+1]={offset=edit.offset,bytes=edit.bytes,before=before,writer=edit.write}
        local write=edit.write=='protected' and api.write_protected or api.write
        assert(write(p.address+edit.offset,edit.bytes),'Data write was incomplete')
        assert(api.read(p.address,p.size)==expected,'Full record verification failed')
        p.current=expected
    end
end

function patch.apply(api,module)
    local ok,result=pcall(function()
        local plans={
            find_damage(api,module),
        }
        local record_addresses=api.record_candidates(module)
        plans[#plans+1]=validate_one(api,record_addresses[1],validate_magazine,'magazine')
        plans[#plans+1]=validate_one(api,record_addresses[2],validate_acid_status,'acid status')
        plans[#plans+1]=validate_one(api,record_addresses[3],validate_helldiver_health,'Helldiver health')
        for _,p in ipairs(plans) do
            assert(api.read(p.address,p.size)==p.source,'Data changed during discovery. No edit applied.')
            p.attempted={}
            p.current=p.source
        end
        local success,reason=pcall(function()
            for _,p in ipairs(plans) do apply_plan(api,p) end
        end)
        if not success then
            local restored=true
            for pi=#plans,1,-1 do
                local p=plans[pi]
                for wi=#p.attempted,1,-1 do
                    local edit=p.attempted[wi]
                    local current=api.read(p.address,p.size)
                    local baseline=edit.before
                    local start=edit.offset+1
                    local finish=edit.offset+#edit.bytes
                    local owned=current and #current==p.size
                      and current:sub(1,start-1)==baseline:sub(1,start-1)
                      and current:sub(finish+1)==baseline:sub(finish+1)
                    if owned then
                        for n=1,#edit.bytes do
                            local value=current:byte(edit.offset+n)
                            local old=baseline:byte(edit.offset+n)
                            local new=edit.bytes:byte(n)
                            if value~=old and value~=new then owned=false;break end
                        end
                    end
                    if owned then
                        local write=edit.writer=='protected' and api.write_protected or api.write
                        restored=(write(p.address+edit.offset,baseline:sub(start,finish))
                          and api.read(p.address,p.size)==baseline) and restored
                    else restored=false end
                end
            end
            error(tostring(reason)..'; restored='..tostring(restored))
        end
        return 'Applied: TX-41 Sterilizer gas 25 -> 45 DPS; Helldiver incoming Gas multiplier 1.3 -> 0.7333; magazine 125 -> 175; Gas MKII / confusion buildup 0.5 -> 0.75; Acid Storm armor reduction added and duration 1 -> 15 seconds.'
    end)
    return ok,tostring(result)
end

return patch

end)()
local start=(function()
return function(make_api,patch)
    if rawget(_G,'SterilizerArmorControlV1') then return end
    local state={version='0.8',active=false,status='Waiting for first game update',scanned=0,candidates=0,diagnostics={}}
    _G.SterilizerArmorControlV1=state
    local previous=update
    local callback
    local function log()
        pcall(function()
            local logger=rawget(_G,'CowboyBingusModLoader')
            local file=logger and logger.open_log and logger.open_log('SterilizerArmorControl.log')
            if file then
                file:write('SterilizerArmorControl v0.8\nstatus='..state.status..'\nscanned_bytes='..state.scanned..'\ncandidates='..state.candidates..'\n'..table.concat(state.diagnostics,'\n')..'\n')
                file:close()
            end
        end)
    end
    local deadline=0
    local logged_mb=-1
    local worker=coroutine.create(function()
        local api=make_api()
        api.note=function(message)
            if #state.diagnostics>=16 then table.remove(state.diagnostics,1) end
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

        state.status='Waiting for game data and companion mods to initialize'
        log()
        local ready_at=api.now()+30000
        repeat coroutine.yield() until api.now()>=ready_at
        local peer_deadline=api.now()+120000
        while true do
            local flag=rawget(_G,'FlagDamagePrototypeV1')
            local sai=rawget(_G,'SaiFocusModV1')
            local ar11=rawget(_G,'AR11ArbitratorModV1')
            local arc=rawget(_G,'RapidArcThrowerV1')
            local pending=(flag and not flag.active) or (sai and not sai.active)
                or (ar11 and not ar11.active) or (arc and not arc.active)
            if not pending then break end
            assert(api.now()<peer_deadline,'An installed optional companion mod did not finish initialization. No edit applied.')
            state.status='Waiting for optional Flag/SAI/AR-11/ARC-3 table edits'
            coroutine.yield()
        end

        for attempt=1,6 do
            state.status='Validating Sterilizer data; attempt '..attempt..'/6'
            log()
            local applied,reason=patch.apply(api,game)
            if applied then return reason end
            if not reason:find('found 0. No edit applied.',1,true) or attempt==6 then error(reason) end
            state.status='Sterilizer data not ready; retrying after loading'
            local until_time=api.now()+10000
            repeat coroutine.yield() until api.now()>=until_time
        end
    end)
    local function init()
        if coroutine.status(worker)=='dead' then return end
        deadline=os.clock()+0.0007
        local ok,message=coroutine.resume(worker)
        if not ok or coroutine.status(worker)=='dead' then
            state.active,state.status=ok,tostring(message)
            print('[SterilizerArmorControl] '..state.status)
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
