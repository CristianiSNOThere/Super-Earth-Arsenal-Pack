-- HD2-Addon: mods/codex/ac8_backpackless
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
    function api.module(name) return ffi.cast('uint8_t *',k.GetModuleHandleA(name)) end
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
        assert(#s==1 or #s==4 or #s==8,'Only validated 1-, 4-, or 8-byte data edits may be written')
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
local COMPONENTS={['rounds']={['name']='WeaponRoundsComponent',['group']=5766096,['header']='721008664c444c440100000072100866f01000000100000000000000',['map']=5766764,['owner']='5f5c0b6f31fbcfa81700000000000000',['row']=5770052,['before']='0000803f0000803f0000803f0000803f0000803f0000803f0000803f0000803f0000803f0000803f0000803f0000803f0000803f0000803f0000803f0000803f73000000000000000000204100000000000000000000000000000000050000000000c040000000000100000000000000000000000000000000000000000000000000000000000000'},['reload']={['name']='WeaponReloadComponent',['group']=5737840,['header']='4e451d994c444c44010000004e451d99406d00000100000000000000',['map']=5744156,['owner']='5f5c0b6f31fbcfa8de00000000000000',['row']=5763596,['before']='00000000fd0a00000100000015fe9ff174713f63030000004b1ac367b77c13ef000000000000000000000000000000000000000000000000000040400000000045bf1295b397435ce86f77b52a5a9704'},['assist']={['name']='WeaponAssistedReloadComponent',['group']=772928,['header']='ce437d614c444c4401000000ce437d61300300000100000000000000',['map']=773004,['owner']='5f5c0b6f31fbcfa80200000000000000',['row']=773356,['before']='3e0a00003d0a0000cdcccc3d0000000005000000010000000000803e666626bf0000000000000000000000000000b442a966ccec0000803e9a9959bf0000000000000000000000000000b44200000000333393bf0000000000000000000000000000b442ffffffff'},['rack']={['name']='HellpodRackComponent',['group']=6151256,['header']='56b18ba94c444c440100000056b18ba948a600000100000000000000',['map']=6152532,['owner']='2154e9abdcc4415f0400000000000000',['row']=6155796,['before']='5f5c0b6f31fbcfa8e3d1c67600000000cdccccbdcdccccbd000000000000b442000000000000000000000000e3f9cd12010000000200000000000000000000004c0f09e045e00ae65fa708ee0000000000000000cdccccbd0000b44200003443000000000000000000000000e3f9cd12000000000100000000000000000000005f5c0b6f31fbcfa8e3d1c67600000000cdccccbdcdccccbd000000000000b442000000000000000000000000e3f9cd12010000000200000000000000000000004c0f09e045e00ae65fa708ee0000000000000000cdccccbd0000b44200003443000000000000000000000000e3f9cd1200000000010000000000000000000000000000000000000027129de80000000000000000000000000000000000000000000000000000000000000000e3f9cd1201000000000000000000000000000000000000000000000027129de80000000000000000000000000000000000000000000000000000000000000000e3f9cd1201000000000000000000000000000000000000000000000027129de80000000000000000000000000000000000000000000000000000000000000000e3f9cd1201000000000000000000000000000000000000000000000027129de80000000000000000000000000000000000000000000000000000000000000000e3f9cd1201000000000000000000000000000000cdcccc3d0000000000000000000000000000000055aec0ba03d56be30ea0c0ac170500001805000000000000020000000000000000000000'}}
local PROJECTILE={['name']='PROJECTILE',['slot']=55108344,['group']=4,['groups']=1,['kind']=3175105218,['size']=95216,['count']=350,['stride']=272,['records']={{['id']=115,['index']=30,['before']='73000000ec6a9fe9b8742212c71aacd6b65cc022f9e5edf80000a0410100000000004d440000f0429a99993e0000803f010000000000000000000000d5000000cdcc0c3f00000000ee0ccc5336ff340500000000000000000ad7233c000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000007042010000009401000000000000000000000000000000000000cdcccc3d1000000003000000010000000000a642000070420000403f0000004000004041934851ed6504e0300000000000000000000080bf00000000000000000000000003000000000000003d0000000000000018953d390000000000000000000000000000000000000000',['mask_pointer']=false},{['id']=206,['index']=256,['before']='ce000000886c5d0969f200886952cdf1f5c84b7d5898656a0000704101000000000034430000c842000000009a99993e010000003333b33e00000000950000000000803e00000000b4494e1ae9d8d1a400000000000000000ad7233c0000000000000000000000000000000000000000596257c2e2189705000000000000000000000000000000000000a042010000007c01000000000000000000007c010000cdcccc3dcdcccc3d0400000003000000010000000000a642000070420000403f000000400000404179356d12116ee98c0000000000000000000080bf0000000000000000000000000200000000000000390000000000000018953d390000000000000000000000000000000000000000',['mask_pointer']=false},{['id']=284,['index']=31,['before']='1c0100001a8f1dd43300ad742e33a854e6114ea11203cc9d000020420100000000004d44000002439a99993e0000803f010000006666663f00000000ca0000000000803e00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000067655b18908acda60000b442010000007c01000000004040000000000000000000000041cdcccc3d0000000000000000010000000000a642000070420000403f0000004000004041934851ed6504e0300000000000000000000080bf00000000000000000000000002000000000000001d00000000000000d8e996ab0000000000000000000000000000000000000000',['mask_pointer']=false}}}
local EXPLOSION={['name']='EXPLOSION',['slot']=55110792,['group']=4,['groups']=1,['kind']=719988114,['size']=67800,['count']=422,['stride']=152,['records']={{['id']=380,['index']=124,['before']='7c0100005a0100000000000000000000000000400000e0400000004100000000000020420000000008ff0000000000000100000000000000fd2f9700661efe561aa86188050000001e000000000000001e000000c90000000e000000010000000000000000000000000000000000000000000000050000000000000002000000000000000000000000000042030000000000000000000000',['mask_pointer']=true},{['id']=404,['index']=127,['before']='9401000072010000000000000000000000000040000080400000b040000000000000a0420000000020ff00000000000001000000000000006cb1ec770bb9ce741aa8618805000000000000000000000000000000c90000000e000000020000000000000000000000000000000000000000000000050000000000000002000000000000000000000000000042030000000000000000000000',['mask_pointer']=true}}}
local DAMAGE={['name']='DAMAGE',['slot']=55108088,['group']=60,['groups']=2,['kind']=3769052400,['size']=49340,['count']=649,['stride']=76,['records']={{['id']=202,['index']=201,['before']='ca000000960000009600000002000000020000000200000000000000140000001e0000001e000000000000000000000000000000000000000000000000000000000000000000000000000000',['mask_pointer']=false},{['id']=213,['index']=212,['before']='d50000004501000004010000040000000400000004000000000000001e0000001e00000014000000000000000000000000000000000000000000000000000000000000000000000000000000',['mask_pointer']=false},{['id']=346,['index']=336,['before']='5a010000be000000be00000003000000000000000000000000000000140000001900000028000000000000000000000000000000000000000000000000000000000000000000000000000000',['mask_pointer']=false},{['id']=370,['index']=359,['before']='720100009600000096000000030000000000000000000000000000001e0000002800000028000000000000000000000000000000000000000000000000000000000000000000000000000000',['mask_pointer']=false}}}
local CHANGES={{['target']='rounds',['offset']=80,['before']='00000000',['after']='3c000000',['protected']=true},{['target']='rounds',['offset']=84,['before']='00000000',['after']='3c000000',['protected']=true},{['target']='rounds',['offset']=88,['before']='00000000',['after']='3c000000',['protected']=true},{['target']='reload',['offset']=1,['before']='00',['after']='01',['protected']=true},{['target']='reload',['offset']=56,['before']='00004040',['after']='00002040',['protected']=true},{['target']='assist',['offset']=0,['before']='3e0a0000',['after']='00000000',['protected']=true},{['target']='assist',['offset']=4,['before']='3d0a0000',['after']='00000000',['protected']=true},{['target']='rack',['offset']=556,['before']='02000000',['after']='01000000',['protected']=true},{['target']='damage_213',['offset']=4,['before']='45010000',['after']='77010000',['protected']=false},{['target']='damage_213',['offset']=8,['before']='04010000',['after']='54010000',['protected']=false},{['target']='damage_213',['offset']=12,['before']='04000000',['after']='05000000',['protected']=false},{['target']='damage_213',['offset']=16,['before']='04000000',['after']='05000000',['protected']=false},{['target']='damage_213',['offset']=20,['before']='04000000',['after']='05000000',['protected']=false},{['target']='damage_370',['offset']=4,['before']='96000000',['after']='b4000000',['protected']=false},{['target']='damage_346',['offset']=4,['before']='be000000',['after']='d2000000',['protected']=false},{['target']='explosion_380',['offset']=20,['before']='0000e040',['after']='00000041',['protected']=false}}

local function unhex(s) return (s:gsub('..',function(h) return string.char(tonumber(h,16)) end)) end
local function u32(s,o)
    if not s or o<0 or o+4>#s then return nil end
    local a,b,c,d=s:byte(o+1,o+4)
    return a+b*256+c*65536+d*16777216
end
local function fail(label) error('AC-8 validation failed: '..label..'. No edit applied.') end
local patch={}

local function component_row(api,entities,spec)
    local header=api.read(entities+spec.group,28)
    if not header or header~=unhex(spec.header) then fail(spec.name..' group header') end
    local owner=api.read(entities+spec.map,16)
    if not owner or owner~=unhex(spec.owner) then fail(spec.name..' owner map') end
    local ptr=entities+spec.row
    local actual=api.read(ptr,#spec.before/2)
    if not actual or actual~=unhex(spec.before) then fail(spec.name..' exact owner row') end
    return ptr
end

local function settings_rows(api,game,spec)
    local root=api.pointer(api.read(game+spec.slot,8),0)
    if not root or u32(api.read(root,4),0)~=spec.groups then fail(spec.name..' table pointer') end
    local group=root+spec.group
    local head=api.read(group,24)
    if not head or head:sub(1,4)~='LDLD' or u32(head,4)~=1
       or u32(head,8)~=spec.kind or u32(head,12)~=spec.size then
        fail(spec.name..' table header')
    end
    local payload=api.read(group+24,16)
    local rows=payload and api.pointer(payload,0)
    if not rows or u32(payload,8)~=spec.count or api.distance(rows,group+24)~=16 then
        fail(spec.name..' table rows')
    end
    local all=api.read(rows,spec.count*spec.stride)
    if not all then fail(spec.name..' table read') end
    local found,by_id={},{}
    for i=0,spec.count-1 do
        local id=u32(all,i*spec.stride)
        if not id or by_id[id] then fail(spec.name..' duplicate or invalid row') end
        by_id[id]=i
    end
    for _,expect in ipairs(spec.records) do
        local i=by_id[expect.id]
        if not i or i~=expect.index then fail(spec.name..' row '..expect.id..' index') end
        local actual=all:sub(i*spec.stride+1,(i+1)*spec.stride)
        local baseline=unhex(expect.before)
        if expect.mask_pointer then
            actual=actual:sub(1,40)..actual:sub(49)
            baseline=baseline:sub(1,40)..baseline:sub(49)
        end
        if actual~=baseline then fail(spec.name..' row '..expect.id..' exact baseline') end
        found[expect.id]=rows+i*spec.stride
    end
    return found,by_id,all
end

local function consumers(projectiles,explosions)
    local function projectile_ids(value)
        local out={}
        for id,i in pairs(projectiles.by_id) do
            local row=projectiles.all:sub(i*272+1,(i+1)*272)
            if u32(row,144)==value or u32(row,156)==value then out[#out+1]=id end
        end
        table.sort(out)
        return table.concat(out,',')
    end
    local function explosion_ids(value)
        local out={}
        for id,i in pairs(explosions.by_id) do
            local row=explosions.all:sub(i*152+1,(i+1)*152)
            if u32(row,4)==value then out[#out+1]=id end
        end
        table.sort(out)
        return table.concat(out,',')
    end
    if projectile_ids(380)~='206,284' or projectile_ids(404)~='115'
      or explosion_ids(346)~='380' or explosion_ids(370)~='404' then
        fail('APHET/FLAK consumer graph changed')
    end
end

function patch.apply(api,game)
    local owner=api.pointer(api.read(game+0x346bf98,8),0)
    local map=owner and api.pointer(api.read(owner+0xf12bd8,8),0)
    if not map then fail('entity manager pointer') end
    local entities=map-26151684
    local ptrs={}
    for key,spec in pairs(COMPONENTS) do ptrs[key]=component_row(api,entities,spec) end
    local projectile,pi,pa=settings_rows(api,game,PROJECTILE)
    local explosion,ei,ea=settings_rows(api,game,EXPLOSION)
    local damage=settings_rows(api,game,DAMAGE)
    consumers({by_id=pi,all=pa},{by_id=ei,all=ea})
    for id,p in pairs(projectile) do ptrs['projectile_'..id]=p end
    for id,p in pairs(explosion) do ptrs['explosion_'..id]=p end
    for id,p in pairs(damage) do ptrs['damage_'..id]=p end

    local writes={}
    for _,change in ipairs(CHANGES) do
        local base=ptrs[change.target]
        if not base then fail('missing target '..change.target) end
        local at=base+change.offset
        local before,after=unhex(change.before),unhex(change.after)
        if api.read(at,#before)~=before then fail(change.target..' +'..change.offset) end
        local protected=change.protected
        if protected then
            if not api.data_access(at,#after) then fail(change.target..' is not accessible') end
        elseif not api.writable(at,#after) then fail(change.target..' is not writable') end
        writes[#writes+1]={at=at,before=before,after=after,label=change.target,protected=protected}
    end
    local applied={}
    for _,item in ipairs(writes) do
        applied[#applied+1]=item
        local function write(change,bytes)
            if change.protected then return api.write_protected(change.at,bytes) end
            return api.write(change.at,bytes)
        end
        if not write(item,item.after) or api.read(item.at,#item.after)~=item.after then
            local rollback_ok=true
            for i=#applied,1,-1 do
                local old=applied[i]
                if not write(old,old.before) or api.read(old.at,#old.before)~=old.before then
                    rollback_ok=false
                end
            end
            error('AC-8 transaction failed at '..item.label..'; rollback '..(rollback_ok and 'verified' or 'FAILED'))
        end
    end
    return 'Applied: AC-8 backpackless candidate; '..#writes..' guarded field writes. FLAK explosion shared with JAR-5 HE.'
end

local function start(make_api)
    if rawget(_G,'AC8BackpacklessV1') then return end
    local state={version='0.1e-test',active=false,status='Waiting for first game update',diagnostics={}}
    _G.AC8BackpacklessV1=state
    local previous=update
    local callback
    local function log()
        pcall(function()
            local loader=rawget(_G,'CowboyBingusModLoader')
            local file=loader and loader.open_log and loader.open_log('AC8Backpackless.log')
            if file then
                file:write('AC8Backpackless v0.1e-test\nstatus='..state.status..'\n'..table.concat(state.diagnostics,'\n')..'\n')
                file:close()
            end
        end)
    end
    local deadline=0
    local worker=coroutine.create(function()
        local api=make_api()
        api.checkpoint=function(stage,force)
            state.status=stage
            if force or os.clock()>=deadline then coroutine.yield() end
        end
        local exe,game=api.module(nil),api.module('game.dll')
        assert(exe and game,'Game modules unavailable')
        assert(api.module_hash(exe)=='F5FEE03DCFDB2E553A4752C283590950AC13316B376D8196AA556FF0400D5F06','Unsupported executable; no edit applied')
        assert(api.module_hash(game)=='2E2C3B7C2500646DADD5F2B4C6E0504DBB7E7896139F64CDDC0D1813C718F51E','Unsupported game.dll; no edit applied')
        local ready_at=api.now()+30000
        state.status='Waiting for game tables';log()
        repeat coroutine.yield() until api.now()>=ready_at
        local peer_deadline=api.now()+120000
        while true do
            local blocker
            for _,peer in ipairs({
                {'FlagDamagePrototypeV1','Flag'},
                {'SaiFocusModV1','SAI'},
                {'AR11ArbitratorModV1','AR-11'},
                {'SterilizerArmorControlV1','Gas Overhaul'},
                {'RapidArcThrowerV1','ARC-3'},
            }) do
                local state=rawget(_G,peer[1])
                if state and not state.active then blocker=peer[2];break end
            end
            local profiles=rawget(_G,'ArsenalPreset01Runtime')
            if not blocker and profiles and profiles.phase~='ready' then blocker='Arsenal profiles' end
            local scorcher=rawget(_G,'ScorcherARRuntime')
            if not blocker and scorcher and scorcher.phase~='ready' then blocker='Scorcher runtime' end
            if not blocker then break end
            assert(api.now()<peer_deadline,'Companion not ready: '..blocker..'; no edit applied')
            state.status='Waiting for '..blocker;log()
            coroutine.yield()
        end
        state.status='Validating AC-8 owners, rows and consumers';log()
        return patch.apply(api,game)
    end)
    local function init()
        if coroutine.status(worker)=='dead' then return end
        deadline=os.clock()+0.0007
        local ok,message=coroutine.resume(worker)
        if not ok or coroutine.status(worker)=='dead' then
            state.active,state.status=ok,tostring(message)
            print('[AC8Backpackless] '..state.status)
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

start(make_api)
