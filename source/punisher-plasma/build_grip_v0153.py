"""Offline leaf-only grip candidate from immutable052. No game access."""
from pathlib import Path
from collections import Counter
import ast, hashlib, json, struct, sys, zipfile
import numpy as np
HERE=Path(__file__).resolve().parent; ROOT=HERE.parents[1]
BASE=ROOT/'outputs/Punisher-Plasma-Final-Tuning-Test-v0.1.52.zip'
DEST=ROOT/'outputs/Punisher-Plasma-Grip-Tuning-Test-v0.1.53.zip'
OUT=HERE/'grip-v0153'
assert not DEST.exists() and not OUT.exists()
sha=lambda b:hashlib.sha256(b).hexdigest()
assert sha(BASE.read_bytes()).upper()=='EAC458AFBA7E8F9CE0EC650ED4061D428F71E08E7BC304C80D964346FE8F3894'
with zipfile.ZipFile(BASE) as z: files={n:z.read(n) for n in z.namelist()}
before=dict(files)
tree=ast.parse((HERE/'audit_hidden_aligned_v0150.py').read_text())
fn=next(n for n in tree.body if isinstance(n,ast.FunctionDef) and n.name=='joints')
ns={'np':np,'struct':struct};exec(compile(ast.Module(body=[fn],type_ignores=[]),'reviewed-joint-parser','exec'),ns)
parent=(HERE/'underbarrel-assets/05d8d8c073b9d502.unit').read_bytes()
assert sha(parent)=='834426b0a1acb672101dc1b4dba05edb730f00ae8b0c177159feff4170c0dc2c'
unit=files['Visual/02cd7321cd8445f5-hidden-aligned.unit']
assert sha(unit)=='8626c0ddd2ce6877063155f43ce191e67a56eac8fc1e80b2729d650ef9a22b21'
ps,pc,pp,pm,pn=ns['joints'](parent);cs,cc,cp,cm,cn=ns['joints'](unit)
mount,grip,target,muzzle=pn(0x7950e36e),cn(0x67c94e4b),pn(0x67c94e4b),cn(0x57520abf)
assert (mount,grip,target,muzzle)==(35,12,36,13)
assert not any(p==grip and i!=p for i,p in enumerate(cp)), 'Grip must be leaf'
desired=np.linalg.inv(pm[mount])@pm[target]
local=np.linalg.inv(cm[cp[grip]])@desired
lo,go=cs+grip*64,cs+cc*64+grip*64
after=bytearray(unit);old=struct.unpack_from('<16f',unit,lo)
struct.pack_into('<16f',after,lo,*(list(local[:3,:3].T.flatten())+list(local[:3,3])+list(old[12:])))
struct.pack_into('<16f',after,go,*desired.T.flatten());after=bytes(after)
_,_,ap,am,_=ns['joints'](after)
changed=[i for i,(a,b) in enumerate(zip(unit,after)) if a!=b]
assert changed and set(changed)<=set(range(lo,lo+48))|set(range(go,go+64))
for i in range(cc):
    if i!=grip:
        for start in (cs,cs+cc*64):assert after[start+i*64:start+(i+1)*64]==unit[start+i*64:start+(i+1)*64]
assert ap==cp and after[cs+cc*128:]==unit[cs+cc*128:]
err=float(np.max(np.abs(pm[mount]@am[grip]-pm[target])));assert err<2e-6
oldtag,newtag=b'0.1.52-one-two-test',b'0.1.53-one-two-test'
for n in ('Source/runtime.lua','Source/one_two_build_data.py'):
    assert files[n].count(oldtag)==1;files[n]=files[n].replace(oldtag,newtag)
sys.path.insert(0,str(ROOT/'work/expanded-stat-editor'))
from lua_runtime import Lua51
Lua51().compile(files['Source/runtime.lua'],'@grip-v0153')
tree=ast.parse((HERE/'build_hidden_aligned_v0150.py').read_text())
fn=next(n for n in tree.body if isinstance(n,ast.FunctionDef) and n.name=='archive')
ns={'Counter':Counter,'struct':struct};exec(compile(ast.Module(body=[fn],type_ignores=[]),'reviewed-serializer','exec'),ns)
main='Addon/9ba626afa44a3aa3.patch_0';b=files[main];tc,fc=struct.unpack_from('<II',b,4);res=[];replaced=0
for i in range(fc):
    r=struct.unpack_from('<7Q6I',b,72+tc*32+i*80);p=b[r[2]:r[2]+r[7]]
    if p[8:]==before['Source/runtime.lua']:p=struct.pack('<II',len(files['Source/runtime.lua']),2)+files['Source/runtime.lua'];replaced+=1
    res.append((r[0],r[1],p,r))
