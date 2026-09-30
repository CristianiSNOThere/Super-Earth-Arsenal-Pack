-- HD2-Addon: mods/codex/r40k_heat_sink
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
        } R40KHeatSinkMemoryInfoV1;
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
    function api.pack_pointer(p)
        local value=ffi.new('uintptr_t[1]')
        value[0]=ffi.cast('uintptr_t',p)
        return ffi.string(value,8)
    end
    function api.read(p,n)
        local buf,got=ffi.new('uint8_t[?]',n),ffi.new('size_t[1]')
        if k.ReadProcessMemory(self,p,buf,n,got)==0 or tonumber(got[0])~=n then return nil end
        return ffi.string(buf,n)
    end
    function api.writable(p,n)
        local info=ffi.new('R40KHeatSinkMemoryInfoV1[1]')
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
        local info=ffi.new('R40KHeatSinkMemoryInfoV1[1]')
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
        local info=ffi.new('R40KHeatSinkMemoryInfoV1[1]')
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
        local info=ffi.new('R40KHeatSinkMemoryInfoV1[1]')
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

    function api.private_write_blob(p,s)
        assert(type(s)=='string' and #s>0 and #s<=65536,'Invalid private data write')
        if not api.data_access(p,#s) then return false end
        local cursor=ffi.cast('uint8_t *',p)
        local source_offset,remaining=1,#s
        local info=ffi.new('R40KHeatSinkMemoryInfoV1[1]')
        while remaining>0 do
            if k.VirtualQuery(cursor,ffi.cast('void *',info),ffi.sizeof(info[0]))~=ffi.sizeof(info[0]) then return false end
            if info[0].state~=0x1000 or info[0].kind~=0x20000
                or (info[0].protection~=2 and info[0].protection~=4) then return false end
            local region_remaining=tonumber(info[0].size)-api.distance(cursor,info[0].base)
            if region_remaining<=0 then return false end
            local take=math.min(remaining,region_remaining)
            local piece=s:sub(source_offset,source_offset+take-1)
            local old=tonumber(info[0].protection)
            local ok,result
            if old==4 then
                ok,result=pcall(api.write,cursor,piece)
            else
                local previous,ignored=ffi.new('uint32_t[1]'),ffi.new('uint32_t[1]')
                if k.VirtualProtect(cursor,take,4,previous)==0 then return false end
                ok,result=pcall(api.write,cursor,piece)
                local restored=k.VirtualProtect(cursor,take,previous[0],ignored)~=0
                assert(restored,'Private data page protection restoration failed')
            end
            assert(ok,result)
            if not result then return false end
            cursor=cursor+take
            source_offset=source_offset+take
            remaining=remaining-take
        end
        return true
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
        local info=ffi.new('R40KHeatSinkMemoryInfoV1[1]')
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

local GAME_BUILD_EXE = 'F5FEE03DCFDB2E553A4752C283590950AC13316B376D8196AA556FF0400D5F06'
local GAME_BUILD_DLL = '2E2C3B7C2500646DADD5F2B4C6E0504DBB7E7896139F64CDDC0D1813C718F51E'
local R40K_LO, R40K_HI = 0xd26ba391, 0x1abbff60

local TABLES = {
    weapon = {
        label = 'R/40-K weapon data',
        header = 'b1dbe4884c444c4401000000b1dbe488000f07000100000000000000',
        wrapper = 0x88e4dbb1, group_size = 462592,
        map_count = 730, data_offset = 11680, record_count = 366, stride = 1232,
        used_count = 365, target_index = 302, resource_lo = R40K_LO, resource_hi = R40K_HI,
        file_offset = 26151656, ergonomics_offset = 356,
    },
    magazine = {
        label = 'R/40-K magazine data',
        header = 'a3888dfb4c444c4401000000a3888dfb20cb00000100000000000000',
        wrapper = 0xfb8d88a3, group_size = 52000,
        map_count = 540, data_offset = 8640, record_count = 271, stride = 160,
        used_count = 270, target_index = 225, resource_lo = R40K_LO, resource_hi = R40K_HI,
        file_offset = 528664, capacity_offset = 136, starting_offset = 140,
        refill_offset = 144, maximum_offset = 148,
    },
}

local function unhex(value)
    return (value:gsub('..', function(pair) return string.char(tonumber(pair, 16)) end))
end

local function u32(value, offset)
    if not value or offset < 0 or offset + 4 > #value then return nil end
    local a, b, c, d = value:byte(offset + 1, offset + 4)
    return a + b * 256 + c * 65536 + d * 16777216
end

local function pack32(value)
    return string.char(value % 256, math.floor(value / 256) % 256,
        math.floor(value / 65536) % 256, math.floor(value / 16777216) % 256)
end

local function replace(value, offset, replacement)
    return value:sub(1, offset) .. replacement .. value:sub(offset + #replacement + 1)
end

local function same_key(entry, lo, hi)
    return entry.lo == lo and entry.hi == hi
end

local function bucket(lo, hi, count)
    return ((hi % count) * (4294967296 % count) + (lo % count)) % count
end

local function read_group(api, address, config)
    local header = unhex(config.header)
    local size = 28 + config.group_size
    if config.data_offset ~= config.map_count * 16
        or config.group_size ~= config.data_offset + config.record_count * config.stride then
        return nil, 'component-table layout constants are inconsistent'
    end
    if not api.data_access(address, size) then return nil, 'component-table data permissions unsupported' end
    local source = api.read(address, size)
    if not source or #source ~= size then return nil, 'component-table read failed' end
    if source:sub(1, 28) ~= header or u32(source, 0) ~= config.wrapper
        or source:sub(5, 8) ~= 'LDLD' or u32(source, 8) ~= 1
        or u32(source, 12) ~= config.wrapper or u32(source, 16) ~= config.group_size
        or u32(source, 20) ~= 1 or u32(source, 24) ~= 0 then
        return nil, 'component-table header mismatch'
    end
    return {address = address, size = size, source = source, config = config, changes = {},
        writer = api.private_write_blob}
end

local function parse_map(group)
    local config, source = group.config, group.source
    local entries, seen_key, seen_index, count = {}, {}, {}, 0
    for slot = 0, config.map_count - 1 do
        local offset = 28 + slot * 16
        local lo, hi = u32(source, offset), u32(source, offset + 4)
        local index, padding = u32(source, offset + 8), u32(source, offset + 12)
        if lo == 0 and hi == 0 then
            if index ~= 0 or padding ~= 0 then return nil, 'empty component-map slot is malformed' end
            entries[slot] = {lo = 0, hi = 0, index = 0, padding = 0}
        else
            if padding ~= 0 or index >= config.record_count then
                return nil, 'component-map entry has an invalid index or padding'
            end
            local key = string.format('%08x%08x', hi, lo)
            if seen_key[key] or seen_index[index] then
                return nil, 'component map contains duplicate keys or records'
            end
            seen_key[key], seen_index[index] = true, true
            entries[slot] = {lo = lo, hi = hi, index = index, padding = padding}
            count = count + 1
        end
    end
    if count ~= config.used_count then return nil, 'component-map occupancy changed' end
    return entries, count
end

local function validate_probe_chain(entries, capacity)
    for slot = 0, capacity - 1 do
        local entry = entries[slot]
        if entry.lo ~= 0 or entry.hi ~= 0 then
            local start = bucket(entry.lo, entry.hi, capacity)
            local found = false
            for step = 0, capacity - 1 do
                local probe = (start + step) % capacity
                local current = entries[probe]
                if current.lo == 0 and current.hi == 0 then break end
                if same_key(current, entry.lo, entry.hi) then
                    found = probe == slot
                    break
                end
            end
            if not found then return false end
        end
    end
    return true
end

local function target_index(entries, config)
    local found, index = 0, nil
    for slot = 0, config.map_count - 1 do
        local entry = entries[slot]
        if same_key(entry, config.resource_lo, config.resource_hi) then
            found, index = found + 1, entry.index
        end
    end
    if found ~= 1 or index ~= config.target_index then return nil, 'R/40-K resource mapping mismatch' end
    local start = bucket(config.resource_lo, config.resource_hi, config.map_count)
    for step = 0, config.map_count - 1 do
        local slot = (start + step) % config.map_count
        local entry = entries[slot]
        if entry.lo == 0 and entry.hi == 0 then break end
        if same_key(entry, config.resource_lo, config.resource_hi) then return index end
    end
    return nil, 'R/40-K map probe lookup failed'
end

local function record_offset(config, index)
    return 28 + config.data_offset + index * config.stride
end

local function make_plan(api, address, config)
    local group, reason = read_group(api, address, config)
    if not group then return nil, reason end
    local entries, count = parse_map(group)
    if not entries then return nil, count end
    if not validate_probe_chain(entries, config.map_count) then return nil, 'component-map probe structure changed' end
    local index, index_reason = target_index(entries, config)
    if not index then return nil, index_reason end
    local row = record_offset(config, index)
    local function change(offset, before, after, label)
        local field = row + offset
        if group.source:sub(field + 1, field + #before) ~= before then
            return nil, label .. ' differs from the supported stock value'
        end
        return {offset = field, before = before, after = after}
    end

    if config == TABLES.weapon then
        local edit, edit_reason = change(config.ergonomics_offset,
            unhex('0000f041'), unhex('00003442'), 'R/40-K ergonomics 30')
        if not edit then return nil, edit_reason end
        group.changes = {edit}
    else
        if u32(group.source, row) ~= 0 then return nil, 'R/40-K magazine row header changed' end
        local values = {
            {config.capacity_offset, 12, 20, 'magazine capacity 12'},
            {config.starting_offset, 5, 5, 'starting magazines 5'},
            {config.refill_offset, 7, 5, 'refill magazines 7'},
            {config.maximum_offset, 7, 5, 'maximum magazines 7'},
        }
        group.changes = {}
        for _, item in ipairs(values) do
            local edit, edit_reason = change(item[1], pack32(item[2]), pack32(item[3]), item[4])
            if not edit then return nil, edit_reason end
            if edit.before ~= edit.after then group.changes[#group.changes + 1] = edit end
        end
    end
    if api.note then
        api.note(config.label .. ' candidate=' .. string.format('%.0f', api.identity(address)) ..
            ': validated target mapping and stock fields')
    end
    return group
end

local function locate(api, module, config)
    local header, result, seen = unhex(config.header), {}, {}
    local function add(address)
        local key = api.identity(address)
        if not seen[key] then seen[key] = true; result[#result + 1] = address end
    end
    for _, address in ipairs(api.candidates(module, nil, 0, header:sub(1, 16))) do add(address) end
    local found = api.scan_private_many({{signature = header, row_offset = 0, key = 1}}, true)[1]
    for _, address in ipairs(found or {}) do add(address) end
    return result
end

local function expected_after(group)
    local result = group.source
    for _, edit in ipairs(group.changes) do result = replace(result, edit.offset, edit.after) end
    return result
end

local function commit(api, groups)
    local expected = {}
    for index, group in ipairs(groups) do
        assert(api.read(group.address, group.size) == group.source,
            group.config.label .. ' changed before commit')
        expected[index] = expected_after(group)
        for _, edit in ipairs(group.changes) do
            assert(api.read(group.address + edit.offset, #edit.before) == edit.before,
                group.config.label .. ' target changed before commit')
        end
    end
    local attempted = {}
    local ok, reason = pcall(function()
        for _, group in ipairs(groups) do
            for _, edit in ipairs(group.changes) do
                attempted[#attempted + 1] = {group = group, edit = edit}
                assert(group.writer(group.address + edit.offset, edit.after),
                    group.config.label .. ' write was incomplete')
            end
        end
        for index, group in ipairs(groups) do
            assert(api.read(group.address, group.size) == expected[index],
                group.config.label .. ' full-table verification failed')
        end
    end)
    if ok then return end

    local restored = true
    for index = #attempted, 1, -1 do
        local item, edit = attempted[index], attempted[index].edit
        local current = api.read(item.group.address + edit.offset, #edit.before)
        local owned = current ~= nil and #current == #edit.before
        if owned then
            for byte = 1, #current do
                local value = current:byte(byte)
                if value ~= edit.before:byte(byte) and value ~= edit.after:byte(byte) then
                    owned = false
                    break
                end
            end
        end
        if owned and current ~= edit.before then
            local wrote = pcall(item.group.writer, item.group.address + edit.offset, edit.before)
            current = api.read(item.group.address + edit.offset, #edit.before)
            restored = (wrote and current == edit.before) and restored
        elseif not owned then
            restored = false
        end
    end
    error(tostring(reason) .. '; restored=' .. tostring(restored))
end

local function plans_for(api, module, config)
    local plans = {}
    for _, address in ipairs(locate(api, module, config)) do
        local plan, reason = make_plan(api, address, config)
        if plan then plans[#plans + 1] = plan
        elseif api.note then api.note(config.label .. ': ' .. tostring(reason)) end
    end
    return plans
end

function patch.apply(api, module)
    local ok, applied, reason = pcall(function()
        local exe, game = api.module(nil), api.module('game.dll')
        assert(exe ~= nil and game ~= nil, 'Game modules unavailable')
        assert(api.module_hash(exe) == GAME_BUILD_EXE, 'Unsupported executable. No edit applied.')
        assert(api.module_hash(game) == GAME_BUILD_DLL, 'Unsupported game module. No edit applied.')

        local weapon = plans_for(api, module, TABLES.weapon)
        local magazine = plans_for(api, module, TABLES.magazine)
        if #weapon == 0 or #magazine == 0 then return false, 'not-ready' end
        local pairs = {}
        local expected_distance = TABLES.weapon.file_offset - TABLES.magazine.file_offset
        for _, weapon_plan in ipairs(weapon) do
            for _, magazine_plan in ipairs(magazine) do
                if api.distance(weapon_plan.address, magazine_plan.address) == expected_distance then
                    pairs[#pairs + 1] = {weapon_plan, magazine_plan}
                end
            end
        end
        assert(#pairs == 1, 'Expected one matching R/40-K generated-data instance; found ' .. #pairs .. '. No edit applied.')
        commit(api, pairs[1])
        return true, 'Applied v0.8: R/40-K ergonomics 30 -> 45; 20 rounds per magazine; 5 starting / 5 refill / 5 maximum magazines. Stock magazine component retained. In-game behavior unverified.'
    end)
    if not ok then return false, tostring(applied) end
    return applied, reason
end

return patch

end)()
local start=(function()
return function(make_api, patch)
    if rawget(_G, 'R40KMagazineTuneV08') then return end
    local state = {
        version = '0.8', active = false,
        status = 'Waiting for first game update', scanned = 0, candidates = 0, diagnostics = {},
    }
    _G.R40KMagazineTuneV08 = state
    local previous = update
    local callback

    local function log()
        pcall(function()
            local logger = rawget(_G, 'CowboyBingusModLoader')
            local file = logger and logger.open_log and logger.open_log('R40KMagazineTune.log')
            if file then
                file:write('R40KMagazineTune v0.8\nstatus=' .. state.status ..
                    '\nscanned_bytes=' .. state.scanned .. '\ncandidates=' .. state.candidates ..
                    '\n' .. table.concat(state.diagnostics, '\n') .. '\n')
                file:close()
            end
        end)
    end

    local deadline, logged_mb = 0, -1
    local worker = coroutine.create(function()
        for _, name in ipairs({
            'R40KHeatSinkModV3', 'R40KHeatSinkModV4', 'R40KHeatSinkModV5',
            'R40KHeatSinkModV7',
        }) do
            assert(not rawget(_G, name),
                'Disable every older Hot-Shot prototype before enabling v0.8. No v0.8 changes applied.')
        end

        local api = make_api()
        api.note = function(message)
            if #state.diagnostics >= 16 then table.remove(state.diagnostics, 1) end
            state.diagnostics[#state.diagnostics + 1] = 'validation=' .. message
        end
        api.checkpoint = function(stage, force)
            state.status = stage
            if force or os.clock() >= deadline then coroutine.yield() end
        end
        api.progress = function(scanned, total, candidates)
            state.scanned, state.candidates = scanned, candidates
            local mb = math.floor(scanned / 16777216)
            if mb ~= logged_mb then logged_mb = mb; log() end
        end

        local exe, game = api.module(nil), api.module('game.dll')
        assert(exe ~= nil and game ~= nil, 'Game modules unavailable')
        state.status = 'Waiting for generated weapon data to load'
        log()
        local load_until = api.now() + 15000
        repeat coroutine.yield() until api.now() >= load_until

        local peer_deadline = api.now() + 90000
        local peers = {'FlagDamagePrototypeV1', 'SaiFocusModV1', 'AR11ArbitratorModV1'}
        while true do
            local pending = {}
            for _, name in ipairs(peers) do
                local peer = rawget(_G, name)
                if peer and not peer.active then pending[#pending + 1] = name end
            end
            if #pending == 0 then break end
            if api.now() >= peer_deadline then
                error('An enabled Flag, SAI, or AR-11 mod did not finish initialization. No R/40-K changes applied.')
            end
            state.status = 'Waiting for enabled Flag, SAI, and AR-11 mods to finish'
            log()
            coroutine.yield()
        end

        for attempt = 1, 8 do
            local applied, reason = patch.apply(api, game)
            if applied then return reason end
            local not_ready = reason == 'not-ready'
            local stale = reason:find('changed before commit', 1, true) ~= nil
                or reason:find('target changed before commit', 1, true) ~= nil
            local restored_conflict = reason:find('full-table verification failed', 1, true) ~= nil
                and reason:find('restored=true', 1, true) ~= nil
            if (not not_ready and not stale and not restored_conflict) or attempt == 8 then error(reason) end
            state.status = (stale or restored_conflict)
                and 'Shared table changed during setup; retrying safely'
                or 'R/40-K data not ready; retrying after loading'
            log()
            local until_time = api.now() + ((stale or restored_conflict) and 3000 or 10000)
            repeat coroutine.yield() until api.now() >= until_time
        end
    end)

    local function init()
        if coroutine.status(worker) == 'dead' then return end
        deadline = os.clock() + 0.0007
        local ok, message = coroutine.resume(worker)
        if not ok or coroutine.status(worker) == 'dead' then
            state.active, state.status = ok, tostring(message)
            print('[R40KMagazineTune] ' .. state.status)
            log()
            if update == callback then update = previous or function() end end
        end
    end

    local function finish(...) init(); return ... end
    callback = function(...)
        if previous then return finish(previous(...)) end
        init()
    end
    update = callback
    log()
end

end)()
start(make_api,patch)
