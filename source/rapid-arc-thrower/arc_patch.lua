local patch = {}

local DAMAGE_SIZE, DAMAGE_ROW_OFFSET, DAMAGE_ROW_SIZE = 49424, 15072, 76
local CHARGE_SIZE, CHARGE_GROUP_BACK, CHARGE_GROUP_SIZE = 216, 1644, 2724
local DAMAGE_ROW = '__DAMAGE_ROW__'
local CHARGE_ROW = '__CHARGE_ROW__'
local CHARGE_OWNER = '__CHARGE_OWNER__'
local CHARGE_HEADER = '__CHARGE_HEADER__'
local WEAPON_ROW = '__WEAPON_ROW__'
local WEAPON_OFFSET, WEAPON_SIZE = 26566228, 1232
local ARC_HEADER = '__ARC_HEADER__'
local ARC_ROW = '__ARC_ROW__'
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
    local values = { [(0.20/0.65)] = 'd9899d3e', [(0.22/0.65)] = 'd54aad3e', [(0.24/0.65)] = 'd10bbd3e', [0.8] = 'cdcc4c3f', [0.4] = 'cdcccc3e', [45] = '00003442' }
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
        {offset=48,bytes=float_word(0.8),writer='normal'},
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
        return 'Applied: ARC-3 range 55 -> 45 m; charge 1.0/1.1/1.2 -> 0.307692/0.338462/0.369231 s; damage 250/100 -> 226/90; Stun Medium buildup 8 -> 0.8; demolition/force strength/impulse 20/35/10 -> 4/25/2; camera climb 1.0/1.0 -> 0.4/0.4.'
    end)
    return ok,tostring(result)
end

return patch
