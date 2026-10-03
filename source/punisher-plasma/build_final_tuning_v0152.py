"""Final normal tuning from immutable051. Offline only; user deploys."""
from pathlib import Path
from collections import Counter
import ast, hashlib, json, struct, sys, zipfile

HERE=Path(__file__).resolve().parent;ROOT=HERE.parents[1]
BASE=ROOT/'outputs/Punisher-Plasma-One-Two-Dual-Archive-Test-v0.1.51.zip'
DEST=ROOT/'outputs/Punisher-Plasma-Final-Tuning-Test-v0.1.52.zip'
OUT=HERE/'final-tuning-v0152'
assert not DEST.exists() and not OUT.exists(), 'Never overwrite versioned candidates'
sha=lambda b:hashlib.sha256(b).hexdigest()
assert sha(BASE.read_bytes()).upper()=='F3E0A9931883D5C32DA34202EF444CE2546625511852FBC0FFCC12294112F259'
with zipfile.ZipFile(BASE) as z:
    assert z.testzip() is None
    files={n:z.read(n) for n in z.namelist()}
before=dict(files)
profile=files['Source/one_two_source_profile.lua'].decode()
owned=files['Source/owned_profile.lua'].decode()
startup=files['Source/one_two_startup.lua'].decode()
replacements={
 'Source/one_two_source_profile.lua':[
  ('elseif r.role==\'parent_projectile\' then s=baseline.projectile',"elseif r.role=='parent_projectile' then s=change(baseline.projectile,8,float(60)) -- final normal cadence only"),
  ("elseif r.role=='parent_magazine' then s=change(change(s,136,word(20)),148,word(6))","elseif r.role=='parent_magazine' then s=change(s,136,word(30)..word(1)..word(1)..word(1)) -- capacity/start/refill/max:30+30")],
 'Source/owned_profile.lua':[
  ("ffi.cast('uint32_t*',np+4)[0]=175;ffi.cast('uint32_t*',np+8)[0]=113", "ffi.cast('uint32_t*',np+4)[0]=350;ffi.cast('uint32_t*',np+8)[0]=225")],
 'Source/one_two_startup.lua':[
  ('normal=175/113 blast;120RPM;20 capacity;six spare magazines','normal=350/225 blast;60RPM;30 capacity;one spare30 magazine')],
}
runtime=files['Source/runtime.lua'].decode()
for name,changes in replacements.items():
    original=files[name].decode().replace('\r\n','\n');updated=original
    for a,b in changes:
        assert updated.count(a)==1, (name,a)
        updated=updated.replace(a,b)
    assert runtime.count(original)==1, 'Shipped module not found exactly'
    runtime=runtime.replace(original,updated)
    files[name]=updated.encode()
assert runtime.count('0.1.51-one-two-test')==1
runtime=runtime.replace('0.1.51-one-two-test','0.1.52-one-two-test')
files['Source/runtime.lua']=runtime.encode()
data=files['Source/one_two_build_data.py'];assert data.count(b'0.1.51-one-two-test')==1
files['Source/one_two_build_data.py']=data.replace(b'0.1.51-one-two-test',b'0.1.52-one-two-test')
sys.path.insert(0,str(ROOT/'work/expanded-stat-editor'))
from lua_runtime import Lua51
lua=Lua51()
for name in ['Source/runtime.lua',*replacements]:lua.compile(files[name],'@'+name)
dliteral=next(line for line in before['Source/runtime.lua'].decode().splitlines() if line.startswith('local D='))
# Execute the actual packaged data/profile/owned construction in a separate LuaJIT process.
fixture="local ffi=require('ffi')\nlocal function unhex(s)return(s:gsub('..',function(x)return string.char(tonumber(x,16))end))end\n"+dliteral+'\n'
for name,source in [('oldprofile',profile),('newprofile',files['Source/one_two_source_profile.lua'].decode()),('modes',files['Source/mode_profile.lua'].decode()),('oldowned',owned),('newowned',files['Source/owned_profile.lua'].decode())]:
    fixture+='local '+name+'=(function()\n'+source+'\nend)()\n'
