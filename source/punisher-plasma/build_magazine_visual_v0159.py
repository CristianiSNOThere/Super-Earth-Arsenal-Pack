"""Immutable057 -> StA11 rigid magazine visual test. No game access/deployment."""
from pathlib import Path
import ast,hashlib,struct,json,zipfile,importlib.util,sys
from collections import Counter
import numpy as np
H=Path(__file__).resolve().parent;R=H.parents[1];O=H/'magazine-visual-v0159';O.mkdir(exist_ok=True)
BASE=R/'outputs/Punisher-Plasma-Double-Grip-Test-v0.1.57.zip';DEST=R/'outputs/Punisher-Plasma-Magazine-Grip-Test-v0.1.59.zip'
sha=lambda b:hashlib.sha256(b).hexdigest().upper()
assert not DEST.exists() and sha(BASE.read_bytes())=='B365000A8D25B80895BBF5419917E55F72012D03F6B537FDF869B97842B7CC09'
with zipfile.ZipFile(BASE) as z:assert z.testzip() is None;before={n:z.read(n) for n in z.namelist()}
files=dict(before);child=before['Visual/02cd7321cd8445f5-double-grip.unit'];donor=(H/'sta11-magazine-research/48d2ddc8e9a80b1e.unit').read_bytes()
rigid=(H/'sta11-magazine-research/private-rigid-vertex-draft.gpu').read_bytes();audit=json.loads((H/'sta11-magazine-research/binding-layout-audit.json').read_text())
assert audit['maximum_rest_skin_matrix_error']==0 and audit['single_weight_vertices']==4688 and audit['private_vertex_conversion']['status']=='PASS'
def fn(file,name,ns):
 tree=ast.parse((H/file).read_text());f=next(n for n in tree.body if isinstance(n,ast.FunctionDef) and n.name==name)
 exec(compile(ast.Module(body=[f],type_ignores=[]),name,'exec'),ns);return ns[name]
joints=fn('audit_hidden_aligned_v0150.py','joints',{'np':np,'struct':struct})
cs,cc,cp,cm,cn=joints(child);assert cc==19
hashes=struct.unpack_from('<19I',child,cs+cc*132)
append=(len(child)+15)&~15;out=bytearray(child+bytes(append-len(child))+donor)
for field in [48,92,96,100,112]:struct.pack_into('<I',out,field,append+struct.unpack_from('<I',donor,field)[0])
layout=struct.unpack_from('<I',donor,92)[0];assert struct.unpack_from('<I',donor,layout)[0]==1
lp=layout+struct.unpack_from('<I',donor,layout+4)[0]
assert struct.unpack_from('<I',donor,lp+328)[0]==8
out[append+lp+8+6*20:append+lp+8+8*20]=bytes(40)
struct.pack_into('<I',out,append+lp+328,6);struct.pack_into('<I',out,append+lp+356,32)
struct.pack_into('<II',out,append+lp+420,4688*32,4688*32)
mesh=struct.unpack_from('<I',donor,100)[0];assert struct.unpack_from('<I',donor,mesh)[0]==4
remap={};placements=[]
desired=np.eye(4);desired[:3,:3]=np.diag([-1.,1.,-1.]);desired[:3,3]=[0,-.160,.025]
for i in range(4):
 pos=mesh+struct.unpack_from('<I',donor,mesh+4+i*4)[0];bone=struct.unpack_from('<I',donor,pos+40)[0];target=15+i
 assert not any(p==target and k!=target for k,p in enumerate(cp))
 local=np.linalg.inv(cm[cp[target]])@desired;raw=struct.unpack_from('<16f',child,cs+target*64)
 struct.pack_into('<16f',out,cs+target*64,*(list(local[:3,:3].T.flatten())+list(local[:3,3])+list(raw[12:])))
 struct.pack_into('<16f',out,cs+cc*64+target*64,*desired.T.flatten())
 struct.pack_into('<III',out,append+pos+40,hashes[target],target,target);struct.pack_into('<i',out,append+pos+56,-1)
 struct.pack_into('<I',out,append+mesh+4+4*4+i*4,hashes[target]);remap[bone]=hashes[target]
 placements.append({'node':target,'matrix':desired.tolist()})
lod=struct.unpack_from('<I',donor,48)[0]
for i in range(struct.unpack_from('<I',donor,lod)[0]):
 pos=lod+struct.unpack_from('<I',donor,lod+4+i*4)[0];bone=struct.unpack_from('<I',donor,pos+4)[0]
 if bone in remap:struct.pack_into('<I',out,append+pos+4,remap[bone])
# Retain only the two material mappings actually used by the magazine meshes.
mp=struct.unpack_from('<I',donor,112)[0];keys=struct.unpack_from('<3I',donor,mp+4);values=struct.unpack_from('<3Q',donor,mp+16)
assert keys[:2]==(370156025,1677044429)
struct.pack_into('<I2I2Q',out,append+mp,2,*keys[:2],*values[:2])
unit=bytes(out);_,_,ap,am,_=joints(unit);assert ap==cp
for i in range(15):
 for start in [cs,cs+cc*64]:assert unit[start+i*64:start+(i+1)*64]==child[start+i*64:start+(i+1)*64]
