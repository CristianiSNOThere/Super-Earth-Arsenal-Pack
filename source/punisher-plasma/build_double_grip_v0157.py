"""Immutable056 -> two-copy visual test; offline only."""
from pathlib import Path
import ast,json,hashlib,struct,zipfile,sys
from collections import Counter
H=Path(__file__).resolve().parent;R=H.parents[1];O=H/'double-grip-v0157'
BASE=R/'outputs/Punisher-Plasma-Grip-Mount-Test-v0.1.56.zip';DEST=R/'outputs/Punisher-Plasma-Double-Grip-Test-v0.1.57.zip'
sha=lambda b:hashlib.sha256(b).hexdigest().upper()
assert not DEST.exists() and sha(BASE.read_bytes())=='7675965ADEAF7F6FC1D60E52AA67556C4A53B639F87AF0BA172CA7C665D1F087'
with zipfile.ZipFile(BASE) as z:assert z.testzip() is None;before={n:z.read(n) for n in z.namelist()}
files=dict(before);new=(O/'02cd7321cd8445f5-double-grip.unit').read_bytes();old=before['Visual/02cd7321cd8445f5-stock-origin-grip.unit']
checks=[]
visuals=['Addon/'+a+'.patch_0' for a in ['49f1972458f7ccec','e16e0aa7740716a2']]
for name in visuals:
 b=bytearray(before[name]);tc,fc=struct.unpack_from('<II',b,4)
 rp=next(72+tc*32+i*80 for i in range(fc) if struct.unpack_from('<Q',b,72+tc*32+i*80)[0]==0x02cd7321cd8445f5)
 row=list(struct.unpack_from('<7Q6I',b,rp));assert b[row[2]:row[2]+row[7]]==old
 delta=row[5]-row[2];b.extend(bytes(-len(b)%64));start=len(b);b.extend(new)
 row[2]=start;row[5]=start+delta;row[7]=len(new);struct.pack_into('<7Q6I',b,rp,*row);struct.pack_into('<Q',b,32,len(b))
 files[name]=bytes(b);checks.append({'archive':name,'cpu_buffer_delta':delta,'new_resource_offset':start,'size':len(new)})
 # Original resource/dependency backing bytes remain at the original locations.
 allowed=set(range(32,40))|set(range(rp,rp+80))
 assert all(a==v or i in allowed for i,(a,v) in enumerate(zip(before[name],b)))
runtime=before['Source/runtime.lua'].replace(b'0.1.56-one-two-test',b'0.1.57-one-two-test')
assert before['Source/runtime.lua'].count(b'0.1.56-one-two-test')==1
files['Source/runtime.lua']=runtime;files['Source/one_two_build_data.py']=before['Source/one_two_build_data.py'].replace(b'0.1.56-one-two-test',b'0.1.57-one-two-test')
tree=ast.parse((H/'build_hidden_aligned_v0150.py').read_text());fn=next(n for n in tree.body if isinstance(n,ast.FunctionDef) and n.name=='archive')
ns={'struct':struct,'Counter':Counter};exec(compile(ast.Module(body=[fn],type_ignores=[]),'archive','exec'),ns)
main='Addon/9ba626afa44a3aa3.patch_0';blob=before[main];tc,fc=struct.unpack_from('<II',blob,4);resources=[];changed=0
for i in range(fc):
 row=struct.unpack_from('<7Q6I',blob,72+tc*32+i*80);p=blob[row[2]:row[2]+row[7]]
 if p[8:]==before['Source/runtime.lua']:p=struct.pack('<II',len(runtime),2)+runtime;changed+=1
 resources.append((row[0],row[1],p,row))
assert changed==1;files[main]=ns['archive'](resources)
for name,b in before.items():
 if name.startswith('Source/') and name not in ['Source/runtime.lua','Source/one_two_build_data.py']:assert files[name]==b
 if name.startswith('Addon/') and name not in [main,*visuals]:assert files[name]==b
sys.path.insert(0,str(R/'work/expanded-stat-editor'));from lua_runtime import Lua51
lua=Lua51()
for name,b in files.items():
 if name.startswith('Source/') and name.endswith('.lua'):lua.compile(b,'@'+name)
lua.run((H/'grip-ammo-hud-v0155/private-profile-fixture.lua').read_bytes(),'@unchanged-profile-fixture')
manifest=json.loads(files['manifest.json']);manifest['Name']='SG-8P Punisher Plasma Double Grip Test v0.1.57';manifest['Description']='Two-copy angled grip visual test; upper inverted bridge and lower grip dropped4cm. Hand fit unverified.'
files['manifest.json']=(json.dumps(manifest,indent=2)+'\n').encode()
files['README.txt']=b'''Punisher Plasma v0.1.57 DOUBLE GRIP TEST
Upper angled grip inverted180degrees about longitudinal axis, partly embedded.
Lower grip placed4cm below accepted056 mount. Both copies use stock mesh/material
and GPU data, with distinct rigid rendering transforms and both copies in allLOD
entries. No new weapon entity, animation edits or native hooks.
Rail connection/overlap, materials, support hand idle/ADS/reload UNVERIFIED.
Functional joints0..14/IK12/muzzle13, skeleton hierarchy/controller retained056.
Ammo15/1/1/1, LEFT NORMAL/SHOTGUN,2xreload,tuning/protected weapons/full native
thread barrier/refusal/rollback/protection/storage lifetime remain exact056.
Offline structure/scope/Lua/profile/ZIP checks PASS; startup/gameplay NOTRUN.
Replace056 with057; import/Purge/Deploy ALL Addon CPU/GPU/STREAM files and restart.
Report launched; await fresh057source_installed=true/Ready before firing.
Check upper/lower seam in armory, hand fit idle/hipfire/ADS/reload, muzzle,
LEFT selector and independent ammo. User deployment/gameplay only.
Final release gated. Restart after replacement/removal; no native hot unload.
'''
for n in list(files):
 if n.startswith('Visual/') or n.startswith('Verification/'):files['Baseline056/'+n]=files.pop(n)
files['Visual/02cd7321cd8445f5-double-grip.unit']=new
report={'status':'PASS','scope':'Offline two-copy grip candidate only','geometry':json.loads((O/'geometry-audit.json').read_text()),'visual_archives':checks,'native_sources_and_profiles_exact056':True,'gpu_stream_dependencies_exact056':True,'lua_compile':'PASS','profile_execution':'PASS','startup':'NOTRUN','gameplay':'NOTRUN','deployment':False,'publication':False}
files['Verification/scoped-v0157.json']=(json.dumps(report,indent=2)+'\n').encode();files['Source/prepare_double_grip_v0157.py']=(H/'prepare_double_grip_v0157.py').read_bytes();files['Source/build_double_grip_v0157.py']=Path(__file__).read_bytes()
with zipfile.ZipFile(DEST,'x',zipfile.ZIP_DEFLATED) as z:
 for n,b in files.items():z.writestr(n,b)
with zipfile.ZipFile(DEST) as z:assert z.testzip() is None and all(z.read(n)==b for n,b in files.items())
for n,b in files.items():
 if n.startswith('Source/'):p=O/n;p.parent.mkdir(parents=True,exist_ok=True);p.write_bytes(b)
report.update(candidate=str(DEST),sha256=sha(DEST.read_bytes()));(O/'package-verification.json').write_text(json.dumps(report,indent=2)+'\n');print(json.dumps({'candidate':str(DEST),'sha256':report['sha256'],'status':'PASS'}))
