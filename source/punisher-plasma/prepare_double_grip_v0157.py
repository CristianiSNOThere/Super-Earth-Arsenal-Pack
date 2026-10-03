"""Two rigid visual copies, retained nineteen-joint weapon skeleton."""
from pathlib import Path
import ast,json,struct,zipfile
import numpy as np
H=Path(__file__).resolve().parent;O=H/'double-grip-v0157';O.mkdir(exist_ok=True)
with zipfile.ZipFile(H.parents[1]/'outputs/Punisher-Plasma-Grip-Mount-Test-v0.1.56.zip') as z:old=z.read('Visual/02cd7321cd8445f5-stock-origin-grip.unit')
tree=ast.parse((H/'audit_hidden_aligned_v0150.py').read_text());fn=next(n for n in tree.body if isinstance(n,ast.FunctionDef) and n.name=='joints')
ns={'np':np,'struct':struct};exec(compile(ast.Module(body=[fn],type_ignores=[]),'joints','exec'),ns)
s,c,parents,mats,_=ns['joints'](old);hashes=struct.unpack_from('<19I',old,s+c*132)
out=bytearray(old);placements=[]
for j,rot,z in [(15,np.diag([-1.,1.,-1.]),.035),(17,np.eye(3),.040)]:
 desired=np.eye(4);desired[:3,:3]=rot;desired[:3,3]=[0,.03195076808333397,z]
 local=np.linalg.inv(mats[parents[j]])@desired;raw=struct.unpack_from('<16f',old,s+j*64)
 struct.pack_into('<16f',out,s+j*64,*(list(local[:3,:3].T.flatten())+list(local[:3,3])+list(raw[12:])))
 struct.pack_into('<16f',out,s+c*64+j*64,*desired.T.flatten());placements.append({'node':j,'matrix':desired.tolist()})
def append(b):
 out.extend(bytes(-len(out)%16));pos=len(out);out.extend(b);return pos
mesh=struct.unpack_from('<I',old,100)[0];assert struct.unpack_from('<I',old,mesh)[0]==4
infos=[]
for i in range(4):
 pos=mesh+struct.unpack_from('<I',old,mesh+4+i*4)[0]
 nm,mo=struct.unpack_from('<II',old,pos+104);ng,go=struct.unpack_from('<II',old,pos+120)
 size=max(128,mo+nm*4,go+ng*24);infos.append(old[pos:pos+size])
table=bytearray(4+8*8);struct.pack_into('<I',table,0,8)
for copy,node in [(0,15),(1,17)]:
 for i,info in enumerate(infos):
  chunk=bytearray(info);struct.pack_into('<III',chunk,40,hashes[node],node,node)
  index=copy*4+i;struct.pack_into('<I',table,4+index*4,len(table));struct.pack_into('<I',table,4+8*4+index*4,hashes[node]);table.extend(chunk)
newmesh=append(table);struct.pack_into('<I',out,100,newmesh)
lod=struct.unpack_from('<I',old,48)[0];count=struct.unpack_from('<I',old,lod)[0];assert count==2
lt=bytearray(4+count*4);struct.pack_into('<I',lt,0,count)
for i in range(count):
 pos=lod+struct.unpack_from('<I',old,lod+4+i*4)[0];nf,ne=struct.unpack_from('<II',old,pos+12)
 group=bytearray(old[pos:pos+20]+bytes((nf+ne)*4))
 for k in range(ne):
  ep=pos+struct.unpack_from('<I',old,pos+20+k*4)[0];ni=struct.unpack_from('<I',old,ep+8)[0]
  idx=list(struct.unpack_from('<'+'I'*ni,old,ep+12));assert all(0<=v<4 for v in idx)
  struct.pack_into('<I',group,20+k*4,len(group));group.extend(old[ep:ep+8]+struct.pack('<I',2*ni)+struct.pack('<'+'I'*(2*ni),*(idx+[v+4 for v in idx])))
 for k in range(nf):
  fp=pos+struct.unpack_from('<I',old,pos+20+ne*4+k*4)[0]
  footer=bytearray(old[fp:fp+40]);bounds=list(struct.unpack_from('<6f',footer))
  # Conservative combined AABB covering both rigid copies, including inversion.
  bounds[:6]=[-.04,-.12,-.06,.04,.15,.13];struct.pack_into('<6f',footer,0,*bounds)
  struct.pack_into('<I',group,20+ne*4+k*4,len(group));group.extend(footer)
 struct.pack_into('<I',lt,4+i*4,len(lt));lt.extend(group)
newlod=append(lt);struct.pack_into('<I',out,48,newlod)
new=bytes(out);_,_,p,mm,_=ns['joints'](new);assert p==parents
allowed=set(range(48,52))|set(range(100,104))
for j in [15,17]:allowed.update(range(s+j*64,s+j*64+48));allowed.update(range(s+c*64+j*64,s+c*64+(j+1)*64))
assert all(a==b or i in allowed for i,(a,b) in enumerate(zip(old,new)))
for i in range(15):
 for start in [s,s+c*64]:assert new[start+i*64:start+(i+1)*64]==old[start+i*64:start+(i+1)*64]
(O/'02cd7321cd8445f5-double-grip.unit').write_bytes(new)
report={'scope':'Offline two rigid visual copies; no new weapon entity or animation changes','old_size':len(old),'new_size':len(new),'placements':placements,'mesh_count':8,'lod_groups':2,'all_lod_entries_duplicate_both_copies':True,'functional_nodes_exact':True,'gpu_materials_layouts_unchanged':True,'lower_drop_m':.04,'upper_inversion':'180 degrees about longitudinal Y axis','rail_seam_hand_fit':'UNVERIFIED'}
(O/'geometry-audit.json').write_text(json.dumps(report,indent=2)+'\n');print(json.dumps(report))