assert unit[8:48]==child[8:48] and unit[cs+cc*128:cs+cc*136]==child[cs+cc*128:cs+cc*136]
p=H/'visual-size/extract_particles.py';spec=importlib.util.spec_from_file_location('reader',p);a=importlib.util.module_from_spec(spec);spec.loader.exec_module(a)
archive='9494c346e564d15f';head=a.archive_read(archive,0,72);nt,nf=struct.unpack_from('<II',head,4)
cpu=a.archive_read(archive,0,a.archives[archive][0]);gpu=a.archive_read(archive+'.gpu_resources',0,a.archives[archive+'.gpu_resources'][0])
rows=[struct.unpack_from('<7Q6I',cpu,72+nt*32+i*80) for i in range(nf)]
dr=next(r for r in rows if r[:2]==(0x48d2ddc8e9a80b1e,0xe0a48d0be9a7453f));assert cpu[dr[2]:dr[2]+dr[7]]==donor
streamsize=max(r[3]+r[8] for r in rows);stream=a.archive_read(archive+'.stream',0,streamsize) if streamsize else b''
locations=json.loads((H/'sta11-magazine-research/material-locations.json').read_text());entry=locations['5990E5EFBCA8AE21'];extra=list(entry['row']);ea=entry['archive']
ecpu=a.archive_read(ea,0,a.archives[ea][0]);egpu=a.archive_read(ea+'.gpu_resources',extra[4],extra[9])
cb=(len(cpu)+63)&~63;gb=(len(gpu)+63)&~63
cpu=cpu+bytes(cb-len(cpu))+ecpu;gpu=gpu+bytes(gb-len(gpu))+egpu
extra[2]+=cb;extra[5]+=cb;extra[6]=gb+extra[6]-extra[4];extra[4]=gb;extra[3]=0;extra[12]=len(rows);rows.append(tuple(extra))
mat=struct.unpack_from('<I',unit,112)[0];mn=struct.unpack_from('<I',unit,mat)[0];materials=struct.unpack_from('<'+'Q'*mn,unit,mat+4+mn*4)
assert set(materials)<={r[0] for r in rows if r[1]==0xeac0b497876adedf}
# Preserve complete stock donor archive data, add private converted GPU payload.
gstart=(len(gpu)+63)&~63;newgpu=gpu+bytes(gstart-len(gpu))+rigid
visuals=[]
for basename in ['49f1972458f7ccec','e16e0aa7740716a2']:
 name='Addon/'+basename+'.patch_0';old=before[name];ot,of=struct.unpack_from('<II',old,4)
 tr=next(struct.unpack_from('<7Q6I',old,72+ot*32+i*80) for i in range(of) if struct.unpack_from('<Q',old,72+ot*32+i*80)[0]==0x02cd7321cd8445f5)
 target=list(tr);counts=Counter(r[1] for r in rows);counts[target[1]]+=1
 start=(72+len(counts)*32+(len(rows)+1)*80+63)&~63
 b=bytearray(start);b.extend(unit);b.extend(bytes(-len(b)%64));base=len(b);b.extend(cpu)
 target[2]=start;target[5]=start+tr[5]-tr[2];target[7]=len(unit)
 target[3]=0;target[8]=0;target[4]=gstart;target[6]=gstart+dr[6]-dr[4];target[9]=len(rigid);target[12]=len(rows)
 translated=[]
 for row in rows:
  row=list(row);row[2]+=base
  if row[5]:row[5]+=base
  translated.append(row)
 types=[]
 for kind,count in sorted(counts.items()):
  t=next(list(struct.unpack_from('<IIQIIII',cpu,72+i*32)) for i in range(nt) if struct.unpack_from('<Q',cpu,72+i*32+8)[0]==kind);t[3]=count;types.append(struct.pack('<IIQIIII',*t))
 prefix=struct.pack('<III20sQQ24s',0xf0000011,len(counts),len(rows)+1,b'',len(b),len(newgpu),b'')+b''.join(types)+b''.join(struct.pack('<7Q6I',*r) for r in translated+[target]);b[:len(prefix)]=prefix
 for original,row in zip(rows,translated):assert b[row[2]:row[2]+row[7]]==cpu[original[2]:original[2]+original[7]]
 assert b[target[2]:target[2]+target[7]]==unit
 files[name]=bytes(b);files[name+'.gpu_resources']=newgpu;files[name+'.stream']=stream
 visuals.append({'archive':basename,'cpu_buffer_delta':target[5]-target[2],'gpu_buffer_delta':target[6]-target[4],'resources':len(rows)+1,'donor_resources_exact':True})