fixture+=r'''
local function u(s,o)local b=ffi.new('uint32_t[1]');ffi.copy(b,s:sub(o+1,o+4),4);return tonumber(b[0])end
local function f(s,o)local b=ffi.new('float[1]');ffi.copy(b,s:sub(o+1,o+4),4);return tonumber(b[0])end
local stock={weapon=D.components.weapon.bytes,projectile=D.components.projectile.bytes,magazine=D.components.magazine.bytes}
local a=oldprofile(D.source_rows,modes,stock,D.child_reload_template)
local b=newprofile(D.source_rows,modes,stock,D.child_reload_template)
local roles={};assert(#a==8 and #b==8)
for i,r in ipairs(a)do
 local s=b[i];roles[s.role]=s.after
 assert(r.role==s.role and r.before==s.before and r.owner==s.owner and r.index==s.index and r.stride==s.stride)
 local allowed={}
 if r.role=='parent_projectile'then for o=8,11 do allowed[o]=true end
 elseif r.role=='parent_magazine'then for o=136,151 do allowed[o]=true end
 else assert(r.after==s.after,'Unrelated source profile changed: '..r.role)end
 for o=0,#r.after-1 do assert(r.after:byte(o+1)==s.after:byte(o+1) or allowed[o],'Unapproved source byte')end
end
assert(f(roles.parent_projectile,8)==60 and u(roles.parent_weapon,140)==1)
assert(u(roles.parent_magazine,136)==30 and u(roles.parent_magazine,140)==1 and u(roles.parent_magazine,144)==1 and u(roles.parent_magazine,148)==1)
assert(f(roles.child_rounds,72)==20 and u(roles.child_rounds,80)==60 and u(roles.child_rounds,84)==60 and u(roles.child_rounds,88)==60)
assert(f(roles.child_projectile,8)==100 and u(roles.child_reload,4)==2774 and math.abs(f(roles.child_reload,56)-121/60)<0.000001)
local held={}
local function pointer(p)local b=ffi.new('uintptr_t[1]',ffi.cast('uintptr_t',p));return ffi.string(b,8)end
local api={epoch=function()return 'private-fixture'end,read=function(p,n)return ffi.string(p,n)end,pointer_bytes=pointer,retain=function(v)held[#held+1]=v end}
api.pointer=function(s,o)local b=ffi.new('uintptr_t[1]');ffi.copy(b,s:sub(o+1,o+8),8);return ffi.cast('uint8_t*',b[0])end
local sources={}
local function record(g)
 local buf=ffi.new('uint64_t[?]',math.ceil(#g.serialized/8));held[#held+1]=buf
 local p=ffi.cast('uint8_t*',buf);ffi.copy(p,g.serialized,#g.serialized)
 if g.array then
  local ar=ffi.new('uint64_t[?]',#g.array/8);held[#held+1]=ar;ffi.copy(ar,g.array,#g.array);ffi.copy(p+40,pointer(ar),8)
 end
 return {address=p,bytes=ffi.string(p,#g.serialized)}
end
for name,g in pairs(D.records)do sources[name]=record(g)end
local original={};for name,g in pairs(sources)do original[name]=g.bytes end
local cfg={epoch='private-fixture',route='user-selected-loyalist-donor',ids={projectile=171,damage=305,explosion=355},sources={projectile=sources.donor_projectile,damage=sources.donor_damage,explosion=sources.donor_explosion},shake_bytes=D.records.donor_explosion.array,tuning=D.tuning,next_tuning=D.next_tuning,normal_two_shot=D.normal_two_shot,normal_flight=D.normal_flight,pellet_split=D.pellet_split,pellet_angle_ap=D.pellet_angle_ap,blast_burning=D.blast_burning,burning_reference=sources.burning_reference,normal_projectile=sources.normal_projectile,tuning_sources={normal_damage=sources.normal_blast_damage,normal_explosion=sources.normal_blast,alternate_explosion=sources.alternate_explosion,equivalent_damage=sources.equivalent_damage,normal_array=D.records.normal_blast.array,alternate_array=D.records.alternate_explosion.array}}
local x=oldowned.build(api,cfg);local y=newowned.build(api,cfg)
assert(u(x.records.normal_damage,4)==175 and u(x.records.normal_damage,8)==113)
assert(u(y.records.normal_damage,4)==350 and u(y.records.normal_damage,8)==225)
local function normalize(k,s)
 if k=='explosion'or k=='normal_explosion'or k=='alternate_explosion'then return s:sub(1,40)..string.rep('\0',8)..s:sub(49)end
 return s
end
for k,s in pairs(x.records)do
 local t=y.records[k];assert(#s==#t)
 if k=='normal_damage'then assert(s:sub(1,4)==t:sub(1,4) and s:sub(13)==t:sub(13),'Normal status/force/AP changed')
 else assert(normalize(k,s)==normalize(k,t),'Unrelated owned record changed: '..k)end
end
assert(u(y.records.alternate_explosion,4)==315)
for name,g in pairs(sources)do assert(api.read(g.address,#g.bytes)==original[name],'Shared source modified')end
collectgarbage('collect')
assert(api.read(y.addresses.normal_damage,76)==y.records.normal_damage)
assert(not pcall(newowned.build,{epoch=function()return 'expired'end},cfg),'Expired epoch accepted')
assert(f(y.records.normal_explosion,16)==3.5 and f(y.records.normal_explosion,20)==6.5 and f(y.records.normal_explosion,24)==8)
assert(u(y.records.normal_damage,28)==30 and u(y.records.normal_damage,32)==25 and u(y.records.normal_damage,36)==30 and u(y.records.normal_damage,44)==5)
'''
try:
    lua.run(fixture.encode(),'@v0152-normal-tuning-private-fixture.lua')