assert replaced==1;files[main]=ns['archive'](res)
visual=[]
for archive in ('49f1972458f7ccec','e16e0aa7740716a2'):
    n='Addon/'+archive+'.patch_0';b=bytearray(files[n]);tc,fc=struct.unpack_from('<II',b,4);assert fc==1
    r=struct.unpack_from('<7Q6I',b,72+tc*32)
    assert r[:2]==(0x02cd7321cd8445f5,0xe0a48d0be9a7453f) and r[7]==len(unit)
    assert b[r[2]:r[2]+r[7]]==unit;b[r[2]:r[2]+r[7]]=after;files[n]=bytes(b)
    assert {i-r[2] for i,(a,v) in enumerate(zip(before[n],b)) if a!=v}==set(changed)
    visual.append(n)
files['Visual/02cd7321cd8445f5-hidden-aligned.unit']=after
retained={}
for n,b in before.items():
    if n.startswith('Source/') and n not in ('Source/runtime.lua','Source/one_two_build_data.py'):
        assert files[n]==b;retained[n]=sha(b)
    if n.endswith('.gpu_resources'):assert files[n]==b
manifest=json.loads(files['manifest.json']);manifest['Name']='Punisher Plasma Grip and Tuning Test v0.1.53'
manifest['Description']='Scoped left-hand grip target correction plus authorized v0.1.52 final normal tuning. Gameplay validation pending.'
files['manifest.json']=(json.dumps(manifest,indent=2)+'\n').encode()
files['README.txt']=b'''Punisher Plasma v0.1.53 grip and tuning TEST
From immutable052: moves only hidden child IK_left leaf12 to parent IK_left36
through full inverse mount composition. Muzzle13 and other18 joints unchanged.
Normal350/225 blast,60RPM,30 loaded plus one spare30 magazine retained052.
Pellets20/60, accepted2x reload, native safety and other weapons retained.
Offline math/byte isolation/Lua compile/archive roundtrip PASS.
Current hand binding and animated pose/startup/gameplay NOT VERIFIED for053.
User deploys all Addon files including both visual patches/GPU companions;
replace previous version, restart, then agent checks fresh startup before firing.
No hot unload. User checks grip/ADS/reload/alignment and final normal tuning.
051 recovery and052 original retained. No settings/publication/schedules.
'''
report=dict(status='PASS',scope='Offline serialized leaf IK target correction only',baseline_sha256=sha(BASE.read_bytes()),grip_node=grip,grip_parent=cp[grip],target_parent_node=target,maximum_matrix_error=err,allowed_ranges=[[lo,48],[go,64]],changed_bytes=changed,other_18_joints_and_muzzle_identical=True,parenting_names_identical=True,source_modules_retained=retained,both_gpu_companions_identical=True,final_tuning_identical052=True,reload_native_thread_safety_identical052=True,live_binding='Historical child node12; current read REFUSED wieldersentinel',fresh_startup='NOTRUN',animated_grip='NOTRUN',gameplay='NOTRUN',game_access=False)
for n in list(files):
    if n.startswith('Verification/'):files['Baseline052/'+n]=files.pop(n)
files['Verification/grip-isolation.json']=(json.dumps(report,indent=2)+'\n').encode()
files['Source/build_grip_v0153.py']=Path(__file__).read_bytes()
with zipfile.ZipFile(DEST,'x',zipfile.ZIP_DEFLATED) as z:
    for n,b in files.items():z.writestr(n,b)
with zipfile.ZipFile(DEST) as z:assert z.testzip() is None and all(z.read(n)==b for n,b in files.items())
OUT.mkdir()
for n,b in files.items():
    if n.startswith(('Source/','Visual/')):
        p=OUT/n;p.parent.mkdir(parents=True,exist_ok=True);p.write_bytes(b)
report.update(candidate=str(DEST),sha256=sha(DEST.read_bytes()).upper())
(OUT/'grip-isolation.json').write_text(json.dumps(report,indent=2)+'\n')
print(json.dumps({k:report[k] for k in ('status','candidate','sha256','maximum_matrix_error','grip_parent','fresh_startup')},indent=2))
