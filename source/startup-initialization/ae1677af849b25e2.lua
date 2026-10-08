-- HD2-Addon: mods/codex/rapid_arc_thrower
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
                if api.checkpoint then api.checkpoint('Searching private data for Arc Thrower records') end
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
local patch=(function()
local patch = {}

local DAMAGE_SIZE, DAMAGE_ROW_OFFSET, DAMAGE_ROW_SIZE = 49424, 15072, 76
local CHARGE_SIZE, CHARGE_GROUP_BACK, CHARGE_GROUP_SIZE = 216, 1644, 2724
local DAMAGE_ROW = 'c5000000fa000000640000000700000007000000070000000000000014000000230000000a000000020000002500000000000041000000000000000000000000000000000000000000000000'
local CHARGE_ROW = '0000803f0000000000000000000000000000000000000000cdcc8c3f00000000000000000000000000000000000000009a99993f00000000000000000000000000000000000000003333333f3333b33f0000803f0000803f0000803f0000803f0000803f0000803f0000000000000000000000000000000082c92774c995a2c500000000000000000000000001e2ccea009970c9000000003e5fcf52b2cf3dc4315845b16a44a4d50fd7d61a96fba229a931ee670e049541000100000000000000000000000000000d010000020000000000000000000000'
local CHARGE_OWNER = 'e606730fd59cde96'
local CHARGE_HEADER = 'a135c3ea4c444c4401000000a135c3ea880a00000100000000000000'
local WEAPON_ROW = '00002042000020420000b4420000b44200000000cdcccc3d0000803f00004842000048420000b4420000b4420000003fcdcccc3d0000803f0000003f0000803f0000803f0000803f0000803f0000803f0000803f0000204100002041000000000000803f0000803f0000803f0000803f000000000000803f0000803f0000803f0000803f0e0000000000803f0100000005000000060000000000000000000000000000000000000000000000000000000000000000000000000000000000000030eb953efde64a2d0000000026b16ea90000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000009a99193f3333333f6666663f7b142e3eec51b83d0000000000000000000000000000000000000000000048423333b33e000000000000c8c10000a0400000000000000000010001000000000000000000000000000f000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000739c7c525a68254d0000000000000000500abe665a3543fd0000000072cceba8e0c22a5000000000eb5d389c0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000002000000000000000000803f0000803f0000803f000000000000803f0000803f0000803fd8cfeaf500000000000000000000000000000000000000000000000000000000010000001200000000000000120000000000000012000000000000001200000000000000120000000000000012000000000000001200000000000000120000000000000000000000a0c7c3d5291e9a0855f346f280b6fbb2000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000803f00000000'
local WEAPON_OFFSET, WEAPON_SIZE = 26566228, 1232
local ARC_HEADER = '010000004c444c44010000006702dfaf900600000100000000000000'
local ARC_ROW = '070000000000964300005c42000020420000204200007042000040400100000001000000c5000000000000000000000000000000000000000000803e00000000b4a0b4fab308326c030000000be365f29a53f7846429b4690a000000010000000100000001000000'
local ARC_SIZE, ARC_ROW_OFFSET, ARC_ROW_SIZE = 1708, 44, 104

local function unhex(s) return (s:gsub('..', function(pair) return string.char(tonumber(pair, 16)) end)) end
local function u32(s, o)
    if not s or o < 0 or o + 4 > #s then return nil end
    local a,b,c,d = s:byte(o + 1, o + 4)
    return a + b*256 + c*65536 + d*16777216
end
local function replace(s, o, v) return s:sub(1,o) .. v .. s:sub(o+#v+1) end
local function word(v) return string.char(v%256, math.floor(v/256)%256, math.floor(v/65536)%256, math.floor(v/16777216)%256) end
local ROW = unhex(DAMAGE_ROW)
local CHARGE = unhex(CHARGE_ROW)
local OWNER = unhex(CHARGE_OWNER)
local HEADER = unhex(CHARGE_HEADER)
local WEAPON = unhex(WEAPON_ROW)
local ARC_H = unhex(ARC_HEADER)
local ARC = unhex(ARC_ROW)
local function float_word(n)
    local values = { [(0.20/0.65)] = 'd9899d3e', [(0.22/0.65)] = 'd54aad3e', [(0.24/0.65)] = 'd10bbd3e', [1.2] = '9a99993f', [0.85] = '9a99593f', [0.4] = 'cdcccc3e', [45] = '00003442' }
    return unhex(assert(values[n]))
end

local function validate_arc(api,address)
    if not api.data_access(address,ARC_SIZE) then return nil,'arc settings are not supported private data' end
    local s=api.read(address,ARC_SIZE)
    if not s or #s~=ARC_SIZE or s:sub(1,28)~=ARC_H or u32(s,36)~=16 or u32(s,40)~=0 then
        return nil,'arc settings header or size mismatch'
    end
    local data=api.pointer(s,28)
    if not data or api.distance(data,address)~=ARC_ROW_OFFSET then
        return nil,'arc settings row pointer mismatch'
    end
    local row=s:sub(ARC_ROW_OFFSET+1,ARC_ROW_OFFSET+ARC_ROW_SIZE)
    if row~=ARC or u32(row,0)~=7 or u32(row,36)~=197 then
        return nil,'ARC-3 range row changed or conflicts with another mod'
    end
    return {address=address+ARC_ROW_OFFSET,size=ARC_ROW_SIZE,source=row,writes={
        {offset=8,bytes=float_word(45),writer='protected'},
    }}
end

local function validate_damage(api, address)
    if not api.writable(address, DAMAGE_SIZE) then return nil, 'damage table is not writable private data' end
    local s = api.read(address, DAMAGE_SIZE)
    if not s or #s ~= DAMAGE_SIZE or u32(s,0) ~= 2 then return nil, 'damage table size/header mismatch' end
    if s:sub(5,28) ~= unhex('4c444c4401000000da3314eb200000000100000000000000') then
        return nil, 'damage first group header mismatch'
    end
    if s:sub(61,84) ~= unhex('4c444c4401000000f02ca7e0bcc000000100000000000000') then
        return nil, 'damage row group header mismatch'
    end
    if u32(s,92) ~= 649 or u32(s,96) ~= 0 then return nil, 'damage row count mismatch' end
    local data = api.pointer(s,84)
    if not data or api.distance(data,address) ~= 100 then return nil, 'damage row pointer mismatch' end
    if s:sub(DAMAGE_ROW_OFFSET+1,DAMAGE_ROW_OFFSET+DAMAGE_ROW_SIZE) ~= ROW then
        return nil, 'Arc Thrower damage row changed or conflicts with another mod'
    end
    if u32(s,DAMAGE_ROW_OFFSET) ~= 197 or u32(s,DAMAGE_ROW_OFFSET+44) ~= 37 then
        return nil, 'Arc Thrower damage/status identity mismatch'
    end
    return {address=address+DAMAGE_ROW_OFFSET,size=DAMAGE_ROW_SIZE,
      source=s:sub(DAMAGE_ROW_OFFSET+1,DAMAGE_ROW_OFFSET+DAMAGE_ROW_SIZE),writes={
        {offset=4,bytes=word(226),writer='normal'},
        {offset=8,bytes=word(90),writer='normal'},
        {offset=28,bytes=word(4),writer='normal'},
        {offset=32,bytes=word(25),writer='normal'},
        {offset=36,bytes=word(2),writer='normal'},
        {offset=48,bytes=float_word(1.2),writer='normal'},
    }}
end

local function validate_weapon(api,address)
    if not api.data_access(address,WEAPON_SIZE) or api.writable(address,WEAPON_SIZE) then
        return nil,'weapon data is not the read-only source record'
    end
    local s=api.read(address,WEAPON_SIZE)
    if not s or #s~=WEAPON_SIZE or s~=WEAPON then
        return nil,'ARC-3 weapon data changed or conflicts with another mod'
    end
    return {address=address,size=WEAPON_SIZE,source=s,writes={
        {offset=76,bytes=float_word(0.4),writer='protected'},
        {offset=80,bytes=float_word(0.4),writer='protected'},
    }}
end

local function validate_charge(api, address)
    if not api.data_access(address, CHARGE_SIZE) then return nil, 'charge record is not supported private data' end
    if api.writable(address, CHARGE_SIZE) then return nil, 'charge candidate is a writable copy, not the read-only source record' end
    local s = api.read(address,CHARGE_SIZE)
    if not s or #s ~= CHARGE_SIZE then return nil, 'Arc Thrower charge record is unreadable' end
    local auto_fire = s:byte(185)
    if (auto_fire ~= 0 and auto_fire ~= 1) or replace(s,184,string.char(0)) ~= CHARGE then
        return nil, 'Arc Thrower charge record changed beyond the supported Bingus auto-fire flag'
    end
    local group = api.read(address-CHARGE_GROUP_BACK,CHARGE_GROUP_SIZE)
    if not group or #group ~= CHARGE_GROUP_SIZE or group:sub(1,28) ~= HEADER then
        return nil, 'charge component group header mismatch'
    end
    if group:sub(CHARGE_GROUP_BACK+1,CHARGE_GROUP_BACK+CHARGE_SIZE) ~= s then
        return nil, 'charge record is not at the expected mapped index'
    end
    local owner_count = 0
    for i=0,19 do
        local at = 28+i*16
        if group:sub(at+1,at+8) == OWNER then
            owner_count = owner_count+1
            if u32(group,at+8) ~= 6 then return nil, 'Arc Thrower charge owner points to another record' end
        end
    end
    if owner_count ~= 1 then return nil, 'Arc Thrower charge owner is missing or duplicated' end
    return {address=address,size=CHARGE_SIZE,source=s,writes={
        {offset=0,bytes=float_word((0.20/0.65)),writer='protected'},
        {offset=24,bytes=float_word((0.22/0.65)),writer='protected'},
        {offset=48,bytes=float_word((0.24/0.65)),writer='protected'},
        {offset=80,bytes=float_word(0.85),writer='protected'},
        {offset=84,bytes=float_word(0.85),writer='protected'},
    }}
end

local function unique(api, addresses, validator, name)
    local plans,seen = {},{}
    for _,address in ipairs(addresses) do
        local identity = api.identity(address)
        if not seen[identity] then
            seen[identity]=true
            local plan,reason=validator(api,address)
            if api.note then api.note(name..' address='..string.format('%.0f',identity)..': '..(reason or 'validated')) end
            if plan then plans[#plans+1]=plan end
        end
    end
    assert(#plans==1,'Expected one supported '..name..' record; found '..#plans..'. No edit applied.')
    return plans[1]
end

local function apply_one(api,p)
    for _,edit in ipairs(p.writes) do
        local before=api.read(p.address,p.size)
        assert(before and before==p.current,'Data changed before write')
        local expected=replace(before,edit.offset,edit.bytes)
        p.attempted[#p.attempted+1]={offset=edit.offset,bytes=edit.bytes,before=before,writer=edit.writer}
        local write=edit.writer=='protected' and api.write_protected or api.write
        assert(write(p.address+edit.offset,edit.bytes),'Data write was incomplete')
        assert(api.read(p.address,p.size)==expected,'Full record verification failed')
        p.current=expected
    end
end

local function rollback(api,plans)
    local restored=true
    for pi=#plans,1,-1 do
        local p=plans[pi]
        for wi=#p.attempted,1,-1 do
            local edit=p.attempted[wi]
            local current=api.read(p.address,p.size)
            local baseline=edit.before
            local first,last=edit.offset+1,edit.offset+#edit.bytes
            local owned=current and #current==p.size
              and current:sub(1,first-1)==baseline:sub(1,first-1)
              and current:sub(last+1)==baseline:sub(last+1)
            if owned then
                for n=1,#edit.bytes do
                    local value=current:byte(edit.offset+n)
                    if value~=baseline:byte(edit.offset+n) and value~=edit.bytes:byte(n) then owned=false;break end
                end
            end
            if owned then
                local write=edit.writer=='protected' and api.write_protected or api.write
                restored=(write(p.address+edit.offset,baseline:sub(first,last))
                  and api.read(p.address,p.size)==baseline) and restored
            else restored=false end
        end
    end
    return restored
end

function patch.apply(api,module)
    local runtime
    local ok,result=pcall(function()
        local plans={unique(api,api.candidates(module),validate_damage,'Arc Thrower damage')}
        plans[#plans+1]=unique(api,api.candidates(module,nil,nil,ARC_H:sub(1,16)),validate_arc,'Arc Thrower range')
        local charge_candidates,weapon_candidates={},{}
        for _,region in ipairs(api.private_regions(true)) do
            if region.size==46616576 and region.protection==2 then
                charge_candidates[#charge_candidates+1]=region.base+7566708
                weapon_candidates[#weapon_candidates+1]=region.base+WEAPON_OFFSET
            end
        end
        plans[#plans+1]=unique(api,charge_candidates,validate_charge,'Arc Thrower charge')
        plans[#plans+1]=unique(api,weapon_candidates,validate_weapon,'Arc Thrower recoil')
        for _,p in ipairs(plans) do
            assert(api.read(p.address,p.size)==p.source,'Data changed during discovery. No edit applied.')
            p.current,p.attempted=p.source,{}
        end
        local success,reason=pcall(function() for _,p in ipairs(plans) do apply_one(api,p) end end)
        if not success then error(tostring(reason)..'; restored='..tostring(rollback(api,plans))) end
        runtime={damage_row=plans[1].address,arc_row=plans[2].address,
            charge_row=plans[3].address,weapon_row=plans[4].address}
        return 'Applied: ARC-3 range 55 -> 45 m; charge 1.0/1.1/1.2 -> 0.307692/0.338462/0.369231 s; damage 250/100 -> 226/90; Stun Medium buildup 8 -> 1.2; demolition/force strength/impulse 20/35/10 -> 4/25/2; camera climb 1.0/1.0 -> 0.4/0.4.'
    end)
    if ok then patch.runtime=runtime end
    return ok,tostring(result)
end

return patch

end)()

local supercharge=(function()
local M={}
local ffi=require('ffi')
local bit=require('bit')
local function unhex(s) return (s:gsub('..',function(p) return string.char(tonumber(p,16)) end)) end
local function u32(s,o)
 local a,b,c,d=s:byte(o+1,o+4);return a+b*256+c*65536+d*16777216
end
local function f32(s,o)
 local x=ffi.new('float[1]');ffi.copy(x,s:sub(o+1,o+4),4);return tonumber(x[0])
end
local function word(v)
 return string.char(v%256,math.floor(v/256)%256,math.floor(v/65536)%256,math.floor(v/16777216)%256)
end
local function replace(s,o,v)return s:sub(1,o)..v..s:sub(o+#v+1)end
local function read(api,p,n)local s=api.read(p,n);assert(s and #s==n,'Supercharge read failed');return s end
local function ptr(api,s,o)return assert(api.pointer(s,o),'Supercharge pointer unavailable')end
local function same(api,a,b)return api.identity(a)==api.identity(b)end

local OWNER=unhex("e606730fd59cde96")
local EXPECT_WEAPON=unhex("00002042000020420000b4420000b44200000000cdcccc3d0000803f00004842000048420000b4420000b4420000003fcdcccc3d0000803f0000003f0000803f0000803f0000803f0000803fcdcccc3ecdcccc3e0000204100002041000000000000803f0000803f0000803f0000803f000000000000803f0000803f0000803f0000803f0e0000000000803f0100000005000000060000000000000000000000000000000000000000000000000000000000000000000000000000000000000030eb953efde64a2d0000000026b16ea90000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000009a99193f3333333f6666663f7b142e3eec51b83d0000000000000000000000000000000000000000000048423333b33e000000000000c8c10000a0400000000000000000010001000000000000000000000000000f000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000739c7c525a68254d0000000000000000500abe665a3543fd0000000072cceba8e0c22a5000000000eb5d389c0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000002000000000000000000803f0000803f0000803f000000000000803f0000803f0000803fd8cfeaf500000000000000000000000000000000000000000000000000000000010000001200000000000000120000000000000012000000000000001200000000000000120000000000000012000000000000001200000000000000120000000000000000000000a0c7c3d5291e9a0855f346f280b6fbb2000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000803f00000000")
local EXPECT_CHARGE=unhex("d9899d3e0000000000000000000000000000000000000000d54aad3e0000000000000000000000000000000000000000d10bbd3e00000000000000000000000000000000000000003333333f3333b33f9a99593f9a99593f0000803f0000803f0000803f0000803f0000000000000000000000000000000082c92774c995a2c500000000000000000000000001e2ccea009970c9000000003e5fcf52b2cf3dc4315845b16a44a4d50fd7d61a96fba229a931ee670e049541000100000000000000000000000000000d010000020000000000000000000000")
local EXPECT_ARCWEAPON=unhex("07000000000080bf01000000195e662900000000994944402bce8e2c00000000c395de7e08bcb2d6c395de7e08bcb2d600000000000000000000a040000020418711eedd2a623c910668590122760be7")
local EXPECT_ARC7=unhex("070000000000964300003442000020420000204200007042000040400100000001000000c5000000000000000000000000000000000000000000803e00000000b4a0b4fab308326c030000000be365f29a53f7846429b4690a000000010000000100000001000000")
local EXPECT_ARC11=unhex("0b0000000000fa4400007a4300000000000000000000344300000000000000000000000023020000000000000000000020cf346eecd8a6d80000403f00000000b4a0b4fab308326c000000000000000066e3c0966604792e0a000000010000000100000001000000")
local EXPECT_DAMAGE197=unhex("c5000000e20000005a0000000700000007000000070000000000000004000000190000000200000002000000250000009a99993f000000000000000000000000000000000000000000000000")
local EXPECT_DAMAGE547=unhex("23020000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000")
local SUPER_ARC11=unhex("0b000000000096430000344200002042000020420000704200004040010000000000000023020000000000000000000000000000000000000000803e00000000b4a0b4fab308326c030000000be365f29a53f7846429b4690a000000010000000100000001000000")
local SUPER_DAMAGE547=unhex("230200000e0600000e06000007000000070000000700000000000000040000001900000002000000020000002500000000004041270000000000c84100000000000000000000000000000000")
local FUNC3=unhex('0300000000000000')
local TYPE7=unhex('07000000')
local TYPE11=unhex('0b000000')
local F49=unhex('cdcc9c40')
local F5=unhex('0000a040')
local F525=unhex('0000a840')
local F1=unhex('0000803f')
local DAMAGE_DELTA=26144
local ARC_DELTA=1352

local function map(api,h,o,key,guards)
 local cap,empty,mult=u32(h,o+8),u32(h,o+12),u32(h,o+16)
 assert(cap>0 and cap<=4096 and bit.band(cap,cap-1)==0,'Native map capacity changed')
 local array=ptr(api,h,o)
 local product=((key%65536)*mult+math.floor(key/65536)*(mult%65536)*65536)%4294967296
 local tomb
 for probe=0,math.min(cap,64)-1 do
  local p=array+bit.band(product+probe,cap-1)*8
  local row=read(api,p,8);if guards then guards[#guards+1]={address=p,bytes=row} end
  local ident,index=u32(row,0),u32(row,4)
  if ident==key and index~=4294967295 then return index,p end
  if index==4294967295 and not tomb then tomb=p end
  if ident==empty or ident==key then return nil,tomb or p end
 end
 error('Native map probe bound reached')
end

local function source_arcweapon(api,game)
 local root=ptr(api,read(api,game+0x346bf98,8),0)
 local base=ptr(api,read(api,root+0xf12cc0,8),0)
 local lo,hi=0x0f7306e6,0x96de9cd5
 local start=2
 for probe=0,19 do
  local slot=(start+probe)%20
  local row=read(api,base+slot*16,16)
  if u32(row,0)==lo and u32(row,4)==hi then
   local index=u32(row,8);assert(index~=4294967295,'ArcWeapon source tombstone')
   return base+0x140+index*80
  end
  if u32(row,0)==0 and u32(row,4)==0 then break end
 end
 error('ARC ArcWeapon source owner missing')
end

local function desired_charge(src,super)
 if not super then return src end
 local s=replace(src,0,F49)
 s=replace(s,24,F5);s=replace(s,48,F525)
 -- Rapid source is balanced with 0.85x damage. Supercharge owns dedicated Damage547,
 -- so restore both charge damage multipliers to exactly 1.0 in its private row.
 s=replace(s,80,F1);s=replace(s,84,F1)
 -- Preserve the native ARC charge start/stop pair in both profiles.
 -- Those events are guaranteed resident with the equipped ARC bank. The 5-second
 -- Supercharge simply sustains the native electrical charge loop much longer.
 -- Ready/danger remain the ARC source values (both zero).
 -- Damage multiplier remains the source 1.0/1.0. Supercharge damage lives in Damage547.
 -- Preserve +184 AutoFireInSafety from the source so CowboyBingus Arc Thrower Revamped
 -- can auto-release at full charge. Disable self-explosion only for Supercharge.
 s=replace(s,185,string.char(0))
 return s
end
local function desired_arc(src,super)return replace(src,0,super and TYPE11 or TYPE7)end

local function commit4(api,edits,guards)
 for _,g in ipairs(guards or {}) do
  assert(read(api,g.address,#g.bytes)==g.bytes,'Supercharge precondition changed')
 end
 local done={}
 local ok,why=pcall(function()
  for _,e in ipairs(edits) do
   assert(read(api,e.address,4)==e.before,'Supercharge target changed')
   if e.before~=e.after then
    done[#done+1]=e
    local wr=e.protected and api.write_protected or api.write
    assert(wr(e.address,e.after),'Supercharge write failed')
    assert(read(api,e.address,4)==e.after,'Supercharge readback failed')
   end
  end
 end)
 if ok then return true end
 local restored=true
 for i=#done,1,-1 do
  local e=done[i];local now=read(api,e.address,4)
  if now==e.after then
   local wr=e.protected and api.write_protected or api.write
   restored=wr(e.address,e.before) and read(api,e.address,4)==e.before and restored
  elseif now~=e.before then restored=false end
 end
 error(tostring(why)..'; restored='..tostring(restored))
end

local function stage_row(api,edits,address,before,after,protected)
 assert(#before==#after and #before%4==0,'Invalid staged row')
 for o=0,#before-4,4 do
  local b,a=before:sub(o+1,o+4),after:sub(o+1,o+4)
  if b~=a then edits[#edits+1]={address=address+o,before=b,after=a,protected=protected} end
 end
end

local function reserve(api,h,o,key,index,reserved,guards)
 local cap,empty,mult=u32(h,o+8),u32(h,o+12),u32(h,o+16)
 assert(cap>0 and cap<=4096 and bit.band(cap,cap-1)==0,'Override map capacity changed')
 local array=ptr(api,h,o)
 local product=((key%65536)*mult+math.floor(key/65536)*(mult%65536)*65536)%4294967296
 local tomb
 for probe=0,math.min(cap,64)-1 do
  local p=array+bit.band(product+probe,cap-1)*8
  local row=read(api,p,8);guards[#guards+1]={address=p,bytes=row}
  local ident,ix=u32(row,0),u32(row,4)
  if ident==key then assert(ix==4294967295,'Override key already registered') end
  if ix==4294967295 and not tomb then tomb=p end
  if ident==empty or ident==key then
   local q=tomb or p;reserved[api.identity(q)]=word(key)..word(index);return q
  end
 end
 error('No bounded override slot')
end

local layouts={
 charge={capacity=0x04,count=0x88,forward=0x50,reverse=0x70,rows=0x90,stride=216,header=160},
 arc={capacity=0x2c,count=0xc0,forward=0x88,reverse=0xa8,rows=0xc8,stride=80,header=208},
}
local function plan_group(api,g,item,plan)
 local l=layouts[g.kind];local h=g.header
 assert(#h==l.header and read(api,g.manager,l.header)==h,'Stale override manager')
 plan.guards[#plan.guards+1]={address=g.manager,bytes=h}
 local count,capacity=u32(h,l.count),u32(h,l.capacity)
 assert(count<=capacity and capacity<=512,'Override row capacity changed')
 local rows=ptr(api,h,l.rows)
 local index,forward=map(api,h,l.forward,item.id,plan.guards)
 local target
 if index then
  assert(index<count,'Override index outside used count')
  local owner=map(api,h,l.reverse,index,plan.guards)
  assert(owner==item.id,'Override reverse owner changed')
  target=rows+index*l.stride
  local current=read(api,target,l.stride)
  assert(current==item.rapid or current==item.super,'Foreign private component edit')
  for o=0,l.stride-4,4 do
   local b,a=current:sub(o+1,o+4),item.desired:sub(o+1,o+4)
   if b~=a then plan.edits[#plan.edits+1]={address=target+o,before=b,after=a,protected=false} end
  end
  return
 end
 assert(count<capacity,'Preallocated override rows exhausted')
 index=count;target=rows+index*l.stride
 local reserved={}
 forward=reserve(api,h,l.forward,item.id,index,reserved,plan.guards)
 local reverse=reserve(api,h,l.reverse,index,item.id,reserved,plan.guards)
 local current=read(api,target,l.stride)
 for o=0,l.stride-4,4 do
  local b=current:sub(o+1,o+4)
  local a=item.desired:sub(o+1,o+4)
  plan.edits[#plan.edits+1]={address=target+o,before=b,after=a,protected=false}
 end
 plan.edits[#plan.edits+1]={address=reverse+4,before=read(api,reverse+4,4),after=word(item.id),protected=false}
 plan.edits[#plan.edits+1]={address=reverse,before=read(api,reverse,4),after=word(index),protected=false}
 plan.edits[#plan.edits+1]={address=g.manager+l.count,before=word(count),after=word(count+1),protected=false}
 plan.edits[#plan.edits+1]={address=forward+4,before=read(api,forward+4,4),after=word(index),protected=false}
 plan.edits[#plan.edits+1]={address=forward,before=read(api,forward,4),after=word(item.id),protected=false}
end

local function patch_private_weapon(api,wm,wh,id,guards,edits)
 local wi=map(api,wh,0x70,id,guards)
 if not wi then return end
 assert(wi<u32(wh,0xa8),'Private WeaponData index changed')
 local row=ptr(api,wh,0xb0)+wi*1232
 local fields=read(api,row+140,52)
 local primary,secondary=u32(fields,4),u32(fields,8)
 assert(u32(fields,0)==1 and (primary==5 or primary==1) and (secondary==6 or secondary==1 or secondary==2)
   and u32(fields,12)==0 and u32(fields,16)==0,'ARC private fire-mode slots changed')
 if primary~=1 then
  edits[#edits+1]={address=row+144,before=word(primary),after=word(1),protected=false}
 end
 if secondary~=2 then
  edits[#edits+1]={address=row+148,before=word(secondary),after=word(2),protected=false}
 end
 local fn=fields:sub(45,52)
 assert(fn==unhex('0000000000000000') or fn==FUNC3,'ARC private selector changed')
 if fn~=FUNC3 then
  edits[#edits+1]={address=row+184,before=fn:sub(1,4),after=FUNC3:sub(1,4),protected=false}
  edits[#edits+1]={address=row+188,before=fn:sub(5,8),after=FUNC3:sub(5,8),protected=false}
 end
end

function M.prepare(api,module,runtime)
 assert(runtime and runtime.damage_row and runtime.arc_row and runtime.charge_row and runtime.weapon_row,
   'Rapid validated addresses unavailable')
 local game=ffi.cast('uint8_t *',module)
 local weapon=read(api,runtime.weapon_row,1232)
 local charge=read(api,runtime.charge_row,216)
 local arc7=read(api,runtime.arc_row,104)
 local damage197=read(api,runtime.damage_row,76)
 assert(weapon==EXPECT_WEAPON,'Rapid WeaponData changed before Supercharge prepare')
 local normalized=replace(charge,184,string.char(0))
 local expectnorm=replace(EXPECT_CHARGE,184,string.char(0))
 assert(normalized==expectnorm,'Rapid Charge changed before Supercharge prepare')
 assert(arc7==EXPECT_ARC7,'Rapid ArcSettings7 changed before Supercharge prepare')
 assert(damage197==EXPECT_DAMAGE197,'Rapid Damage197 changed before Supercharge prepare')
 local arcweapon_addr=source_arcweapon(api,game)
 local arcweapon=read(api,arcweapon_addr,80)
 assert(arcweapon==EXPECT_ARCWEAPON,'ARC ArcWeapon source changed')

 local damage547_addr=runtime.damage_row+DAMAGE_DELTA
 local arc11_addr=runtime.arc_row+ARC_DELTA
 local damage547=read(api,damage547_addr,76)
 local arc11=read(api,arc11_addr,104)
 assert(damage547==EXPECT_DAMAGE547,'Damage547 donor changed before prepare')
 assert(arc11==EXPECT_ARC11,'ArcSettings11 donor changed before prepare')

 local edits={}
 stage_row(api,edits,damage547_addr,damage547,SUPER_DAMAGE547,false)
 stage_row(api,edits,arc11_addr,arc11,SUPER_ARC11,true)
 assert(u32(weapon,144)==5 and u32(weapon,148)==6,'ARC source fire modes changed before prepare')
 local fn=weapon:sub(185,192)
 assert(fn==unhex('0000000000000000'),'ARC source selector changed before prepare')
 edits[#edits+1]={address=runtime.weapon_row+144,before=word(5),after=word(1),protected=true}
 edits[#edits+1]={address=runtime.weapon_row+148,before=word(6),after=word(2),protected=true}
 edits[#edits+1]={address=runtime.weapon_row+184,before=fn:sub(1,4),after=FUNC3:sub(1,4),protected=true}
 edits[#edits+1]={address=runtime.weapon_row+188,before=fn:sub(5,8),after=FUNC3:sub(5,8),protected=true}
 commit4(api,edits,{})

 local selected=replace(replace(replace(weapon,144,word(1)),148,word(2)),184,FUNC3)
 assert(read(api,runtime.weapon_row,1232)==selected,'ARC selector source verification failed')
 assert(read(api,damage547_addr,76)==SUPER_DAMAGE547,'Damage547 donor verification failed')
 assert(read(api,arc11_addr,104)==SUPER_ARC11,'ArcSettings11 donor verification failed')

 return {
  game=game,weapon=selected,charge=charge,arc=arcweapon,
  charge_super=desired_charge(charge,true),arc_super=desired_arc(arcweapon,true),
  contexts={},frame=0,status='Prepared: native Firemode selector enabled',
 }
end

local function resolve_managers(api,plan)
 local wm=ptr(api,read(api,plan.game+0x3326ce0,8),0);local wh=read(api,wm,192)
 local cm=ptr(api,read(api,plan.game+0x3326c20,8),0);local ch=read(api,cm,160)
 local am=ptr(api,read(api,plan.game+0x3326c10,8),0);local ah=read(api,am,208)
 return wm,wh,cm,ch,am,ah
end

local function busy(api,address)
 local b=read(api,address,28)
 local c,r=f32(b,4),f32(b,24)
 assert(c==c and r==r and math.abs(c)<=30 and math.abs(r)<=30,'ARC charge state invalid')
 return c~=0 or r~=0
end

local function current_profile(api,plan,ch,ah,id)
 local ci=map(api,ch,0x50,id)
 local ai=map(api,ah,0x88,id)
 if not ci and not ai then return 1 end
 assert(ci and ai,'ARC private profile ownership split')
 assert(ci<u32(ch,0x88) and ai<u32(ah,0xc0),'ARC private profile index changed')
 local cr=read(api,ptr(api,ch,0x90)+ci*216,216)
 local ar=read(api,ptr(api,ah,0xc8)+ai*80,80)
 if cr==plan.charge and ar==plan.arc then return 1 end
 if cr==plan.charge_super and ar==plan.arc_super then return 2 end
 error('Foreign ARC private profile')
end

local function apply_profile(api,plan,ctx,mode)
 local wm,wh,cm,ch,am,ah=resolve_managers(api,plan)
 local p={guards={},edits={}}
 patch_private_weapon(api,wm,wh,ctx.id,p.guards,p.edits)
 plan_group(api,{kind='charge',manager=cm,header=ch},
   {id=ctx.id,rapid=plan.charge,super=plan.charge_super,
    desired=mode==2 and plan.charge_super or plan.charge},p)
 plan_group(api,{kind='arc',manager=am,header=ah},
   {id=ctx.id,rapid=plan.arc,super=plan.arc_super,
    desired=mode==2 and plan.arc_super or plan.arc},p)
 if #p.edits>0 then commit4(api,p.edits,p.guards) end
 ctx.applied_mode=mode
 return #p.edits
end

local function discover(api,plan)
 local wm,wh,cm,ch,am,ah=resolve_managers(api,plan)
 local owned=u32(ch,0x10)
 assert(owned<=u32(ch,0x0c) and owned<=512,'Owned charge count changed')
 local refs=owned>0 and read(api,ptr(api,ch,0x38),owned*8) or ''
 local found={}
 for slot=0,owned-1 do
  local entity=ptr(api,refs,slot*8)
  local identity=read(api,entity,24)
  if identity:sub(1,8)==OWNER and bit.band(u32(identity,20),1)==1 then
   local id=u32(identity,8)
   local wi=map(api,wh,0x30,id)
   assert(wi and wi<u32(wh,0x1c),'ARC weapon slot changed')
   local entity_ref=refs:sub(slot*8+1,slot*8+8)
   local weapon_refaddr=ptr(api,wh,0x48)+wi*8
   assert(read(api,weapon_refaddr,8)==entity_ref,'ARC weapon owner changed')
   local si=map(api,ch,0x20,id)
   assert(si==slot,'ARC charge state slot changed')
   local charge_refaddr=ptr(api,ch,0x38)+si*8
   assert(read(api,charge_refaddr,8)==entity_ref,'ARC charge owner changed')
   local modeaddr=ptr(api,wh,0x60)+wi*12
   local stateaddr=ptr(api,ch,0x40)+si*40
   local mode=u32(read(api,modeaddr,4),0)
   assert(mode==1 or mode==2,'Unsupported ARC fire mode')
   local ctx={id=id,entity=entity,identity=identity,entity_ref=entity_ref,
     weapon_refaddr=weapon_refaddr,charge_refaddr=charge_refaddr,
     modeaddr=modeaddr,stateaddr=stateaddr}
   local selector_plan={guards={},edits={}}
   patch_private_weapon(api,wm,wh,id,selector_plan.guards,selector_plan.edits)
   if #selector_plan.edits>0 then commit4(api,selector_plan.edits,selector_plan.guards) end
   local private_mode=current_profile(api,plan,ch,ah,id)
   ctx.applied_mode=private_mode
   if not busy(api,stateaddr) and private_mode~=mode then apply_profile(api,plan,ctx,mode) end
   if not map(api,ch,0x50,id) or not map(api,ah,0x88,id) then
    if not busy(api,stateaddr) then apply_profile(api,plan,ctx,mode) end
   end
   found[#found+1]=ctx
  end
 end
 plan.contexts=found
 plan.weapon_manager=wm;plan.charge_manager=cm
 plan.mode_array=wh:sub(0x61,0x68);plan.charge_state_array=ch:sub(0x41,0x48)
 return #found
end

function M.synchronize(api,plan)
 plan.frame=plan.frame+1
 -- Recheck for newly created ARC entities after the first was registered.
 if #plan.contexts==0 or plan.frame%30==1 then
  if plan.frame%30~=1 then return plan.status end
  local n=discover(api,plan)
  plan.status=n>0 and ('Ready: '..n..' ARC instance(s)') or 'Ready: waiting for ARC instance'
  return plan.status
 end
 if read(api,plan.weapon_manager+0x60,8)~=plan.mode_array
    or read(api,plan.charge_manager+0x40,8)~=plan.charge_state_array then
  plan.contexts={};plan.status='ARC arrays changed; rebinding';return plan.status
 end
 for _,ctx in ipairs(plan.contexts) do
  if read(api,ctx.entity,24)~=ctx.identity
     or read(api,ctx.weapon_refaddr,8)~=ctx.entity_ref
     or read(api,ctx.charge_refaddr,8)~=ctx.entity_ref then
   plan.contexts={};plan.status='ARC instance changed; rebinding';return plan.status
  end
  local mode=u32(read(api,ctx.modeaddr,4),0)
  assert(mode==1 or mode==2,'Unsupported ARC fire mode')
  if mode~=ctx.applied_mode and not busy(api,ctx.stateaddr) then
   apply_profile(api,plan,ctx,mode)
  end
  plan.status=mode==2 and 'Supercharge selected' or 'Rapid Fire selected'
 end
 return plan.status
end

return M
end)()

local start = (function()
return function(make_api, patch, supercharge)
    if rawget(_G,'RapidArcThrowerV1') then return end
    local state={version='0.11',active=false,status='Waiting for first game update',scanned=0,candidates=0,diagnostics={}}
    _G.RapidArcThrowerV1=state
    local previous=update
    local callback
    local api,super_plan
    local super_disabled=false
    local last_super_status
    local function log()
        pcall(function()
            local logger=rawget(_G,'CowboyBingusModLoader')
            local file=logger and logger.open_log and logger.open_log('RapidArcThrower.log')
            if file then
                file:write('RapidArcThrower v0.10\nstatus='..state.status..'\nscanned_bytes='..state.scanned..'\ncandidates='..state.candidates..'\n'..table.concat(state.diagnostics,'\n')..'\n')
                file:close()
            end
        end)
    end
    local deadline=0
    local logged_mb=-1
    local worker=coroutine.create(function()
        api=make_api()
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
        for attempt=1,6 do
            state.status='Validating ARC-3 data; attempt '..attempt..'/6'
            log()
            local applied,reason=patch.apply(api,game)
            if applied then
                super_plan=supercharge.prepare(api,game,assert(patch.runtime,'Rapid runtime addresses missing'))
                state.supercharge_status='Prepared: native Firemode selector enabled'
                return reason
            end
            if not reason:find('found 0. No edit applied.',1,true) or attempt==6 then error(reason) end
            state.status='ARC-3 data not ready; retrying after loading'
            local until_time=api.now()+10000
            repeat coroutine.yield() until api.now()>=until_time
        end
    end)
    local function init()
        if coroutine.status(worker)=='dead' then return end
        deadline=os.clock()+0.004
        local ok,message=coroutine.resume(worker)
        if not ok then
            state.active=false
            state.status=tostring(message)
            super_disabled=true
            state.supercharge_status='Stopped during prepare: '..state.status
            print('[RapidArcThrower] '..state.status)
            log()
        elseif coroutine.status(worker)=='dead' then
            state.active=true
            state.status=tostring(message)
            print('[RapidArcThrower] '..state.status)
            log()
        end
    end
    local function finish(...)
        init()
        if state.active and super_plan and not super_disabled then
            local ok,label=pcall(supercharge.synchronize,api,super_plan)
            if ok then
                state.supercharge_status=label
                if label~=last_super_status then
                    last_super_status=label
                    print('[RapidArcSupercharge] '..label)
                end
            else
                super_disabled=true
                state.supercharge_status='Stopped: '..tostring(label)
                print('[RapidArcSupercharge] '..state.supercharge_status)
                log()
            end
        end
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
start(make_api,patch,supercharge)
