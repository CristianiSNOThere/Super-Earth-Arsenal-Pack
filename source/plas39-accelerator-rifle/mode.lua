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

local WEAPON_HEADER = unhex('__WEAPON_HEADER__')
local CHARGE_HEADER = unhex('__CHARGE_HEADER__')
local WEAPON_TOTAL = __WEAPON_TOTAL__
local CHARGE_TOTAL = __CHARGE_TOTAL__
local WEAPON_MAP_COUNT = __WEAPON_MAP_COUNT__
local CHARGE_MAP_COUNT = __CHARGE_MAP_COUNT__
local WEAPON_MAP_INDEX = __WEAPON_MAP_INDEX__
local CHARGE_MAP_INDEX = __CHARGE_MAP_INDEX__
local WEAPON_RECORD_INDEX = __WEAPON_RECORD_INDEX__
local CHARGE_RECORD_INDEX = __CHARGE_RECORD_INDEX__
local WEAPON_STRIDE = __WEAPON_STRIDE__
local CHARGE_STRIDE = __CHARGE_STRIDE__
local OWNER = unhex('__OWNER_LITTLE_ENDIAN__')
local CHARGE_STOCK = unhex('__CHARGE_STOCK_ROW__')
local CHARGE_MIN_STOCK = unhex('__CHARGE_MIN_STOCK__')
local CHARGE_MIN_QUICK = unhex('__CHARGE_MIN_QUICK__')

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

