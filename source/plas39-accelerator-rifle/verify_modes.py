"""Offline checks of the actual resolved Lua patch; never opens the game process."""
import json
import re
from pathlib import Path
import build
from lua_runtime import Lua51

root = Path(__file__).resolve().parent
source, _ = build.resolve_mode_source()
charge = re.search(r"local CHARGE_STOCK = unhex\('([^']+)'\)", source)[1]
harness = r'''
local patch=(function() SOURCE end)()
local function hex(s) return (s:gsub('..',function(p) return string.char(tonumber(p,16)) end)) end
local function word(v) return string.char(v%256,math.floor(v/256)%256,math.floor(v/65536)%256,math.floor(v/16777216)%256) end
local mem={}
local function put(a,s) for i=1,#s do mem[a+i-1]=s:sub(i,i) end end
local api={identity=function(a) return a end,data_access=function() return true end}
api.read=function(a,n) local t={} for i=0,n-1 do t[#t+1]=assert(mem[a+i],'unmapped') end return table.concat(t) end
local fail
api.write_protected=function(a,s) if fail==a then fail=nil;return false end put(a,s);return true end
local weapon=string.rep('\0',192)
put(1000,weapon);put(1140,word(3));put(1144,word(3));put(1148,word(2));put(1184,word(3))
put(2000,weapon);put(2140,word(3));put(2144,word(3));put(2148,word(2));put(2184,word(3))
local stock=hex('__TEST_CHARGE__');put(3000,stock)
put(4000,string.rep('\0',40));put(4020,word(2));put(4024,word(123))
put(5000,string.rep('e',24));put(6000,word(2))
put(7000,string.rep('\0',264));put(7000,word(155));put(7008,hex('00800944'));put(7236,hex('01010000'))
put(8000,string.rep('s',168));put(8012,hex('0e6bdf3d'))
local item={projectile=7000,projectile_state=8000,id=440,mode=2,mode_address=6000,entity=5000,identity=api.read(5000,24),weapon=2000,charge=3000,charge_state=4000}
local items={item}
local native={instances=function() return items end,isolate=function() end,validate=function() end}
local plan={weapon_address=1000,charge_address=3000,last_modes={}}
assert(patch.synchronize(api,plan,native))
assert(api.read(1140,4)==word(1) and api.read(2140,4)==word(1))
assert(api.read(7008,4)==hex('00004843') and api.read(7236,4)==hex('01010000'))
assert(api.read(8012,4)==hex('9a99993e') and api.read(8000,12)==string.rep('s',12) and api.read(8016,152)==string.rep('s',152))
assert(api.read(3188,4)==word(0) and api.read(3000,4)==hex('0ad7233c'))
assert(api.read(4020,8)==string.rep('\0',8))
assert(api.read(3004,184)==stock:sub(5,188) and api.read(3192,24)==stock:sub(193))
item.mode=3;put(6000,word(3));assert(patch.synchronize(api,plan,native))
assert(api.read(3000,216)==stock and api.read(2140,4)==word(1))
assert(api.read(7008,4)==hex('00800944') and api.read(7236,4)==hex('01000000'))
assert(api.read(8012,4)==hex('0e6bdf3d'))
item.mode=2;put(6000,word(2));fail=3188
local ok,reason=patch.synchronize(api,plan,native)
assert(not ok and reason:find('original values restored',1,true))
assert(api.read(3000,216)==stock and plan.last_modes[440]==3)
assert(patch.synchronize(api,plan,native))
local other={} for k,v in pairs(item) do other[k]=v end
other.id=441;other.mode=3;other.mode_address=6010;put(6010,word(3));items={item,other}
local before=api.read(3000,216)
local accepted,err=pcall(patch.synchronize,api,plan,native)
assert(not accepted and tostring(err):find('share charge data',1,true))
assert(api.read(3000,216)==before)
print('PASS: remembered Semi, cached burst limit, charge repetition switching, unrelated fields, pending repeat cancellation, rollback, shared-row conflict')
'''.replace('__TEST_CHARGE__', charge).replace('SOURCE', source)
Lua51().run(harness.encode())
startup = (root / 'startup.lua').read_text()
startup_test = r'''
local start=(function() SOURCE end)()
local calls,sync=0,0
update=function(x) calls=calls+1;return x,nil,'tail' end
local api={module=function(n) return n or 'exe' end,module_hash=function(n) return n=='exe' and 'F5FEE03DCFDB2E553A4752C283590950AC13316B376D8196AA556FF0400D5F06' or '2E2C3B7C2500646DADD5F2B4C6E0504DBB7E7896139F64CDDC0D1813C718F51E' end}
local patch={prepare=function() return {} end,synchronize=function() sync=sync+1;return true,'Semi',false,1 end}
start(function() return api end,patch,{})
local a,b,c=update(42)
assert(calls==1 and sync==2 and a==42 and b==nil and c=='tail')
assert(Plas39FireModeV1.mode=='Semi')
print('PASS: startup reads selection immediately, callback executes once and preserves nil returns')
'''.replace('SOURCE', startup)
Lua51().run(startup_test.encode())

