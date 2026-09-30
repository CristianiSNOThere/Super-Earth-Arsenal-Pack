-- HD2-Addon: mods/codex/ar11_arbitrator
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
        } AR11ArbitratorMemoryInfoV1;
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
        local info=ffi.new('AR11ArbitratorMemoryInfoV1[1]')
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
        local info=ffi.new('AR11ArbitratorMemoryInfoV1[1]')
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
    function api.write_attachment(p,s)
        assert(#s==8,'Only the two spread floats may be written')
        local info=ffi.new('AR11ArbitratorMemoryInfoV1[1]')
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

    function api.private_write(p,s)
        assert(#s==4 or #s==8,'Only validated 4-byte fields or one 8-byte pair may be written')
        local info=ffi.new('SaiFocusMemoryInfoV1[1]')
        if k.VirtualQuery(p,ffi.cast('void *',info),ffi.sizeof(info[0]))~=ffi.sizeof(info[0]) then return false end
        if info[0].kind~=0x20000 or not api.data_access(p,#s)
            or api.distance(p,info[0].base)+#s>tonumber(info[0].size) then return false end
        local old=tonumber(info[0].protection)
        if old==4 then return api.write(p,s) end
        if old~=2 then return false end
        local previous,ignored=ffi.new('uint32_t[1]'),ffi.new('uint32_t[1]')
        if k.VirtualProtect(p,#s,4,previous)==0 then return false end
        local ok,result=pcall(api.write,p,s)
        local restored=k.VirtualProtect(p,#s,previous[0],ignored)~=0
        assert(restored,'Private data page protection restoration failed')
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
        local info=ffi.new('AR11ArbitratorMemoryInfoV1[1]')
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

    function api.scan_private_many(items,include_readonly)
        assert(type(items)=='table' and #items>0,'Invalid private-data signatures')
        local max_length=0
        for _,item in ipairs(items) do
            assert(type(item.signature)=='string' and #item.signature>=8 and #item.signature<=256,
                'Invalid private-data signature')
            max_length=math.max(max_length,#item.signature)
        end
        local regions=api.private_regions(include_readonly)
        local total,scanned,matches=0,0,0
        local results,seen={},{}
        for _,region in ipairs(regions) do total=total+region.size end
        assert(total<=8589934592,'Private-data scan exceeds 8 GiB bounds. No edit applied.')
        for _,item in ipairs(items) do results[item.key]={};seen[item.key]={} end
        for _,region in ipairs(regions) do
            local tail=''
            for offset=0,region.size-1,65536 do
                local length=math.min(65536,region.size-offset)
                local data=api.read(region.base+offset,length)
                if data then
                    local block=tail..data
                    for _,item in ipairs(items) do
                        local from=1
                        while true do
                            local at=block:find(item.signature,from,true)
                            if not at then break end
                            matches=matches+1
                            local address=region.base+offset-#tail+at-1-(item.row_offset or 0)
                            local key=api.identity(address)
                            if not seen[item.key][key] then
                                seen[item.key][key]=true
                                results[item.key][#results[item.key]+1]=address
                            end
                            from=at+1
                        end
                    end
                    if max_length>1 then tail=block:sub(-(max_length-1)) else tail='' end
                else
                    tail=''
                end
                scanned=scanned+length
                if api.progress then api.progress(scanned,total,matches) end
                if api.checkpoint then api.checkpoint('Searching private data for AR-11 component tables') end
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

local DAMAGE_SIZE, DAMAGE_COUNT, DAMAGE_STRIDE = 49424, 649, 76
local DAMAGE_SIGNATURE_HEX = '850000004600000014000000020000000200000002000000000000000a0000000f0000000c000000000000000000000000000000000000000000000000000000000000000000000000000000'
local STOCK_AR11_DAMAGE = '850000004600000014000000020000000200000002000000000000000a0000000f0000000c000000000000000000000000000000000000000000000000000000000000000000000000000000'
local STOCK_UNDERBARREL_DAMAGE = 'a1000000320000000c000000030000000300000003000000000000000a0000001400000014000000000000000000000000000000000000000000000000000000000000000000000000000000'
local ENTITY_CONFIGS = {
    {
        label='AR-11 ergonomics',
        signature='b1dbe4884c444c4401000000b1dbe488000f07000100000000000000',
        wrapper=0x88e4dbb1, group_size=462592,
        map_count=730, data_offset=11680, record_count=366, stride=1232,
        resource_lo=0x4892b6b2, resource_hi=0xa8a91eb5, expected_index=280,
        field_offset=356,
        before='0000f041', after='00002442',
    },
    {
        label='AR-11 magazine capacity',
        signature='a3888dfb4c444c4401000000a3888dfb20cb00000100000000000000',
        wrapper=0xfb8d88a3, group_size=52000,
        map_count=540, data_offset=8640, record_count=271, stride=160,
        resource_lo=0x4892b6b2, resource_hi=0xa8a91eb5, expected_index=211,
        field_offset=136,
        before='2d000000', after='41000000',
    },
    {
        label='AR-11 underbarrel spare ammo',
        signature='721008664c444c440100000072100866f01000000100000000000000',
        wrapper=0x66081072, group_size=4336,
        map_count=50, data_offset=800, record_count=26, stride=136,
        resource_lo=0xf99b5335, resource_hi=0xb9c209b4, expected_index=14,
        field_offset=80,
        before='14000000', after='1e000000',
        guard_span='0000804000000000',
        guard_offset=72,
        extra_changes={
            {field_offset=88,before='14000000',after='1e000000'},
        },
    },
}

local function unhex(s)
    return (s:gsub('..', function(h) return string.char(tonumber(h, 16)) end))
end
local function u32(s, o)
    if not s or o < 0 or o + 4 > #s then return nil end
    local a,b,c,d = s:byte(o+1,o+4)
    return a+b*256+c*65536+d*16777216
end
local function set(s, o, b)
    return s:sub(1,o)..b..s:sub(o+#b+1)
end
local function pack32(v)
    return string.char(v%256,math.floor(v/256)%256,math.floor(v/65536)%256,math.floor(v/16777216)%256)
end

local function damage_plan(api, module)
    local addresses = api.candidates(module, unhex(DAMAGE_SIGNATURE_HEX), 10588, nil)
    if #addresses == 0 then return nil, 'not-ready' end
    local plans, seen = {}, {}
    for _, address in ipairs(addresses) do
        local identity = api.identity(address)
        if not seen[identity] then
            seen[identity] = true
            if api.writable(address, DAMAGE_SIZE) then
                local s = api.read(address, DAMAGE_SIZE)
                if s and #s == DAMAGE_SIZE and u32(s,0) == 2
                    and u32(s,4) == 0x444c444c and u32(s,8) == 1
                    and u32(s,12) == 3943969754 and u32(s,16) == 32
                    and u32(s,20) == 1 and u32(s,24) == 0
                    and u32(s,60) == 0x444c444c and u32(s,64) == 1
                    and u32(s,68) == 3769052400 and u32(s,72) == 49340
                    and u32(s,76) == 1 and u32(s,80) == 0
                    and u32(s,92) == DAMAGE_COUNT and u32(s,96) == 0 then
                    local pointer = api.pointer(s,84)
                    if pointer and api.distance(pointer,address) == 100 then
                        local ids, positions = {}, {}
                        local unique = true
                        for i=0,DAMAGE_COUNT-1 do
                            local o=100+i*DAMAGE_STRIDE
                            local kind=u32(s,o)
                            if not kind or ids[kind] then unique=false;break end
                            ids[kind]=true
                            if kind==133 or kind==161 then positions[kind]=o end
                        end
                        if unique and positions[133]==10588 and positions[161]==12640
                            and s:sub(10589,10664)==unhex(STOCK_AR11_DAMAGE)
                            and s:sub(12641,12716)==unhex(STOCK_UNDERBARREL_DAMAGE) then
                            plans[#plans+1]={
                                label='AR-11 damage settings',
                                address=address,size=DAMAGE_SIZE,source=s,writer=api.write,
                                changes={
                                    {offset=positions[133]+4,before=pack32(70),after=pack32(80)},
                                    {offset=positions[161]+32,before=pack32(20),after=pack32(25)},
                                },
                            }
                        end
                    end
                end
            end
        end
    end
    if #plans ~= 1 then
        if #plans == 0 then return nil, 'damage-validation' end
        error('Expected one AR-11 damage table; found '..#plans..'. No edit applied.')
    end
    return plans[1]
end

local function entity_plan(api, address, config)
    local header=unhex(config.signature)
    local total=28+config.group_size
    if not api.data_access(address,total) then return nil,'component memory permissions unsupported' end
    local s=api.read(address,total)
    if not s or #s~=total then return nil,'component table read failed' end
    if s:sub(1,28)~=header or u32(s,0)~=config.wrapper
        or s:sub(5,8)~='LDLD' or u32(s,8)~=1
        or u32(s,12)~=config.wrapper or u32(s,16)~=config.group_size
        or u32(s,20)~=1 or u32(s,24)~=0 then return nil,'component header mismatch' end
    if config.data_offset~=config.map_count*16
        or config.group_size~=config.data_offset+config.record_count*config.stride then
        return nil,'component layout constants are inconsistent'
    end
    local found,index=0,nil
    for i=0,config.map_count-1 do
        local o=28+i*16
        local lo,hi=u32(s,o),u32(s,o+4)
        if lo==nil or hi==nil then return nil,'component map truncated' end
        if lo==config.resource_lo and hi==config.resource_hi then
            found=found+1
            index=u32(s,o+8)
        end
    end
    if found~=1 or index~=config.expected_index then return nil,'AR-11 resource mapping mismatch' end
    local record=28+config.data_offset+index*config.stride
    local function checked_change(member_offset,before_hex,after_hex)
        local field=record+member_offset
        local before,after=unhex(before_hex),unhex(after_hex)
        if field<28 or field+#before>total then return nil,'AR-11 field lies outside component table' end
        if #before~=#after or s:sub(field+1,field+#before)~=before then return nil,'AR-11 stock value mismatch' end
        return {offset=field,before=before,after=after}
    end
    local changes={}
    local main_change,change_reason=checked_change(config.field_offset,config.before,config.after)
    if not main_change then return nil,change_reason end
    changes[#changes+1]=main_change
    for _,extra in ipairs(config.extra_changes or {}) do
        local change,reason=checked_change(extra.field_offset,extra.before,extra.after)
        if not change then return nil,reason end
        changes[#changes+1]=change
    end
    if config.guard_span then
        local guard=record+config.guard_offset
        local span=unhex(config.guard_span)
        if guard<28 or guard+#span>total or s:sub(guard+1,guard+#span)~=span then
            return nil,'AR-11 magazine-capacity layout mismatch'
        end
    end
    return {
        label=config.label,address=address,size=total,source=s,writer=api.private_write,
        changes=changes,
    }
end

local function entity_plans(api,module)
    local items={}
    for i,config in ipairs(ENTITY_CONFIGS) do
        local header=unhex(config.signature)
        items[i]={signature=header,row_offset=0,key=i}
    end
    local addresses,seen={},{}
    -- Follow module-owned references when available, then scan private read-only
    -- and writable memory once to find relocated copies.
    for i,config in ipairs(ENTITY_CONFIGS) do
        local header=unhex(config.signature):sub(1,16)
        for _,address in ipairs(api.candidates(module,nil,0,header)) do
            local key=api.identity(address)
            if not seen[i..':'..key] then
                seen[i..':'..key]=true
                addresses[i]=addresses[i] or {}
                addresses[i][#addresses[i]+1]=address
            end
        end
    end
    local private=api.scan_private_many(items,true)
    for i,list in ipairs(private) do
        for _,address in ipairs(list) do
            local key=api.identity(address)
            if not seen[i..':'..key] then
                seen[i..':'..key]=true
                addresses[i]=addresses[i] or {}
                addresses[i][#addresses[i]+1]=address
            end
        end
    end
    local plans={}
    for i,config in ipairs(ENTITY_CONFIGS) do
        local valid={}
        for _,address in ipairs(addresses[i] or {}) do
            local plan=entity_plan(api,address,config)
            if plan then valid[#valid+1]=plan end
        end
        if #valid==0 then return nil,'not-ready' end
        if #valid~=1 then error('Expected one supported '..config.label..' table; found '..#valid..'. No edit applied.') end
        plans[#plans+1]=valid[1]
    end
    return plans
end

local function expected_after(plan)
    local result=plan.source
    for _,change in ipairs(plan.changes) do result=set(result,change.offset,change.after) end
    return result
end

local function apply_transaction(api, plans)
    for _,plan in ipairs(plans) do
        assert(api.read(plan.address,plan.size)==plan.source,plan.label..' changed before commit. No edit applied.')
        for _,change in ipairs(plan.changes) do
            assert(api.read(plan.address+change.offset,#change.before)==change.before,
                plan.label..' target changed before commit. No edit applied.')
        end
    end
    local attempted={}
    local ok,reason=pcall(function()
        for _,plan in ipairs(plans) do
            for _,change in ipairs(plan.changes) do
                attempted[#attempted+1]={plan=plan,change=change}
                assert(plan.writer(plan.address+change.offset,change.after),plan.label..' write was incomplete')
            end
        end
        for _,plan in ipairs(plans) do
            assert(api.read(plan.address,plan.size)==expected_after(plan),
                plan.label..' full-table verification failed')
        end
    end)
    if not ok then
        local restored=true
        for i=#attempted,1,-1 do
            local item=attempted[i]
            local current=api.read(item.plan.address+item.change.offset,#item.change.after)
            if current==item.change.after then
                local ok_write=item.plan.writer(item.plan.address+item.change.offset,item.change.before)
                if not ok_write then restored=false end
            elseif current~=item.change.before then
                restored=false
            end
        end
        for _,plan in ipairs(plans) do
            if api.read(plan.address,plan.size)~=plan.source then restored=false end
        end
        error(tostring(reason)..'; restored='..tostring(restored))
    end
end

function patch.apply(api,module)
    local ok,result=pcall(function()
        local damage,reason=damage_plan(api,module)
        if not damage then
            if reason=='not-ready' then error('AR11_DATA_NOT_READY',0) end
            error('AR-11 damage table validation failed. No edit applied.')
        end
        local entities,entity_reason=entity_plans(api,module)
        if not entities then
            if entity_reason=='not-ready' then error('AR11_DATA_NOT_READY',0) end
            error('AR-11 component table validation failed. No edit applied.')
        end
        local plans={damage}
        for _,plan in ipairs(entities) do plans[#plans+1]=plan end
        apply_transaction(api,plans)
        return 'Applied: AR-11 rifle damage 70 -> 80; rifle magazine 45 -> 65; underbarrel magazine remains 4 and reserve ammo 20 -> 30; stagger 20 -> 25 with push force 20 unchanged; ergonomics 29 -> 40 with the default optic.'
    end)
    if not ok and tostring(result)=='AR11_DATA_NOT_READY' then return false,'AR11_DATA_NOT_READY' end
    return ok,tostring(result)
end

return patch

end)()
local start=(function()
return function(make_api,patch)
    if rawget(_G,'AR11ArbitratorModV1') then return end
    local state={
        version='0.2',active=false,status='Waiting for first game update',
        scanned=0,candidates=0,diagnostics={}
    }
    _G.AR11ArbitratorModV1=state
    local previous=update
    local callback
    local function log()
        pcall(function()
            local logger=rawget(_G,'CowboyBingusModLoader')
            local file=logger and logger.open_log and logger.open_log('AR11ArbitratorMod.log')
            if file then
                file:write(
                    'AR11ArbitratorMod v0.2\nstatus='..state.status..
                    '\nscanned_bytes='..state.scanned..
                    '\ncandidates='..state.candidates..
                    '\n'..table.concat(state.diagnostics,'\n')..'\n'
                )
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
        assert(api.module_hash(exe)=='F5FEE03DCFDB2E553A4752C283590950AC13316B376D8196AA556FF0400D5F06',
            'Unsupported executable. No edit applied.')
        assert(api.module_hash(game)=='2E2C3B7C2500646DADD5F2B4C6E0504DBB7E7896139F64CDDC0D1813C718F51E',
            'Unsupported game module. No edit applied.')

        state.status='Waiting for game data to load'
        log()
        local load_until=api.now()+15000
        repeat coroutine.yield() until api.now()>=load_until

        for attempt=1,8 do
            local applied,reason=patch.apply(api,game)
            if applied then return reason end
            local not_ready=reason=='AR11_DATA_NOT_READY'
            local stale=reason:find('changed before commit',1,true)~=nil
                or reason:find('target changed before commit',1,true)~=nil
            local restored_conflict=reason:find('full-table verification failed',1,true)~=nil
                and reason:find('restored=true',1,true)~=nil
            if not not_ready and not stale and not restored_conflict or attempt==8 then error(reason) end
            state.status=(stale or restored_conflict)
                and 'Shared table changed during AR-11 setup; retrying safely'
                or 'AR-11 data not ready; retrying after loading'
            log()
            local until_time=api.now()+(not_ready and 10000 or 3000)
            repeat coroutine.yield() until api.now()>=until_time
        end
    end)
    local function init()
        if coroutine.status(worker)=='dead' then return end
        deadline=os.clock()+0.0007
        local ok,message=coroutine.resume(worker)
        if not ok or coroutine.status(worker)=='dead' then
            state.active,state.status=ok,tostring(message)
            print('[AR11ArbitratorMod] '..state.status)
            log()
            if update==callback then update=previous or function() end end
        end
    end
    local function finish(...)
        init()
        return ...
    end
    callback=function(...)
        if previous then return finish(previous(...)) end
        init()
    end
    update=callback
    log()
end

end)()
start(make_api,patch)