except RuntimeError:
    (HERE/'v0152-failed-private-fixture.lua').write_text(fixture)
    raise
for path,expected in [(Path('D:/SteamLibrary/steamapps/common/Helldivers 2/bin/helldivers2.exe'),'F5FEE03DCFDB2E553A4752C283590950AC13316B376D8196AA556FF0400D5F06'),(Path('D:/SteamLibrary/steamapps/common/Helldivers 2/data/game/game.dll'),'2E2C3B7C2500646DADD5F2B4C6E0504DBB7E7896139F64CDDC0D1813C718F51E')]:
    assert sha(path.read_bytes()).upper()==expected
tree=ast.parse((HERE/'build_hidden_aligned_v0150.py').read_text())
fn=next(x for x in tree.body if isinstance(x,ast.FunctionDef) and x.name=='archive')
ns={'Counter':Counter,'struct':struct};exec(compile(ast.Module(body=[fn],type_ignores=[]),'serializer','exec'),ns)
main='Addon/9ba626afa44a3aa3.patch_0';blob=files[main];tc,fc=struct.unpack_from('<II',blob,4)
resources=[];changed=0;unchanged_resources=[]
for i in range(fc):
    row=struct.unpack_from('<7Q6I',blob,72+tc*32+i*80);payload=blob[row[2]:row[2]+row[7]]
    if payload[8:]==before['Source/runtime.lua']:
        payload=struct.pack('<II',len(files['Source/runtime.lua']),2)+files['Source/runtime.lua'];changed+=1
    else:unchanged_resources.append(dict(name=f'{row[0]:016X}',type=f'{row[1]:016X}',sha256=sha(payload)))
    resources.append((row[0],row[1],payload,row))
assert changed==1
files[main]=ns['archive'](resources)
allowed={'Source/runtime.lua','Source/one_two_build_data.py',*replacements}
retained={}
for name,payload in before.items():
    if name.startswith('Source/') and name not in allowed:
        assert files[name]==payload;retained[name]=sha(payload)
    if name.startswith('Addon/') and name!=main:assert files[name]==payload
