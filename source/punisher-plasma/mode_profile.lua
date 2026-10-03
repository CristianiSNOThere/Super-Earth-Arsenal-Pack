-- Constructs private component bytes, without reading/writing the game. Native
-- cache registration and derived-state transactions belong to the adapter.
local ffi=require('ffi')
local M={}
local function word(value)
    local box=ffi.new('uint32_t[1]',value);return ffi.string(box,4)
end
local function float(value)
    local box=ffi.new('float[1]',value);return ffi.string(box,4)
end
local function replace(raw,offset,bytes)
    assert(offset>=0 and offset+#bytes<=#raw,'Profile edit exceeds component')
    return raw:sub(1,offset)..bytes..raw:sub(offset+#bytes+1)
end
local function u32(raw,offset)
    local box=ffi.new('uint32_t[1]');ffi.copy(box,raw:sub(offset+1,offset+4),4)
    return tonumber(box[0])
end
function M.build(stock,mode,shotgun_id,stage,sway_factor,normal_two_shot,normal_single_fast)
    stage=stage or 'firemode-and-pellets'
    assert(stage=='firemode-and-pellets' or stage=='full-design' or stage=='tuning-v017' or stage=='tuning-v014','Unsupported test stage')
    assert(mode==2 or mode==3,'Unsupported Punisher mode')
    assert(shotgun_id>=1 and shotgun_id<=350 and shotgun_id~=57
        and shotgun_id==math.floor(shotgun_id),'Invalid isolated shotgun projectile ID')
    assert(#stock.weapon==1232 and #stock.projectile==616 and #stock.magazine==160,'Unsupported component sizes')
    assert(u32(stock.projectile,0)==57 and stock.projectile:sub(9,12)==float(80),'Unexpected Punisher projectile source')
    assert(stock.weapon:sub(85,92)==float(8)..float(8),'Unexpected stock spread')
    assert(u32(stock.magazine,136)==10 and u32(stock.magazine,148)==8,'Unexpected magazine source')
    local weapon,projectile,magazine=stock.weapon,stock.projectile,stock.magazine
    if sway_factor then
        assert(sway_factor==0.5,'Unexpected sway tuning')
        local box=ffi.new('float[1]');ffi.copy(box,stock.weapon:sub(105,108),4)
        assert(box[0]>=0 and box[0]<=100,'Unsupported stock sway')
        weapon=replace(weapon,104,float(tonumber(box[0])*sway_factor))
    end
    local spread=mode==2 and 8 or 60
    local vertical=spread
    if stage=='tuning-v014'and mode==3 then spread=100;vertical=90 end
    weapon=replace(weapon,84,float(spread)..float(vertical))
    -- Native Burst is the second selector enum, but one firing event per pull
    -- is essential. Nine pellets belong to ProjectileInfo, never nine rounds.
    weapon=replace(weapon,140,word(1))
    weapon=replace(weapon,144,word(2)..word(3)..word(0)..word(0))
    if normal_two_shot then
        assert(stage=='tuning-v014','Two-shot normal requires current tuning')
        -- Semantic profile2 is normal, profile3 is pellets. Native selectors
        -- are Burst3 for normal and Semi2 for pellets; no input simulation.
        weapon=replace(weapon,140,word(mode==2 and 2 or 1))
        weapon=replace(weapon,144,word(3)..word(2)..word(0)..word(0))
    end
    if normal_single_fast then
        assert(normal_two_shot and normal_single_fast==120,'Unexpected single-shot rate')
        weapon=replace(weapon,140,word(1))
    end
    weapon=replace(weapon,184,word(3)..word(0))
    projectile=replace(projectile,0,word(mode==2 and 57 or shotgun_id))
    if stage=='tuning-v017' and mode==3 then projectile=replace(projectile,8,float(100)) end
    if stage=='tuning-v014'then projectile=replace(projectile,8,float(mode==2 and 60 or 100))end
    if normal_single_fast and mode==2 then projectile=replace(projectile,8,float(120)) end
    -- Burst MIDI can schedule extra notes independently of physical pellets.
    -- Keep native Semi MIDI; use the Accelerator's ordinary-event approach in
    -- shotgun mode. Audibility still requires a Punisher gameplay test.
    if mode==3 then projectile=replace(projectile,237,string.char(0)) end
    if stage=='full-design' then
        magazine=replace(magazine,136,word(20))
        magazine=replace(magazine,148,word(6))
    end
    return {weapon=weapon,projectile=projectile,magazine=magazine,
        derived_spread=float(spread)..float(vertical),mode=mode,
        native_rounds_per_event=1,desired_rounds_per_event=stage=='full-design' and mode==2 and 2 or 1,
        stage=stage,
        pellets=mode==2 and 1 or 9,rpm=normal_single_fast and mode==2 and 120 or stage=='tuning-v014'and(mode==2 and 60 or 100)or(stage=='tuning-v017' and mode==3 and 100 or 80),
        gameplay_verified=false,registry_ownership_verified=false}
end
return M

