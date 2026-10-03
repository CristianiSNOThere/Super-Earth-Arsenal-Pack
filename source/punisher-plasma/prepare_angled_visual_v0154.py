"""Isolated render-only angled grip draft. No game access or deployment."""
from pathlib import Path
import ast,struct,json,hashlib,importlib.util,zipfile
import numpy as np
H=Path(__file__).resolve().parent;O=H/'angled-v0154';O.mkdir(exist_ok=True)
base=H.parents[1]/'outputs/Punisher-Plasma-Grip-Tuning-Test-v0.1.53.zip'
assert hashlib.sha256(base.read_bytes()).hexdigest().upper()=='29FDEBB2FF6A7E9574D69883D81F0F2A5A4C2E1C94021B2B8798DA284B71C680'
with zipfile.ZipFile(base) as z:child=z.read('Visual/02cd7321cd8445f5-hidden-aligned.unit')
donor=(H/'unused-grip-assets/411c4fd07740a7dd.unit').read_bytes()
tree=ast.parse((H/'audit_hidden_aligned_v0150.py').read_text());fn=next(n for n in tree.body if isinstance(n,ast.FunctionDef) and n.name=='joints')
ns={'struct':struct,'np':np};exec(compile(ast.Module(body=[fn],type_ignores=[]),'joints','exec'),ns)
cs,cc,cp,cm,cn=ns['joints'](child);ds,dc,dp,dm,dn=ns['joints'](donor)
assert cc==19 and cn(0x67c94e4b)==12 and cn(0x57520abf)==13
donor_ik=dn(0x67c94e4b)
mesh=struct.unpack_from('<I',donor,100)[0];count=struct.unpack_from('<I',donor,mesh)[0];assert count==4
append=(len(child)+15)&~15;out=bytearray(child+bytes(append-len(child))+donor)
# Retain original functional header, skeleton maps, state machine and all19 hashes.
for field in [48,92,96,100,112]:
    offset=struct.unpack_from('<I',donor,field)[0];assert 0<offset<len(donor)
    struct.pack_into('<I',out,field,append+offset)
hashes=struct.unpack_from('<19I',child,cs+cc*132)
transforms=[]
remap={}
for i in range(count):
    o=mesh+struct.unpack_from('<I',donor,mesh+4+i*4)[0]
    _,bound,transform,_,skel,layout=struct.unpack_from('<IIIIii',donor,o+40)
    assert skel==-1 and bound==transform
    target=15+i;assert not any(p==target and j!=p for j,p in enumerate(cp))
    desired=cm[12]@np.linalg.inv(dm[donor_ik])@dm[transform]
    local=np.linalg.inv(cm[cp[target]])@desired
    lo,go=cs+target*64,cs+cc*64+target*64
    old=struct.unpack_from('<16f',child,lo)
    struct.pack_into('<16f',out,lo,*(list(local[:3,:3].T.flatten())+list(local[:3,3])+list(old[12:])))
    struct.pack_into('<16f',out,go,*desired.T.flatten())
    struct.pack_into('<III',out,append+o+40,hashes[target],target,target)
    remap[struct.unpack_from('<I',donor,o+40)[0]]=hashes[target]
    struct.pack_into('<I',out,append+mesh+4+count*4+i*4,hashes[target])
    transforms.append(dict(donor_joint=transform,target_joint=target,world_rest=desired.tolist()))
# LOD group headers name the same render bones; indices remain mesh indices.
lod=struct.unpack_from('<I',donor,48)[0]
for i in range(struct.unpack_from('<I',donor,lod)[0]):
    group=lod+struct.unpack_from('<I',donor,lod+4+i*4)[0]
    bone=struct.unpack_from('<I',donor,group+4)[0]
    if bone in remap:struct.pack_into('<I',out,append+group+4,remap[bone])
out=bytes(out);_,_,ap,am,_=ns['joints'](out);assert ap==cp
for i in range(15):
    for start in [cs,cs+cc*64]:assert out[start+i*64:start+(i+1)*64]==child[start+i*64:start+(i+1)*64]
assert out[8:48]==child[8:48] and out[cs+cc*128:cs+cc*136]==child[cs+cc*128:cs+cc*136]
unit=O/'02cd7321cd8445f5-angled.unit';unit.write_bytes(out)
report=dict(scope='Offline rigid geometry transplant and rest-pose placement ONLY',baseline_sha256=hashlib.sha256(child).hexdigest(),candidate_sha256=hashlib.sha256(out).hexdigest(),functional_joints_0_through14_identical=True,ik12_muzzle13_identical=True,bones_controller_refs_identical=True,hierarchy_names_identical=True,render_joint_only_changes=[15,16,17,18],geometry_header_fields=[48,92,96,100,112],transforms=transforms,animation_edits=False,game_access=False,animated_hand_fit='UNVERIFIED',rendering='NOTRUN',material_dependencies='Package construction pending',limitations=['Geometry rests aligned to preserved childIK12 using donorIK; current animated target may differ.','Only rendering joint transforms change; original19joint hierarchy retained.'])
(O/'visual-draft-audit.json').write_text(json.dumps(report,indent=2)+'\n');print(json.dumps({k:report[k] for k in ['candidate_sha256','functional_joints_0_through14_identical','animated_hand_fit']},indent=2))
