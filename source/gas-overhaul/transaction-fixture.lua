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
    if s:sub(2381,2456)~=unhex('1d000000010000000100000005000000050000000500000000000000050000000a00000005000000050000002b0000000000003f2d0000000000003f00000000000000000000000000000000') then return nil,'Gas Overhaul record 29 mismatch' end
    if s:sub(5421,5496)~=unhex('410000008a02000013010000050000000500000005000000050000001e0000005000000023000000000000002a000000000048422c0000000000484200000000000000000000000000000000') then return nil,'Gas Overhaul record 65 mismatch' end
    if s:sub(5497,5572)~=unhex('420000000300000003000000060000000000000000000000000000001e0000000a0000000a000000050000002a0000000000c8422c0000000000c84200000000000000000000000000000000') then return nil,'Gas Overhaul record 66 mismatch' end
    if s:sub(5573,5648)~=unhex('430000003c0000000a00000004000000040000000300000000000000010000000100000001000000050000002a0000000000c8422c0000000000c84200000000000000000000000000000000') then return nil,'Gas Overhaul record 67 mismatch' end
    if s:sub(28981,29056)~=unhex('87010000000000000000000006000000000000000000000000000000320000000a00000028000000050000002a0000000000c8422c0000000000c84200000000000000000000000000000000') then return nil,'Gas Overhaul record 391 mismatch' end
    if s:sub(33465,33540)~=unhex('bf010000000000000000000006000000000000000000000000000000320000000a00000028000000050000002a0000000000c8422c0000000000c84200000000000000000000000000000000') then return nil,'Gas Overhaul record 447 mismatch' end
    if s:sub(33541,33616)~=unhex('c00100000000000000000000060000000000000000000000000000001e0000000a00000014000000050000002a0000000000c8422c0000000000c84200000000000000000000000000000000') then return nil,'Gas Overhaul record 448 mismatch' end
    if s:sub(33617,33692)~=unhex('c10100000300000003000000060000000000000000000000000000001e0000000a0000000a000000050000002a0000000000c8422c0000000000c84200000000000000000000000000000000') then return nil,'Gas Overhaul record 449 mismatch' end
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
        {offset=2440,bytes=pack32(55)..unhex('0000803f'),write='normal'},
        {offset=5480,bytes=pack32(55)..unhex('0000803f'),write='normal'},
        {offset=5556,bytes=pack32(55)..unhex('0000803f'),write='normal'},
        {offset=5632,bytes=pack32(55)..unhex('0000803f'),write='normal'},
        {offset=29040,bytes=pack32(55)..unhex('0000803f'),write='normal'},
        {offset=33524,bytes=pack32(55)..unhex('0000803f'),write='normal'},
        {offset=33600,bytes=pack32(55)..unhex('0000803f'),write='normal'},
        {offset=33676,bytes=pack32(55)..unhex('0000803f'),write='normal'},

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
        return 'Applied: TX-41 Sterilizer gas 25 -> 45 DPS; Helldiver incoming Gas multiplier 1.3 -> 0.7333; magazine 125 -> 175; Gas MKII / confusion buildup 0.5 -> 0.75; Gas Overhaul: Acid Storm armor reduction added to player gas hit records; duration 1 -> 15 seconds.'
    end)
    return ok,tostring(result)
end


patch._set_plans=function(plans) find_damage=function() return plans[1] end; validate_one=function(_,_,_,label) return plans[({magazine=2,["acid status"]=3,["Helldiver health"]=4})[label]] end end
return patch
end)()

local function check(fail)
 local blobs={[1000]=string.rep('A',16),[2000]=string.rep('B',16),[3000]=string.rep('C',16),[4000]=string.rep('D',16)}
 local saved={};local plans={}
 for i,base in ipairs({1000,2000,3000,4000}) do
  saved[base]=blobs[base]
  plans[i]={address=base,size=16,source=blobs[base],writes={{offset=0,bytes='1234',write='normal'}}}
 end
 plans[1].writes={{offset=0,bytes='1111',write='normal'},{offset=4,bytes='2222',write='normal'},{offset=8,bytes='3333',write='normal'}}
 local count=0;local failed=false
 local api={candidates=function()return{}end,record_candidates=function()return{{},{},{}}end,
 read=function(address,n)return blobs[address]end}
 local function write(address,bytes)
  count=count+1
  for base,blob in pairs(blobs) do
   if address>=base and address+#bytes<=base+16 then
    local o=address-base
    if count==fail and not failed then
      failed=true;blobs[base]=blob:sub(1,o)..bytes:sub(1,2)..blob:sub(o+3);return false
    end
    blobs[base]=blob:sub(1,o)..bytes..blob:sub(o+#bytes+1);return true
   end
  end
  return false
 end
 api.write=write;api.write_protected=write
 patch._set_plans(plans)
 local ok,reason=patch.apply(api,0)
 if fail then
  assert(not ok and reason:find('restored=true',1,true),reason)
  for base,blob in pairs(saved)do assert(blobs[base]==blob,'Rollback failed')end
 else assert(ok,reason);assert(blobs[1000]=='111122223333AAAA')end
end
check(nil);for i=1,6 do check(i)end
