"""Immutable061 to one-centimetre lower magazine mount. Offline only."""
from pathlib import Path
import ast,hashlib,json,struct,zipfile,sys
from collections import Counter
import numpy as np
H=Path(__file__).resolve().parent;ROOT=H.parents[1];O=H/'magazine-mount-v0162'
BASE=ROOT/'outputs/Punisher-Plasma-Magazine-Mount-Test-v0.1.61.zip'
DEST=ROOT/'outputs/Punisher-Plasma-Magazine-Mount-Test-v0.1.62.zip'
sha=lambda b:hashlib.sha256(b).hexdigest().upper()
assert not DEST.exists() and sha(BASE.read_bytes())=='F1FC9D7D226C828AE213947D68398460FC2BC038753FC41237A1A7361D21D22D'
with zipfile.ZipFile(BASE) as z:assert z.testzip() is None;before={n:z.read(n) for n in z.namelist()}
files=dict(before);O.mkdir(exist_ok=True)
def function(file,name,ns):
 tree=ast.parse((H/file).read_text());fn=next(n for n in tree.body if isinstance(n,ast.FunctionDef) and n.name==name)
 exec(compile(ast.Module(body=[fn],type_ignores=[]),name,'exec'),ns);return ns[name]
joints=function('audit_hidden_aligned_v0150.py','joints',{'np':np,'struct':struct})
old=before['Visual/02cd7321cd8445f5-magazine.unit'];donor=(H/'unused-grip-assets/411c4fd07740a7dd.unit').read_bytes()
cs,cc,cp,cm,cn=joints(old);ds,dc,dp,dm,dn=joints(donor)
assert np.allclose(cm[0],np.eye(4)) and np.allclose(dm[0],np.eye(4))
new=bytearray(old);allowed=set();placements=[]
for j in [15,16,17,18]:
 assert not any(p==j and k!=j for k,p in enumerate(cp))
 desired=cm[j].copy()
 desired[2,3]+=.010
 local=np.linalg.inv(cm[cp[j]])@desired;lo=cs+j*64;go=cs+cc*64+j*64
 raw=struct.unpack_from('<16f',old,lo)
 struct.pack_into('<16f',new,lo,*(list(local[:3,:3].T.flatten())+list(local[:3,3])+list(raw[12:])))
 struct.pack_into('<16f',new,go,*desired.T.flatten())
 allowed.update(range(lo,lo+48));allowed.update(range(go,go+64));placements.append({'child_node':j,'matrix':desired.tolist()})
new=bytes(new);_,_,np_,nm,_=joints(new);assert np_==cp
assert all(a==b or i in allowed for i,(a,b) in enumerate(zip(old,new)))
for i in range(15):
 for start in [cs,cs+cc*64]:assert new[start+i*64:start+(i+1)*64]==old[start+i*64:start+(i+1)*64]
visuals=['Addon/'+a+'.patch_0' for a in ['49f1972458f7ccec','e16e0aa7740716a2']]
for name in visuals:
 b=bytearray(files[name]);tc,fc=struct.unpack_from('<II',b,4)
 row=next(struct.unpack_from('<7Q6I',b,72+tc*32+i*80) for i in range(fc) if struct.unpack_from('<Q',b,72+tc*32+i*80)[0]==0x02cd7321cd8445f5)
 assert b[row[2]:row[2]+row[7]]==old and row[7]==len(new)
 b[row[2]:row[2]+row[7]]=new;files[name]=bytes(b)
 assert files[name][:row[2]]==before[name][:row[2]] and files[name][row[2]+row[7]:]==before[name][row[2]+row[7]:]
oldruntime=before['Source/runtime.lua'];runtime=oldruntime.replace(b'0.1.61-one-two-test',b'0.1.62-one-two-test')
assert oldruntime.count(b'0.1.61-one-two-test')==1 and runtime!=oldruntime
files['Source/runtime.lua']=runtime
files['Source/one_two_build_data.py']=before['Source/one_two_build_data.py'].replace(b'0.1.61-one-two-test',b'0.1.62-one-two-test')
serialize=function('build_hidden_aligned_v0150.py','archive',{'struct':struct,'Counter':Counter})
main='Addon/9ba626afa44a3aa3.patch_0';blob=before[main];tc,fc=struct.unpack_from('<II',blob,4);resources=[];changed=0
for i in range(fc):
 r=struct.unpack_from('<7Q6I',blob,72+tc*32+i*80);p=blob[r[2]:r[2]+r[7]]
 if p[8:]==oldruntime:p=struct.pack('<II',len(runtime),2)+runtime;changed+=1
 resources.append((r[0],r[1],p,r))
