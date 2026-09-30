"""Offline Lua and package tests; never attaches to the game process."""
import ctypes
import hashlib
import json
from pathlib import Path
import struct
import zipfile

ROOT = Path(__file__).resolve().parent
PROJECT = ROOT.parents[1]
DATA = PROJECT / "work/flag-mod/filediver-master/datalibrary"
GAME_LUA = r"D:\SteamLibrary\steamapps\common\Helldivers 2\bin\lua51.dll"

dll = ctypes.CDLL(GAME_LUA)
dll.luaL_newstate.restype = ctypes.c_void_p
dll.luaL_openlibs.argtypes = [ctypes.c_void_p]
dll.luaL_loadbuffer.argtypes = [ctypes.c_void_p,ctypes.c_char_p,ctypes.c_size_t,ctypes.c_char_p]
dll.luaL_loadbuffer.restype = ctypes.c_int
dll.lua_pcall.argtypes = [ctypes.c_void_p,ctypes.c_int,ctypes.c_int,ctypes.c_int]
dll.lua_pcall.restype = ctypes.c_int
dll.lua_tolstring.argtypes = [ctypes.c_void_p,ctypes.c_int,ctypes.POINTER(ctypes.c_size_t)]
dll.lua_tolstring.restype = ctypes.c_char_p
dll.lua_close.argtypes = [ctypes.c_void_p]


def run(code: str, execute: bool = False) -> None:
    state = dll.luaL_newstate()
    dll.luaL_openlibs(state)
    try:
        raw = code.encode()
        rc = dll.luaL_loadbuffer(state,raw,len(raw),b"rapid-arc-offline-test")
        if rc == 0 and execute:
            rc = dll.lua_pcall(state,0,0,0)
        if rc:
            raise AssertionError(dll.lua_tolstring(state,-1,None).decode(errors="replace"))
    finally:
        dll.lua_close(state)


