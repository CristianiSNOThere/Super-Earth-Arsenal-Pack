"""Exercise resolved native cache registration and mode patch in offline game LuaJIT."""
import json
import re
from pathlib import Path
import build
from lua_runtime import Lua51

root = Path(__file__).resolve().parent
mode, _ = build.resolve_mode_source()
native, guards = build.resolve_native_source()
charge = re.search(r"local CHARGE_STOCK = unhex\('([^']+)'\)", mode)[1]
fixture = r'''
bit=require('bit')
local native=(function() NATIVE_SOURCE end)()
local patch=(function() MODE_SOURCE end)()
local mem={}
local function word(v) return string.char(v%256,math.floor(v/256)%256,math.floor(v/65536)%256,math.floor(v/16777216)%256) end
local function ptr(v) return word(v)..word(0) end
local function hex(s) return (s:gsub('..',function(p) return string.char(tonumber(p,16)) end)) end
local function put(a,s) for i=1,#s do mem[a+i-1]=s:sub(i,i) end end
local api={module=function() return 100000 end,byte_pointer=function(v) return v end,identity=function(v) return v end,data_access=function() return true end}
api.read=function(a,n) local t={} for i=0,n-1 do t[#t+1]=assert(mem[a+i],'unmapped '..tostring(a+i)) end return table.concat(t) end
api.pointer=function(s,o) local a,b,c,d=s:byte(o+1,o+4);local v=a+b*256+c*65536+d*16777216;return v~=0 and v or nil end
local fail,writes
api.write_protected=function(a,s) writes=(writes or 0)+1;if fail==a then fail=nil;return false end;put(a,s);return true end
GUARDS
put(100000+0x346bf98,ptr(200000))
put(200000+0xf12bd8,ptr(500000));put(200000+0xf12ad8,ptr(600000));put(200000+0xf12e80,ptr(700000))
put(700000+290*16,hex('5e7f47af911f0630')..word(136)..word(0))
local target=native.prepare(api)
local source_weapon,source_charge,source_projectile=3000000,3100000,target.projectile_address
local function weapon(a)
 put(a,string.rep('\0',1232));put(a+140,word(3));put(a+144,word(3));put(a+148,word(2));put(a+184,word(3))
end
weapon(source_weapon)
local stock=hex('STOCK_CHARGE');put(source_charge,stock)
local function projectile(a)
 put(a,string.rep('\0',616));put(a,word(155));put(a+8,hex('00800944'));put(a+236,hex('01010000'))
end
projectile(source_projectile)
local stock_projectile=api.read(source_projectile,616)
local dm,cm,pm=1000000,1100000,1200000
put(100000+0x3326ce0,ptr(dm));put(100000+0x3326c20,ptr(cm));put(100000+0x33266d8,ptr(pm))
put(dm,string.rep('\0',224));put(cm,string.rep('\0',224));put(pm,string.rep('\0',224))
local function map(m,o,a,empty)
 put(m+o,ptr(a)..word(16)..word(empty)..word(2))
 for i=0,15 do put(a+i*8,word(empty)..word(4294967295)) end
end
local function insert(m,o,key,value)
 local header=api.read(m,224);local a=api.pointer(header,o)
 local cap=16;local at=(key*2)%cap
 for probe=0,15 do
  local p=a+(at+probe)%cap*8
  local row=api.read(p,8)
  if row:sub(1,4)==header:sub(o+13,o+16) or row:sub(1,4)==word(key) then put(p,word(key)..word(value));return end
 end
 error('full')
end
-- Both owned active rifles share stock source rows before the patch. A third
-- dropped rifle has WeaponData but no owned native charge state.
put(dm+0x10,word(3));put(dm+0x1c,word(3));put(dm+0x48,ptr(1300000));put(dm+0x60,ptr(1400000));put(dm+0xb0,ptr(1500000));put(dm+0xa8,word(3))
map(dm,0x30,1700000,4294967295);map(dm,0x70,1800000,0)
put(cm+4,word(8));put(cm+0xc,word(2));put(cm+0x10,word(2));put(cm+0x38,ptr(2200000));put(cm+0x40,ptr(2300000));put(cm+0x90,ptr(2400000))
put(2400000,string.rep('\0',216*8));put(2300000,string.rep('\0',80))
map(cm,0x20,2100000,4294967295);map(cm,0x50,2500000,0);map(cm,0x70,2600000,4294967295)
put(pm+0x30,word(8));put(pm+0xd0,ptr(2700000));put(2700000,string.rep('\0',616*8))
map(pm,0x90,2800000,0);map(pm,0xb0,2900000,4294967295)
map(pm,0x50,3200000,4294967295);put(pm+0x38,word(3));put(pm+0x68,ptr(3300000));put(pm+0x78,ptr(3400000))
for i=0,2 do
 local entity=1600000+i*100
 put(entity,hex('5e7f47af911f0630')..word(440+i)..word(0)..word(0)..word(1))
 put(1300000+i*8,ptr(entity));put(1400000+i*12,word(i==1 and 3 or 2)..word(0)..word(0))
 weapon(1500000+i*1232);insert(dm,0x30,440+i,i);insert(dm,0x70,440+i,i)
 put(3300000+i*8,ptr(entity));insert(pm,0x50,440+i,i)
 put(3400000+i*168,string.rep('s',168));put(3400012+i*168,hex('0e6bdf3d'))
 if i<2 then put(2200000+i*8,ptr(entity));insert(cm,0x20,440+i,i) end
end
local plan={native=target,weapon_address=source_weapon,charge_address=source_charge,projectile_address=source_projectile,last_modes={}}
assert(#native.instances(api,plan)==2,'dropped Semi entity must be excluded')
fail=cm+0x88
local initial_ok,initial_reason=patch.synchronize(api,plan,native)
assert(not initial_ok and initial_reason:find('original values restored',1,true))
assert(api.read(cm+0x88,4)==word(0) and api.read(pm+0xc8,4)==word(0))
assert(api.read(2400000,216*8)==string.rep('\0',216*8))
assert(api.read(source_charge,216)==stock and #native.instances(api,plan)==2)
assert(patch.synchronize(api,plan,native))
local items=native.instances(api,plan)
assert(items[1].charge~=items[2].charge and items[1].projectile~=items[2].projectile)
assert(items[1].charge_cached and items[2].charge_cached and items[1].projectile_cached)
assert(api.read(source_charge,216)==stock and api.read(source_projectile,616)==stock_projectile,'source firing rows changed')
assert(api.read(items[1].charge,4)==hex('0ad7233c') and api.read(items[1].charge+188,4)==word(0))
assert(api.read(items[2].charge,216)==stock and api.read(items[2].projectile+236,4)==hex('01000000'))
assert(api.read(items[1].projectile+8,4)==hex('00004843') and api.read(items[2].projectile+8,4)==hex('00800944'))
assert(api.read(items[1].projectile_state+12,4)==hex('9a99993e') and api.read(items[2].projectile_state+12,4)==hex('0e6bdf3d'))
assert(api.read(items[1].projectile_state,12)==string.rep('s',12) and api.read(items[1].projectile_state+16,152)==string.rep('s',152),'unrelated firing state or remaining cooldown changed')
writes=0;assert(patch.synchronize(api,plan,native));assert(writes==0,'unchanged frame should perform no writes')
-- Remembered mode switches affect only the corresponding private firing rows.
put(1400000,word(3));put(1400012,word(2));assert(patch.synchronize(api,plan,native))
assert(api.read(items[1].charge,216)==stock and api.read(items[2].charge+188,4)==word(0))
assert(api.read(source_charge,216)==stock and api.read(source_projectile,616)==stock_projectile)
assert(api.read(items[1].projectile_state+12,4)==hex('0e6bdf3d') and api.read(items[2].projectile_state+12,4)==hex('9a99993e'))
-- Failed switch rolls back and preserves last successful selection.
put(1400000,word(2));fail=items[1].charge+188
local ok,reason=patch.synchronize(api,plan,native)
assert(not ok and reason:find('original values restored',1,true))
assert(api.read(items[1].charge,216)==stock and plan.last_modes[440]==3)
assert(patch.synchronize(api,plan,native))
-- Fail at the new cadence edit after component edits: the entire switch rolls back.
put(1400000,word(3));fail=items[1].projectile_state+12
local interval_ok,interval_reason=patch.synchronize(api,plan,native)
assert(not interval_ok and interval_reason:find('original values restored',1,true))
assert(api.read(items[1].projectile+8,4)==hex('00004843') and api.read(items[1].projectile_state+12,4)==hex('9a99993e') and plan.last_modes[440]==2)
put(1400000,word(2));assert(patch.synchronize(api,plan,native))
-- Verify both native reverse-index maps, required by teardown compaction.
local function value(m,o,key)
 local head=api.read(m,224);local a=api.pointer(head,o)
 for i=0,15 do local row=api.read(a+i*8,8);if row:sub(1,4)==word(key) then return row:sub(5,8) end end
end
assert(value(cm,0x70,0)==word(440) and value(cm,0x70,1)==word(441))
assert(value(pm,0xb0,0)==word(440) and value(pm,0xb0,1)==word(441))
-- An unowned charge instance must not receive a local override.
put(cm+0x10,word(1));assert(#native.instances(api,plan)==1)
-- Removing/compacting first entity using the traced native map contract.
local function erase(m,o,key)
 local head=api.read(m,224);local a=api.pointer(head,o)
 local empty=head:sub(o+13,o+16);local at
 for i=0,15 do if api.read(a+i*8,4)==word(key) then at=i;break end end
 assert(at);local index=api.read(a+at*8+4,4)
 put(a+at*8,empty)
 local hole=at
 for step=1,15 do
  local next=(at+step)%16;local row=api.read(a+next*8,8)
  if row:sub(1,4)==empty then break end
  local b,c,d,e=row:byte(1,4);local home=((b+c*256+d*65536+e*16777216)*2)%16
  if (next-hole)%16<=(next-home)%16 then put(a+hole*8,row);put(a+next*8,empty);hole=next end
 end
 return index
end
local function remove_and_compact(m,forward,reverse,count,array,stride)
 local head=api.read(m,224)
 assert(erase(m,forward,440)==word(0));assert(erase(m,reverse,1)==word(441))
 local rows=api.pointer(head,array);put(rows,api.read(rows+stride,stride))
 insert(m,forward,441,0);insert(m,reverse,0,441)
 put(m+count,word(1))
end
remove_and_compact(cm,0x50,0x70,0x88,0x90,216)
remove_and_compact(pm,0x90,0xb0,0xc8,0xd0,616)
-- Relink the owned active slot to the surviving weapon. Inactive 440 keeps Semi.
erase(cm,0x20,440);insert(cm,0x20,441,0);put(2200000,ptr(1600100));put(cm+0xc,word(1))
assert(patch.synchronize(api,plan,native));items=native.instances(api,plan)
assert(#items==1 and items[1].id==441 and items[1].charge==2400000 and items[1].projectile==2700000)
-- Pick up the formerly dropped entity: reserve its own rows and cancel repeats.
put(cm+0xc,word(2));put(cm+0x10,word(2));insert(cm,0x20,442,1);put(2200008,ptr(1600200));put(2300060,word(2));put(2300064,word(123))
assert(patch.synchronize(api,plan,native));items=native.instances(api,plan)
assert(#items==2 and api.read(2300060,8)==string.rep('\0',8))
assert(items[1].charge~=items[2].charge and api.read(cm+0x88,4)==word(2))
-- Cache capacity and stale snapshot failures publish nothing.
put(cm+4,word(1));writes=0
local accepted,err=pcall(patch.synchronize,api,plan,native)
assert(not accepted and tostring(err):find('capacity',1,true) and writes==0)
put(cm+4,word(8));native.instances(api,plan);put(pm+0x30,word(7))
accepted,err=pcall(native.validate,api,plan,items)
assert(not accepted and tostring(err):find('manager changed',1,true))
print('PASS: mixed active modes isolated; dropped/unowned instances ignored; source rows preserved; no idle writes; switch rollback; reverse maps; native compaction; pickup; capacity/stale guards')
put(items[1].projectile_state+12,word(0));writes=0
accepted,err=pcall(patch.synchronize,api,plan,native)
assert(not accepted and tostring(err):find('interval changed externally',1,true) and writes==0)
put(items[1].projectile_state+12,hex('9a99993e'))
put(3300008,ptr(1600000));writes=0
accepted,err=pcall(patch.synchronize,api,plan,native)
assert(not accepted and tostring(err):find('state owner changed',1,true) and writes==0)
print('PASS: per-instance cadence, preserved cooldown/state, cadence-write rollback, unexpected interval and mismatched state owner refusal')
'''
setup = '\n'.join("put(100000+%d,hex('%s'))" % (g['rva'], g['bytes']) for g in guards)
fixture = fixture.replace('GUARDS', setup).replace('STOCK_CHARGE', charge).replace('NATIVE_SOURCE', native).replace('MODE_SOURCE', mode)
Lua51().run(fixture.encode())
(root / 'offline-verification-v1.1.8-isolation.json').write_text(json.dumps({
    'result': 'passed', 'runtime': 'game LuaJIT in separate offline process',
    'checks': ['mixed active Semi/Burst uses distinct charge/projectile caches',
               'dropped and unowned instances excluded', 'source firing rows preserved',
               'unchanged frame has zero writes', 'initial cache-publication failure rollback', 'independent switches and failed switch rollback',
               'forward and reverse map registration', 'traced native compaction modeled',
               'pickup and queued-repeat cancellation', 'capacity and stale-manager guards',
               'per-instance derived cadence in both modes', 'remaining cooldown and unrelated state preserved',
               'cadence-write failure rolls back component changes', 'unexpected interval and mismatched projectile state owner refusal'],
    'gameplay_tested': False, 'game_process_modified': False,
}, indent=2) + '\n')