assert changed==1;files[main]=serialize(resources)
sys.path.insert(0,str(ROOT/'work/expanded-stat-editor'));from lua_runtime import Lua51
lua=Lua51()
for n,b in files.items():
 if n.startswith('Source/') and n.endswith('.lua'):lua.compile(b,'@'+n)
lua.run((H/'grip-ammo-hud-v0155/private-profile-fixture.lua').read_bytes(),'@unchanged055-profile-fixture')
for n,b in before.items():
 if n.startswith('Source/') and n not in ['Source/runtime.lua','Source/one_two_build_data.py']:assert files[n]==b
 if n.startswith('Addon/') and n not in [main,*visuals]:assert files[n]==b
manifest=json.loads(files['manifest.json']);manifest['Name']='SG-8P Punisher Plasma Magazine Mount Test v0.1.62'
manifest['Description']='Magazine lowered1cm from061; rearward position/angle/size preserved. Placement test; prior crashes unresolved.'
files['manifest.json']=(json.dumps(manifest,indent=2)+'\n').encode()
files['README.txt']=b'WARNING - UNEQUIP PUNISHER PLASMA BEFORE REMOVING THIS MOD\n\n1. With the mod still installed, equip a different primary weapon.\n2. Close the game completely.\n3. Only then disable, purge, or remove the Punisher Plasma mod.\n\nRemoving the mod while Punisher Plasma is equipped can prevent the game\nfrom starting. If this happens, reinstall the mod, switch to another primary\nweapon, close the game completely, then remove the mod again.\n\nThis is a temporary recovery precaution. Mission-loading crashes remain\nunder investigation; this warning does not resolve them.\n\nPunisher Plasma v0.1.62 MAGAZINE MOUNT PLACEMENT TEST\n\nMagazine lowered 1 cm from v061. Rearward position, angle and stock size unchanged.\nOnly render nodes 15..18 translations change; no animation edits.\nFunctional bones 0..14, IK/muzzle, native safety/profiles, reload 2x,\nnormal 15/1/1/1 (effective 3/3 accepted), LEFT modes and protected weapons preserved.\nPrior v059 crashes unresolved; one monitored mission entry succeeded.\nOffline preservation checks only; startup/mount/palm/gameplay NOTRUN.\nUser deploys ALL Addon CPU/GPU/STREAM files after unequipping and fully closing game.\nRestart and report launched. Final release remains gated.\n'
for n in list(files):
 if n.startswith('Visual/') or n.startswith('Verification/'):files['Baseline061/'+n]=files.pop(n)
files['Visual/02cd7321cd8445f5-magazine.unit']=new
report={'status':'PASS','scope':'Offline magazine translation-only placement test','baseline_sha256':sha(BASE.read_bytes()),'placements':placements,'changed_unit_bytes':sum(a!=b for a,b in zip(old,new)),'functional_nodes_exact':True,'native_safety_and_tuning_exact':True,'ammo_hud_profiles_exact061':True,'rearward_shift_from061_m':0,'downward_shift_from061_m':.010,'rotation_and_scale_exact061':True,'mount_and_hand_fit':'UNVERIFIED','animation_edits':False,'game_access':False,'startup':'NOTRUN','gameplay':'NOTRUN'}
files['Verification/scoped-v0162.json']=(json.dumps(report,indent=2)+'\n').encode()
files['Source/build_magazine_mount_v0162.py']=Path(__file__).read_bytes()
with zipfile.ZipFile(DEST,'x',zipfile.ZIP_DEFLATED) as z:
 for n,b in files.items():z.writestr(n,b)
with zipfile.ZipFile(DEST) as z:assert z.testzip() is None and all(z.read(n)==b for n,b in files.items())
for n,b in files.items():
 if n.startswith('Source/'):p=O/n;p.parent.mkdir(parents=True,exist_ok=True);p.write_bytes(b)
report.update(candidate=str(DEST),sha256=sha(DEST.read_bytes()))
(O/'package-verification.json').write_text(json.dumps(report,indent=2)+'\n')
print(json.dumps(report,indent=2))