def main():
    for name in ("arc_patch.lua","patch_resolved.lua","windows.lua","startup.lua","entry.lua"):
        run((ROOT/name).read_text(encoding="utf-8"))
    damage = (DATA/"generated_damage_settings.dl_bin").read_bytes()
    entities = (DATA/"generated_entities.dl_bin").read_bytes()
    arc = (DATA/"generated_arc_settings.dl_bin").read_bytes()
    group = entities[7565064:7565064+2724]
    weapon = entities[26566228:26566228+1232]
    assert len(group)==2724 and group[1644:1644+216]==entities[7566708:7566708+216]
    patch=(ROOT/"patch_resolved.lua").read_text(encoding="utf-8")
    lua = ("local patch=(function()\n"+patch+"\nend)()\n"
           "local DAMAGE=__DAMAGE__\nlocal GROUP=__GROUP__\nlocal WEAPON=__WEAPON__\nlocal ARC=__ARC__\n".replace("__DAMAGE__", "'"+"".join("\\%03d"%b for b in damage)+"'").replace("__GROUP__", "'"+"".join("\\%03d"%b for b in group)+"'").replace("__WEAPON__", "'"+"".join("\\%03d"%b for b in weapon)+"'").replace("__ARC__", "'"+"".join("\\%03d"%b for b in arc)+"'"))
    lua += r'''
local function word(s,o) local a,b,c,d=s:byte(o+1,o+4);return a+b*256+c*65536+d*16777216 end
local function replace(s,o,v) return s:sub(1,o)..v..s:sub(o+#v+1) end
local function le64(n) return string.char(n%256,math.floor(n/256)%256,math.floor(n/65536)%256,math.floor(n/16777216)%256,0,0,0,0) end
local ARC_RUNTIME=replace(ARC,28,le64(300044))
local function make()
  local damage,group,weapon,arc=DAMAGE,GROUP,WEAPON,ARC_RUNTIME
  local base,origin,charge=1000,100000,101644
  local arcbase=300000
  local weapon_addr=charge-7566708+26566228
  local writes=0
  local api={}
  function api.identity(p) return p end
  function api.candidates(_,signature,row_offset,header)
    assert(signature==nil and row_offset==nil,'bulk signature fallback was requested')
    if header then assert(header==ARC:sub(1,16));return {arcbase} end
    return {base}
  end
  function api.scan_private_many() error('multi-gigabyte private scan is forbidden') end
  function api.private_regions() return {
    {base=50,size=46616576,protection=4},
    {base=60,size=39051264,protection=2},
    {base=charge-7566708,size=46616576,protection=2},
  } end
  function api.writable(p,n) return (p==base and n==#damage) or (p==arcbase and n==#arc) end
  function api.data_access(p,n) return (p==charge and n==216) or (p==weapon_addr and n==1232) or (p==arcbase and n==#arc) end
  function api.pointer(s,o) if o==84 then return base+100 end;if o==28 then return word(s,o) end end
  function api.distance(a,b) return a-b end
  function api.read(p,n)
    if p>=base and p+n<=base+#damage then return damage:sub(p-base+1,p-base+n) end
    if p>=origin and p+n<=origin+#group then return group:sub(p-origin+1,p-origin+n) end
    if p>=weapon_addr and p+n<=weapon_addr+#weapon then return weapon:sub(p-weapon_addr+1,p-weapon_addr+n) end
    if p>=arcbase and p+n<=arcbase+#arc then return arc:sub(p-arcbase+1,p-arcbase+n) end
    return nil
  end
  function api.write(p,v)
    if p>=arcbase and p+#v<=arcbase+#arc then arc=replace(arc,p-arcbase,v);writes=writes+1;return true end
    if p<base or p+#v>base+#damage then return false end
    damage=replace(damage,p-base,v);writes=writes+1;return true
  end
  function api.write_protected(p,v)
    if p>=arcbase and p+#v<=arcbase+#arc then arc=replace(arc,p-arcbase,v);writes=writes+1;return true end
    if p>=weapon_addr and p+#v<=weapon_addr+#weapon then weapon=replace(weapon,p-weapon_addr,v);writes=writes+1;return true end
    if p<charge or p+#v>charge+216 then return false end
    group=replace(group,p-origin,v);writes=writes+1;return true
  end
  return api,{base=base,origin=origin,charge=charge,damage=function() return damage end,
    group=function() return group end,weapon=function() return weapon end,arc=function() return arc end,writes=function() return writes end,
    change_damage=function(o,v) damage=replace(damage,o,v) end,
    change_group=function(o,v) group=replace(group,o,v) end,
    change_weapon=function(o,v) weapon=replace(weapon,o,v) end,
    change_arc=function(o,v) arc=replace(arc,o,v) end}
end
local api,f=make()
local ok,msg=patch.apply(api,0)
assert(ok,msg)
local d,g,w,r=f.damage(),f.group(),f.weapon(),f.arc()
assert(word(d,15076)==226 and word(d,15080)==90)
assert(word(d,15100)==4 and word(d,15104)==25 and word(d,15108)==2)
assert(d:sub(15121,15124)==string.char(205,204,76,63))
assert(g:sub(1645,1648)==string.char(217,137,157,62))
assert(g:sub(1669,1672)==string.char(213,74,173,62))
assert(g:sub(1693,1696)==string.char(209,11,189,62))
assert(w:sub(77,80)==string.char(205,204,204,62))
assert(w:sub(81,84)==string.char(205,204,204,62))
assert(r:sub(53,56)==string.char(0,0,52,66))
local allowed={}
for _,o in ipairs({15076,15080,15100,15104,15108,15120}) do for i=o+1,o+4 do allowed[i]=true end end
for i=1,#DAMAGE do if d:byte(i)~=DAMAGE:byte(i) then assert(allowed[i],'damage edit escaped target row') end end
for i=1,#GROUP do if g:byte(i)~=GROUP:byte(i) then
  assert((i>=1645 and i<=1648) or (i>=1669 and i<=1672) or (i>=1693 and i<=1696),'charge edit escaped target row') end end
for i=1,#WEAPON do if w:byte(i)~=WEAPON:byte(i) then
  assert(i>=77 and i<=84,'recoil edit escaped target fields') end end
for i=1,#ARC_RUNTIME do if r:byte(i)~=ARC_RUNTIME:byte(i) then
  assert(i>=53 and i<=56,'range edit escaped target field') end end
assert(f.writes()==12)
do
  local a,x=make()
  x.change_group(1644+184,string.char(1))
  local yes,reason=patch.apply(a,0)
  assert(yes,reason)
  assert(x.group():byte(1644+185)==1,'Bingus auto-fire flag was not preserved')
end

local function reject(name,modify)
  local a,x=make(); modify(a,x)
  local before_d,before_g,before_w,before_r=x.damage(),x.group(),x.weapon(),x.arc()
  local yes,reason=patch.apply(a,0)
  assert(not yes,name..': '..reason)
  assert(x.damage()==before_d and x.group()==before_g and x.weapon()==before_w and x.arc()==before_r,name..': unexpected mutation')
end
reject('damage conflict',function(a,x) x.change_damage(15076,string.char(1,0,0,0)) end)
reject('charge conflict',function(a,x) x.change_group(1644,string.char(1,0,0,0)) end)
reject('recoil conflict',function(a,x) x.change_weapon(76,string.char(0,0,0,0)) end)
reject('range conflict',function(a,x) x.change_arc(52,string.char(0,0,0,0)) end)
reject('range count conflict',function(a,x) x.change_arc(36,string.char(0,0,0,0)) end)
reject('range pointer conflict',function(a,x) x.change_arc(28,string.rep('\0',8)) end)
do
  local a,x=make();local before_d,before_r=x.damage(),x.arc()
  local original=a.write_protected;local failed=false
  a.write_protected=function(p,v)
    if p==300000+44+8 and not failed then failed=true;original(p,v:sub(1,2));return false end
    return original(p,v)
  end
  local yes,reason=patch.apply(a,0)
  assert(not yes and reason:find('restored=true',1,true),reason)
  assert(x.damage()==before_d and x.arc()==before_r,'range partial write was not rolled back')
end
reject('wrong owner',function(a,x)
  local owner=string.char(230,6,115,15,213,156,222,150)
  local g=x.group();local at=g:find(owner,1,true);assert(at)
  x.change_group(at-1,string.rep('\0',8))
end)
reject('duplicate damage',function(a)
  local original_read,original_writable=a.read,a.writable
  a.candidates=function() return {1000,200000} end
  a.read=function(p,n) if p==200000 and n==#DAMAGE then return DAMAGE end;return original_read(p,n) end
  a.writable=function(p,n) return (p==200000 and n==#DAMAGE) or original_writable(p,n) end
  a.pointer=function(s,o) return o==84 and 1100 end
  a.distance=function(p,b) return (b==200000) and 100 or p-b end
end)
reject('missing charge',function(a) a.private_regions=function() return {} end end)
reject('unsupported table permission',function(a) a.writable=function() return false end end)
do
  local a,x=make();local before_d,before_g,before_w=x.damage(),x.group(),x.weapon()
  local original=a.write_protected;local calls=0
  a.write_protected=function(p,v)
    calls=calls+1
    if calls==2 then original(p,v:sub(1,2));return false end
    return original(p,v)
  end
  local yes,reason=patch.apply(a,0)
  assert(not yes and reason:find('restored=true',1,true),reason)
  assert(x.damage()==before_d and x.group()==before_g and x.weapon()==before_w,'partial transaction was not rolled back')
end
do
  local a,x=make();local before_d,before_g,before_w=x.damage(),x.group(),x.weapon()
  local original=a.write_protected;local calls=0
  a.write_protected=function(p,v)
    calls=calls+1
    if calls==5 then original(p,v:sub(1,2));return false end
    return original(p,v)
  end
  local yes,reason=patch.apply(a,0)
  assert(not yes and reason:find('restored=true',1,true),reason)
  assert(x.damage()==before_d and x.group()==before_g and x.weapon()==before_w,'recoil partial write was not rolled back')
end
do
  local a,x=make();local before_d,before_g,before_w=x.damage(),x.group(),x.weapon()
  local original=a.read;local reads=0
  a.read=function(p,n)
    local s=original(p,n)
    if p==1000+15072 and n==76 then
      reads=reads+1
      if reads==3 then return '\0'..s:sub(2) end
    end
    return s
  end
  local yes,reason=patch.apply(a,0)
  assert(not yes and reason:find('restored=true',1,true),reason)
  assert(x.damage()==before_d and x.group()==before_g and x.weapon()==before_w,'readback failure was not rolled back')
end
do
  local a,x=make();local region=a.private_regions
  a.private_regions=function()
    x.change_damage(200,string.char(17)) -- an unrelated mod edits another damage row during discovery
    return region()
  end
  local yes,reason=patch.apply(a,0)
  assert(yes,reason)
  assert(x.damage():byte(201)==17,'unrelated damage edit was lost')
  assert(word(x.damage(),15076)==226,'ARC-3 target row was not changed')
end
print('Lua transaction fixtures passed')
'''
    run(lua,True)
    startup=(ROOT/"startup.lua").read_text(encoding="utf-8")
    version_test=("local start=(function()\n"+startup+"\nend)()\n"
                  "start(function() return {module=function() return 1 end,module_hash=function() return 'wrong' end} end,{apply=function() error('must not write') end})\n"
                  "update()\nassert(not RapidArcThrowerV1.active)\nassert(RapidArcThrowerV1.status:find('Unsupported executable',1,true))\n")
    run(version_test,True)
    package=PROJECT/"outputs/ARC-3-Rapid-Arc-Thrower-v0.10.zip"
    with zipfile.ZipFile(package) as z:
        names=set(z.namelist())
        assert {"manifest.json","README.md","Addon/9ba626afa44a3aa3.patch_0","Source/entry.lua"} <= names
        manifest=json.loads(z.read("manifest.json"))
        assert manifest["Guid"]=="2f61e45d-92fc-4517-b931-a6cd10515357"
        assert z.read("Source/entry.lua")== (ROOT/"entry.lua").read_bytes()
        archive=z.read("Addon/9ba626afa44a3aa3.patch_0")
        assert struct.unpack_from("<I",archive,0)[0]==0xF0000011
        size,kind=struct.unpack_from("<II",archive,192)
        assert kind==2 and archive[200:200+size]==z.read("Source/entry.lua")
    report=json.loads((ROOT/"build-report.json").read_text())
    assert report["package_sha256"]==hashlib.sha256(package.read_bytes()).hexdigest().upper()
    report["offline_tests"]="passed: exact shipped Lua syntax, relocated live-layout arc pointer fixture, stock and Bingus auto-fire fixtures, bounded allocation lookup with bulk scan forbidden, unrelated damage-row changes during discovery, damage/charge/recoil/range conflict and owner rejection, version rejection, edit scope, range/charge/recoil partial-write and readback rollback, package round trip"
    (ROOT/"build-report.json").write_text(json.dumps(report,indent=2),encoding="utf-8")
    (PROJECT/"outputs/ARC-3-Rapid-Arc-Thrower-v0.10-Validation.json").write_text(json.dumps(report,indent=2),encoding="utf-8")
    print("Lua syntax, package round trip, conflicts, edit scope, and rollback passed")


if __name__=="__main__": main()