native_source, guards = build.resolve_native_source()
fixture = r"""
+bit=require('bit')
+local native=(function() SOURCE end)()
+local mem={}
+local function word(v) return string.char(v%256,math.floor(v/256)%256,math.floor(v/65536)%256,math.floor(v/16777216)%256) end
+local function ptr(v) return word(v)..word(0) end
+local function put(a,s) for i=1,#s do mem[a+i-1]=s:sub(i,i) end end
+local function hex(s) return (s:gsub('..',function(p) return string.char(tonumber(p,16)) end)) end
+local api={module=function() return 100000 end,byte_pointer=function(v) return v end}
+api.read=function(a,n) local t={} for i=0,n-1 do t[#t+1]=assert(mem[a+i],'unmapped '..tostring(a+i)) end return table.concat(t) end
+api.pointer=function(s,o) local a,b,c,d=s:byte(o+1,o+4);local v=a+b*256+c*65536+d*16777216;return v~=0 and v or nil end
+GUARDS
+put(100000+0x346bf98,ptr(200000))
+put(200000+0xf12bd8,ptr(500000));put(200000+0xf12ad8,ptr(600000));put(200000+0xf12e80,ptr(700000))
+put(700000+MAP_SLOT*16,hex('5e7f47af911f0630')..word(136)..word(0))
+local target=native.prepare(api)
+put(100000+0x3326ce0,ptr(1000000));put(100000+0x3326c20,ptr(1100000));put(100000+0x33266d8,ptr(1200000))
+put(1000000,string.rep('\0',192));put(1100000,string.rep('\0',160));put(1200000,string.rep('\0',224))
+put(1000000+0x10,word(1));put(1000000+0x1c,word(1));put(1000000+0x48,ptr(1300000));put(1000000+0x60,ptr(1400000));put(1000000+0xb0,ptr(1500000))
+put(1300000,ptr(1600000));put(1600000,hex('5e7f47af911f0630')..word(440)..word(0)..word(0)..word(1));put(1400000,word(2))
+local function map(manager,offset,address)
+ put(manager+offset,ptr(address)..word(1)..word(4294967295)..word(2));put(address,word(440)..word(0))
+end
+map(1000000,0x30,1700000);map(1000000,0x70,1800000);put(1000000+0xa8,word(1))
+put(1200000+0xc8,word(1));map(1200000,0x90,1900000);put(1200000+0xd0,ptr(2000000))
+map(1200000,0x50,2400000);put(1200000+0x38,word(1));put(1200000+0x68,ptr(2500000));put(2500000,ptr(1600000));put(1200000+0x78,ptr(2600000))
+map(1100000,0x20,2100000);put(1100000+0xc,word(1));put(1100000+0x10,word(1));put(1100000+0x38,ptr(2200000));put(2200000,ptr(1600000));put(1100000+0x40,ptr(2300000))
+local plan={native=target,weapon_address=501000,charge_address=601000,projectile_address=target.projectile_address}
+local item=native.instances(api,plan)[1]
+assert(item.id==440 and item.mode==2 and item.weapon==1500000 and item.projectile==2000000 and item.charge==601000)
+put(1400000,word(3));assert(native.instances(api,plan)[1].mode==3)
+print('PASS: exact resolved native resolver, remembered enum, cached projectile and WeaponData index zero')
+""".replace('\n+', '\n').replace('MAP_SLOT',str(0x30061f91af477f5e%542))
guard_setup='\n'.join("put(100000+%d,hex('%s'))"%(g['rva'],g['bytes']) for g in guards)
fixture=fixture.replace('GUARDS',guard_setup).replace('SOURCE',native_source)
Lua51().run(fixture.encode())

(root / 'offline-verification-v1.1.8-core.json').write_text(json.dumps({
    'result': 'passed', 'runtime': 'game LuaJIT in separate offline process',
    'checks': ['remembered Semi initialization', 'cached and source native burst limit',
               'charge min and repetitions in both modes', 'unrelated charge bytes preserved',
               'Semi 200 RPM and Burst stock RPM restoration', 'mode-specific MIDI flag', 'native resolver and cached projectile index zero', 'queued repetition cancellation', 'failed write rollback',
               'conflicting shared charge data refused', 'startup update callback and returns'],
    'gameplay_tested': False, 'game_process_modified': False,
}, indent=2) + '\n')