manifest=json.loads(files['manifest.json']);guid=manifest['Guid'];options=manifest['Options']
manifest['Name']='SG-8P Punisher Plasma Final Tuning Test v0.1.52'
manifest['Description']='Normal350/225 blast,60RPM,30 loaded plus one spare30 magazine. Pellet tuning, reload2x and verified hidden/aligned child retained.'
files['manifest.json']=(json.dumps(manifest,indent=2)+'\n').encode()
files['README.txt']=b'''Punisher Plasma v0.1.52 - final normal tuning TEST
Built from immutable051 after user confirms hidden appearance and good alignment.
ONLY normal tuning changes:350 normal/225 durable blast;60RPM;one round per shot;
30 loaded plus one spare30-round magazine (start/refill/max one spare).
Pellet tuning/20 loaded60 loose spares, working reload2774/duration121/60 (2x),
both hidden/aligned visual archives/GPU data and native publication safety retained.
Existing normal radii/forces/AP/burning/flight, AR11/Scorcher protections retained.
Offline actual packaged Lua construction, byte scope/preservation, fingerprints,
Lua compile and ZIP/archive roundtrip PASS. Fresh052 startup/gameplay NOTRUN.
Baseline051 records are historical, not fresh052 evidence. No publication.

USER DEPLOYS when finished testing051: equip unrelated primary before closing.
Replace051 with052 through existing import/Purge/Deploy; never stack versions.
Deploy all Addon files including BOTH visual archives and BOTH GPU companions.
Restart and tell agent launched. Agent checks fresh052 source, normal30+30/60RPM
and pellet20/60 evidence before user firing/reload/ammo-independence checks.
Stop on source refusal/pink/resource failure;051 recovery kept unchanged.
Restart after replacement/refusal/removal; no hot-unload of retained native storage.
User handles deployment and gameplay. No agent game writes/calls/input/settings,
publication or schedules. Menu icon and other unmentioned settings unchanged.
'''
report=dict(status='PASS',scope='Offline actual packaged Lua profile/owned allocation and byte-preservation; no game access',baseline=str(BASE),baseline_sha256=sha(BASE.read_bytes()),normal=dict(blast_damage=350,durable=225,rpm=60,rounds_per_shot=1,capacity=30,starting_spares=1,refill_spares=1,max_spares=1),source_changes=['parent_projectile offset8 float60','parent_magazine offsets136/140/144/148 values30/1/1/1'],owned_changes=['normal_damage311 offsets4/8 values350/225'],other_six_source_profiles_identical=True,other_owned_records_identical_after_pointer_normalization=True,pellet_tuning_and_rounds_identical=True,accepted_reload2x_identical=True,visual_archives_and_gpu_companions_identical051=True,shared_source_bytes_unchanged_fixture=True,retained_source_hashes=retained,native_publisher_guards_thread_safety_refusal_restoration_retention_unchanged=True,retained_archive_payloads=unchanged_resources,lua_execution='PASS',lua_compile='PASS',fingerprints='PASS',fresh_startup='NOTRUN',normal_ammo_runtime='NOTRUN',gameplay='NOTRUN',game_access=False,deployment=False,settings=False,publication=False,schedules=False)
for name in list(files):
    if name.startswith('Verification/'):files['Baseline051/'+name]=files.pop(name)
files['Verification/final-normal-tuning-preservation.json']=(json.dumps(report,indent=2)+'\n').encode()
files['Source/build_final_tuning_v0152.py']=Path(__file__).read_bytes()
files['Verification/v0152-private-lua-fixture.lua']=fixture.encode()
with zipfile.ZipFile(DEST,'x',zipfile.ZIP_DEFLATED) as z:
    for name,payload in files.items():z.writestr(name,payload)
with zipfile.ZipFile(DEST) as z:
    assert z.testzip() is None and all(z.read(n)==b for n,b in files.items())
    assert json.loads(z.read('manifest.json'))['Guid']==guid and json.loads(z.read('manifest.json'))['Options']==options
    b=z.read(main);tc,fc=struct.unpack_from('<II',b,4);assert fc==len(resources)
    for i,(name,kind,payload,_) in enumerate(resources):
        row=struct.unpack_from('<7Q6I',b,72+tc*32+i*80);assert row[:2]==(name,kind) and b[row[2]:row[2]+row[7]]==payload
OUT.mkdir()
for name,payload in files.items():
    if name.startswith('Source/'):
        p=OUT/name;p.parent.mkdir(parents=True,exist_ok=True);p.write_bytes(payload)
(OUT/'private-lua-fixture.lua').write_text(fixture)
report.update(candidate=str(DEST),sha256=sha(DEST.read_bytes()).upper(),zip_integrity='PASS',archive_roundtrip='PASS')
(HERE/'one-two-v0152-package-verification.json').write_text(json.dumps(report,indent=2)+'\n')
print(json.dumps({k:report[k] for k in ['status','candidate','sha256','normal','fresh_startup','gameplay']},indent=2))
