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
        local info=ffi.new('SaiFocusMemoryInfoV1[1]')
        local cursor=ffi.cast('uint8_t *',65536)
        while ffi.cast('uintptr_t',cursor)<0x800000000000 do
            if k.VirtualQuery(cursor,ffi.cast('void *',info),ffi.sizeof(info[0]))~=ffi.sizeof(info[0]) then break end
            local size=tonumber(info[0].size)
            local next_address=ffi.cast('uint8_t *',info[0].base)+size
            assert(size>0 and next_address>cursor,'Invalid memory-region layout')
            if info[0].state==0x1000 and info[0].kind==0x20000 and (info[0].protection==4 or (include_readonly and info[0].protection==2)) then
                regions[#regions+1]={base=ffi.cast('uint8_t *',info[0].base),size=size}
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
local validate=(function()

local patch={}
local function u32(s,o)
    if not s or o<0 or o+4>#s then return nil end
    local a,b,c,d=s:byte(o+1,o+4)
    return a+b*256+c*65536+d*16777216
end
local function pack(v)
    return string.char(v%256,math.floor(v/256)%256,math.floor(v/65536)%256,math.floor(v/16777216)%256)
end
local function replace(s,o,b) return s:sub(1,o)..b..s:sub(o+#b+1) end
local function unhex(s) return (s:gsub('..',function(h) return string.char(tonumber(h,16)) end)) end
local DAMAGE_SIGNATURE=unhex('310000005000000004000000030000000300000003000000000000000a0000000a0000000a000000000000000000000000000000000000000000000000000000000000000000000000000000')
local FOCUS_SIGNATURE=unhex('63bd3f91b5cb88a16dcd7c827321dd4d0000000000001644000000000000964200009642000000000000c0c01200000000000000120000000000000012000000000000001200000000000000120000000000000012000000000000001200000000000000')
local DELTA_HEADER=unhex('4f603e684c444c44010000004f603e68665505000100000000000000')
local DELTA_ARRAYS={ {28,108,1024},{44,16492,1122},{60,25468,1011},{76,37600,6040},{92,110080,239490} }
local AR11_DAMAGE_OFFSET=10592
local AR11_STAGGER_OFFSET=12672
local ARC_DAMAGE_OFFSET=15072
local AR11_V02_STATUS='Applied: AR-11 rifle damage 70 -> 80; rifle magazine 45 -> 65; underbarrel magazine remains 4 and reserve ammo 20 -> 30; stagger 20 -> 25 with push force 20 unchanged; ergonomics 29 -> 40 with the default optic.'
local ARC_V09_STATUS='Applied: ARC-3 range 55 -> 40 m; charge 1.0/1.1/1.2 -> 0.20/0.22/0.24 s; damage 250/100 -> 163/65; Stun Medium buildup 8 -> 0.8; demolition/force strength/impulse 20/35/10 -> 4/25/2; camera climb 1.0/1.0 -> 0.4/0.4.'
local ARC_V10_STATUS='Applied: ARC-3 range 55 -> 45 m; charge 1.0/1.1/1.2 -> 0.307692/0.338462/0.369231 s; damage 250/100 -> 226/90; Stun Medium buildup 8 -> 0.8; demolition/force strength/impulse 20/35/10 -> 4/25/2; camera climb 1.0/1.0 -> 0.4/0.4.'
local ARC_V11_STATUS='Applied: ARC-3 range 55 -> 45 m; charge 1.0/1.1/1.2 -> 0.307692/0.338462/0.369231 s; damage 250/100 -> 226/90; Stun Medium buildup 8 -> 1.2; demolition/force strength/impulse 20/35/10 -> 4/25/2; camera climb 1.0/1.0 -> 0.4/0.4.'

local function damage(api,address)
    local size=49424
    if not api.writable(address,size) then return nil,'damage data not writable' end
    local s=api.read(address,size)
    if not s or #s~=size or u32(s,0)~=2 then return nil,'damage layout mismatch' end
    for _,h in ipairs({{4,3943969754,32},{60,3769052400,49340}}) do
        if u32(s,h[1])~=0x444c444c or u32(s,h[1]+4)~=1 or u32(s,h[1]+8)~=h[2]
          or u32(s,h[1]+12)~=h[3] or u32(s,h[1]+16)~=1 or u32(s,h[1]+20)~=0 then return nil,'damage header mismatch' end
    end
    if u32(s,92)~=649 or u32(s,96)~=0 then return nil,'damage count mismatch' end
    local pointer=api.pointer(s,84)
    if not pointer or api.distance(pointer,address)~=100 then return nil,'damage pointer mismatch' end
    local normalized=s
    local peer=rawget(_G,'FlagDamagePrototypeV1')
    if peer and peer.active then
        local n,d=peer.status:match('Applied: flag damage 200 %-> (%d+); durable damage 100 %-> (%d+)%.')
        n,d=tonumber(n),tonumber(d)
        if not n or not d or u32(s,41980)~=n or u32(s,41984)~=d then return nil,'flag companion values mismatch' end
        normalized=replace(s,41980,pack(200)..pack(100))
    end

    local ar11=rawget(_G,'AR11ArbitratorModV1')
    if ar11 and ar11.active then
        if ar11.version~='0.2' or ar11.status~=AR11_V02_STATUS then
            return nil,'unsupported AR-11 companion result'
        end
        if u32(s,AR11_DAMAGE_OFFSET)~=80 or u32(s,AR11_STAGGER_OFFSET)~=25 then
            return nil,'AR-11 companion values mismatch'
        end
        normalized=replace(normalized,AR11_DAMAGE_OFFSET,pack(70))
        normalized=replace(normalized,AR11_STAGGER_OFFSET,pack(20))
    end

    local arc=rawget(_G,'RapidArcThrowerV1')
    if u32(s,ARC_DAMAGE_OFFSET)~=197 or u32(s,ARC_DAMAGE_OFFSET+44)~=37 then
        return nil,'ARC-3 damage record identity mismatch'
    end
    if arc and arc.active then
        local arc_normal,arc_durable,arc_buildup
        if arc.version=='0.9' and arc.status==ARC_V09_STATUS then arc_normal,arc_durable,arc_buildup=163,65,'cdcc4c3f'
        elseif arc.version=='0.10' and arc.status==ARC_V10_STATUS then arc_normal,arc_durable,arc_buildup=226,90,'cdcc4c3f'
        elseif arc.version=='0.11' and arc.status==ARC_V11_STATUS then arc_normal,arc_durable,arc_buildup=226,90,'9a99993f'
        else return nil,'unsupported ARC-3 companion result' end
        if u32(s,ARC_DAMAGE_OFFSET+4)~=arc_normal or u32(s,ARC_DAMAGE_OFFSET+8)~=arc_durable
          or u32(s,ARC_DAMAGE_OFFSET+28)~=4 or u32(s,ARC_DAMAGE_OFFSET+32)~=25
          or u32(s,ARC_DAMAGE_OFFSET+36)~=2
          or s:sub(ARC_DAMAGE_OFFSET+49,ARC_DAMAGE_OFFSET+52)~=unhex(arc_buildup) then
            return nil,'ARC-3 companion values mismatch'
        end
        normalized=replace(normalized,ARC_DAMAGE_OFFSET+4,pack(250)..pack(100))
        normalized=replace(normalized,ARC_DAMAGE_OFFSET+28,pack(20)..pack(35)..pack(10))
        normalized=replace(normalized,ARC_DAMAGE_OFFSET+48,unhex('00000041'))
    end

    if api.sha256(normalized:sub(101))~='7BDD751C1336E5BEA8023B5C12A6A8FC60E1EE0BF50132D6BAFDA9D44AD1F72A' then return nil,'damage rows checksum mismatch' end
    if s:sub(4205,4280)~=DAMAGE_SIGNATURE then return nil,'SAI record mismatch' end
    return {address=address,size=size,source=s,offset=4208,bytes=pack(90)..pack(21)}
end

local function focus(api,address)
    local size=349570
    if not api.data_access(address,size) then return nil,'attachment data permissions unsupported' end
    if api.read(address,28)~=DELTA_HEADER then return nil,'attachment header mismatch' end
    local s=api.read(address,size)
    if not s or #s~=size then return nil,'attachment read failed' end
    for _,a in ipairs(DELTA_ARRAYS) do
        local pointer=api.pointer(s,a[1])
        if not pointer or api.distance(pointer,address)~=a[2] or u32(s,a[1]+8)~=a[3] or u32(s,a[1]+12)~=0 then return nil,'attachment pointer/count mismatch' end
    end
    if api.sha256(s:sub(109))~='3A394B39EE2AEEBD916179E8199F11D5F135D56C0F074694CF4E051AF70CDB85' then return nil,'attachment checksum mismatch' end
    if s:sub(181582,181681)~=FOCUS_SIGNATURE then return nil,'complete Focus Lens payload mismatch' end
    -- IEEE 754 float 0.5, horizontal and vertical. All other lens fields stay stock.
    return {address=address,size=size,source=s,offset=181609,bytes=unhex('0000003f0000003f'),attachment=true}
end

local function find(api,module,validator,signature,offset,header,label)
    local plans,seen={},{}
    local addresses
    if label=='Focus Lens' then addresses=api.scan_private(signature,181581,true)
    else addresses=api.candidates(module,signature,offset,header) end
    for _,address in ipairs(addresses) do
        local key=api.identity(address)
        if not seen[key] then
            seen[key]=true
            local plan,reason=validator(api,address)
            if api.note then api.note(label..' address='..string.format('%.0f',key)..': '..(reason or 'validated')) end
            if plan then plans[#plans+1]=plan end
        end
    end
    assert(#plans==1,'Expected one supported '..label..' table; found '..#plans..'. No edit applied.')
    return plans[1]
end

function patch.apply(api,module)
    local ok,result=pcall(function()
        local plans={find(api,module,damage,DAMAGE_SIGNATURE,4204,nil,'damage'),
          find(api,module,focus,FOCUS_SIGNATURE,181581,nil,'Focus Lens')}
        -- Discovery can yield. Recheck both complete tables before committing.
        for _,p in ipairs(plans) do
            assert(api.read(p.address,p.size)==p.source,'Data changed before edit. No edit applied.')
        end
        local attempted={}
        local applied,reason=pcall(function()
            for _,p in ipairs(plans) do
                attempted[#attempted+1]=p
                local write=p.attachment and api.write_attachment or api.write
                assert(write(p.address+p.offset,p.bytes),'Write incomplete')
            end
            for _,p in ipairs(plans) do
                assert(api.read(p.address,p.size)==replace(p.source,p.offset,p.bytes),'Full table verification failed')
            end
        end)
        if not applied then
            local restored=true
            for i=#attempted,1,-1 do
                local p=attempted[i]
                local before=p.source:sub(p.offset+1,p.offset+#p.bytes)
                local current=api.read(p.address,p.size)
                local owned=current and replace(current,p.offset,before)==p.source
                if owned then
                    for j=1,#p.bytes do
                        local b=current:byte(p.offset+j)
                        if b~=before:byte(j) and b~=p.bytes:byte(j) then owned=false end
                    end
                end
                if owned then
                    local write=p.attachment and api.write_attachment or api.write
                    restored=(write(p.address+p.offset,before) and api.read(p.address,p.size)==p.source) and restored
                else restored=false end
            end
            error(tostring(reason)..'; restored='..tostring(restored))
        end
        return 'Applied: SAI normal damage 80 -> 90; durable damage 4 -> 21; Focus Lens spread 75 -> 0.5 MRAD on both axes.'
    end)
    return ok,tostring(result)
end
return damage
end)()
local path=[====[C:/Users/crife/Desktop/HD2 Mods/work/flag-mod/filediver-master/datalibrary/generated_damage_settings.dl_bin]====]
local status09=[====[Applied: ARC-3 range 55 -> 40 m; charge 1.0/1.1/1.2 -> 0.20/0.22/0.24 s; damage 250/100 -> 163/65; Stun Medium buildup 8 -> 0.8; demolition/force strength/impulse 20/35/10 -> 4/25/2; camera climb 1.0/1.0 -> 0.4/0.4.]====]
local status11=[====[Applied: ARC-3 range 55 -> 45 m; charge 1.0/1.1/1.2 -> 0.307692/0.338462/0.369231 s; damage 250/100 -> 226/90; Stun Medium buildup 8 -> 1.2; demolition/force strength/impulse 20/35/10 -> 4/25/2; camera climb 1.0/1.0 -> 0.4/0.4.]====]
local status10=[====[Applied: ARC-3 range 55 -> 45 m; charge 1.0/1.1/1.2 -> 0.307692/0.338462/0.369231 s; damage 250/100 -> 226/90; Stun Medium buildup 8 -> 0.8; demolition/force strength/impulse 20/35/10 -> 4/25/2; camera climb 1.0/1.0 -> 0.4/0.4.]====]

local ffi=require('ffi')
local f=assert(io.open(path,'rb'));local original=f:read('*a');f:close()
local function case(version,status,n,d,reject,offset,extra)
    _G.FlagDamagePrototypeV1=nil;_G.SaiFocusModV1=nil;_G.AR11ArbitratorModV1=nil;_G.RapidArcThrowerV1=nil
    local api=make_api();local hold=ffi.new('uint8_t[?]',#original);ffi.copy(hold,original,#original)
    local p=ffi.cast('uint8_t *',hold)
    ffi.cast('uintptr_t *',p+84)[0]=ffi.cast('uintptr_t',p+100)
    local function put(o,v) ffi.cast('uint32_t *',p+o)[0]=v end
    if version then
        _G.RapidArcThrowerV1={active=true,version=version,status=status}
        put(15076,n);put(15080,d);put(15100,4);put(15104,25);put(15108,2)
        ffi.cast('float *',p+15120)[0]=(version=='0.11' and status==status11) and 1.2 or 0.8
    end
    if offset then p[offset]=bit.bxor(p[offset],1) end
    if extra then extra(put) end
    local before=api.read(p,#original)
    local ok,result,reason=pcall(validate,api,p)
    assert((ok and result~=nil)==not reject,tostring(version)..': '..tostring(result)..' '..tostring(reason))
    assert(api.read(p,#original)==before,'validator mutated fixture')
end
case(nil,nil,nil,nil,false)
case('0.9',status09,163,65,false)
case('0.10',status10,226,90,false)
case('0.11',status10,226,90,true)
case('0.10',status09,226,90,true)
case('0.10',status10,163,65,true)
case('0.9',status09,226,90,true)
for _,o in ipairs({15072,15084,15100,15104,15108,15116,15120,10000}) do case('0.10',status10,226,90,true,o) end
case('0.10',status10,226,90,false,nil,function(put)
    _G.FlagDamagePrototypeV1={active=true,status='Applied: flag damage 200 -> 300; durable damage 100 -> 150.'}
    put(41980,300);put(41984,150)
    _G.AR11ArbitratorModV1={active=true,version='0.2',status='Applied: AR-11 rifle damage 70 -> 80; rifle magazine 45 -> 65; underbarrel magazine remains 4 and reserve ammo 20 -> 30; stagger 20 -> 25 with push force 20 unchanged; ergonomics 29 -> 40 with the default optic.'}
    put(10592,80);put(12672,25)
end)

case('0.11',status11,226,90,false)
case('0.12',status11,226,90,true)
case('0.10',status11,226,90,true)
case('0.11',status11,163,65,true)
for _,o in ipairs({15072,15084,15100,15104,15108,15116,15120,10000})do case('0.11',status11,226,90,true,o)end