oldruntime=before['Source/runtime.lua'];runtime=oldruntime.replace(b'0.1.57-one-two-test',b'0.1.59-one-two-test');assert oldruntime.count(b'0.1.57-one-two-test')==1
files['Source/runtime.lua']=runtime;files['Source/one_two_build_data.py']=before['Source/one_two_build_data.py'].replace(b'0.1.57-one-two-test',b'0.1.59-one-two-test')
serialize=fn('build_hidden_aligned_v0150.py','archive',{'struct':struct,'Counter':Counter})
main='Addon/9ba626afa44a3aa3.patch_0';blob=before[main];tc,fc=struct.unpack_from('<II',blob,4);resources=[];changed=0
for i in range(fc):
 row=struct.unpack_from('<7Q6I',blob,72+tc*32+i*80);p=blob[row[2]:row[2]+row[7]]
 if p[8:]==oldruntime:p=struct.pack('<II',len(runtime),2)+runtime;changed+=1
 resources.append((row[0],row[1],p,row))
assert changed==1;files[main]=serialize(resources)
for n,b in before.items():
 if n.startswith('Source/') and n not in ['Source/runtime.lua','Source/one_two_build_data.py']:assert files[n]==b
 if n.startswith('Addon/') and not any(n.startswith('Addon/'+key) for key in ['49f1972458f7ccec','e16e0aa7740716a2','9ba626afa44a3aa3']):assert files[n]==b
sys.path.insert(0,str(R/'work/expanded-stat-editor'));from lua_runtime import Lua51
lua=Lua51()
for n,b in files.items():
 if n.startswith('Source/') and n.endswith('.lua'):lua.compile(b,'@'+n)
lua.run((H/'grip-ammo-hud-v0155/private-profile-fixture.lua').read_bytes(),'@unchanged-profiles')
manifest=json.loads(files['manifest.json']);manifest['Name']='SG-8P Punisher Plasma Magazine Grip Test v0.1.59';manifest['Description']='Rigid StA11 magazine visual handhold replacing double grips. Materials/mount/hand fit require gameplay test.'
files['manifest.json']=(json.dumps(manifest,indent=2)+'\n').encode()
files['README.txt']=b'''Punisher Plasma v0.1.59 MAGAZINE HANDHOLD TEST
StA11 cylindrical magazine replaces both angled grips visually. Its rest
geometry is converted to rigid vertices; stock positions/normals/UV/color/index
data preserved, skin attributes removed. No new weapon entity or animation edit.
Rigid magazine oriented under fore-end, original size retained. Mount/palm fit,
materials/shader selection and all poses UNVERIFIED until user test.
Functional0..14/IK12/muzzle13/skeleton/controller exact057. Ammo15/1/1/1,
LEFT NORMAL/SHOTGUN,2xreload,tuning/protected weapons/full native safety retained.
Offline compile/profile/geometry/archive checks PASS;059startup/gameplay NOTRUN.
Replace current Punisher candidate with059; import/Purge/Deploy ALL Addon files,
including BOTH CPU/GPU/STREAM sets. Restart and report launched; await fresh
059source_installed=true/Ready before firing. Check armory material/mount first,
then hand fit idle/ADS/reload, muzzle,LEFT selector and both ammo pools.
User deploys/gameplays. Final release gated. Restart after replacement/removal.
Known actual OneTwo mission-launch crash remains user-reported/unverified.
'''
for n in list(files):
 if n.startswith('Visual/') or n.startswith('Verification/'):files['Baseline057/'+n]=files.pop(n)
files['Visual/02cd7321cd8445f5-magazine.unit']=unit
report={'status':'PASS','scope':'Offline rigid magazine candidate only','baseline':sha(BASE.read_bytes()),'placements':placements,'visual_archives':visuals,'material_resources':[f'{m:016X}' for m in materials],'vertices':4688,'stride':32,'meshes':4,'functional_native_profiles_exact057':True,'animation_edits':False,'startup':'NOTRUN','gameplay':'NOTRUN','material_mount_hand_fit':'UNVERIFIED'}
files['Verification/scoped-v0159.json']=(json.dumps(report,indent=2)+'\n').encode();files['Verification/binding-layout-audit.json']=(H/'sta11-magazine-research/binding-layout-audit.json').read_bytes();files['Source/build_magazine_visual_v0159.py']=Path(__file__).read_bytes()
with zipfile.ZipFile(DEST,'x',zipfile.ZIP_DEFLATED) as z:
 for n,b in files.items():z.writestr(n,b)
with zipfile.ZipFile(DEST) as z:assert z.testzip() is None and all(z.read(n)==b for n,b in files.items())
for n,b in files.items():
 if n.startswith('Source/'):p=O/n;p.parent.mkdir(parents=True,exist_ok=True);p.write_bytes(b)
(O/'02cd7321cd8445f5-magazine.unit').write_bytes(unit);report.update(candidate=str(DEST),sha256=sha(DEST.read_bytes()));(O/'package-verification.json').write_text(json.dumps(report,indent=2)+'\n');print(json.dumps({'candidate':str(DEST),'sha256':report['sha256'],'status':'PASS'}))
