from pathlib import Path
import ast,hashlib,json,struct,zipfile,sys
from collections import Counter
H=Path(__file__).resolve().parent;R=H.parents[1];O=H/'pellet-radius-v0165';BASE=R/'outputs/Punisher-Plasma-Radius-Ammo-Test-v0.1.64.zip';DEST=R/'outputs/Punisher-Plasma-Pellet-Radius-Test-v0.1.65.zip'
assert not O.exists() and not DEST.exists()
sha=lambda b:hashlib.sha256(b).hexdigest().upper()
assert sha(BASE.read_bytes())=='8774E91DC77C53966FDB1549B19C109E613D164757979B36F6587C2AC0E63930'
with zipfile.ZipFile(BASE) as z:assert z.testzip() is None;a={n:z.read(n) for n in z.namelist()}
b=dict(a);runtime=a['Source/runtime.lua'].decode()
edits={'Source/owned_profile.lua':[("ffi.cast('float*',ep+16)[0]=1","ffi.cast('float*',ep+16)[0]=0.5"),("ffi.cast('float*',ep+20)[0]=1","ffi.cast('float*',ep+20)[0]=0.5"),("ffi.cast('float*',ep+24)[0]=2","ffi.cast('float*',ep+24)[0]=0.5")]}

for n,changes in edits.items():
 old=a[n].decode().replace('\r\n','\n');new=old
 for x,y in changes:assert new.count(x)==1,(n,x);new=new.replace(x,y)
 assert runtime.count(old)==1,n;runtime=runtime.replace(old,new);b[n]=new.encode()
assert runtime.count('0.1.64-one-two-test')==1
b['Source/runtime.lua']=runtime.replace('0.1.64-one-two-test','0.1.65-one-two-test').encode()
b['Source/one_two_build_data.py']=a['Source/one_two_build_data.py'].replace(b'0.1.64-one-two-test',b'0.1.65-one-two-test')
# Execute both actual packaged constructors against private allocated source fixtures.
orig=(H/'build_final_tuning_v0152.py').read_text();tree=ast.parse(orig)
fixturetail=next(n.value.value for n in ast.walk(tree) if isinstance(n,ast.AugAssign) and isinstance(n.target,ast.Name) and n.target.id=='fixture' and isinstance(n.value,ast.Constant) and 'local function u(s,o)' in str(n.value.value))
fixturetail=fixturetail.replace("if r.role=='parent_projectile'then for o=8,11 do allowed[o]=true end\n elseif r.role=='parent_magazine'then for o=136,151 do allowed[o]=true end","if r.role=='parent_magazine'then for o=136,139 do allowed[o]=true end")
fixturetail=fixturetail.replace('u(roles.parent_magazine,136)==30','u(roles.parent_magazine,136)==17')
fixturetail=fixturetail.replace('u(x.records.normal_damage,4)==175 and u(x.records.normal_damage,8)==113','u(x.records.normal_damage,4)==350 and u(x.records.normal_damage,8)==225')
fixturetail=fixturetail.replace("if k=='normal_damage'then assert(s:sub(1,4)==t:sub(1,4) and s:sub(13)==t:sub(13),'Normal status/force/AP changed')", "if k=='explosion'then\n local ns,nt=normalize(k,s),normalize(k,t)\n for o=0,#ns-1 do assert(ns:byte(o+1)==nt:byte(o+1) or (o>=16 and o<28),'Unexpected pellet explosion edit')end\n assert(f(s,16)==1 and f(s,20)==1 and f(s,24)==2)\n assert(f(t,16)==0.5 and f(t,20)==0.5 and f(t,24)==0.5)")
fixture="local ffi=require('ffi')\nlocal function unhex(s)return(s:gsub('..',function(x)return string.char(tonumber(x,16))end))end\n"+next(l for l in a['Source/runtime.lua'].decode().splitlines() if l.startswith('local D='))+'\n'
for name,n,files in [('oldprofile','one_two_source_profile.lua',a),('newprofile','one_two_source_profile.lua',b),('modes','mode_profile.lua',b),('oldowned','owned_profile.lua',a),('newowned','owned_profile.lua',b)]:fixture+='local '+name+'=(function()\n'+files['Source/'+n].decode()+'\nend)()\n'
fixturetail=fixturetail.replace("if r.role=='parent_magazine'then for o=136,139 do allowed[o]=true end","if false then")
fixture+=fixturetail
sys.path.insert(0,str(R/'work/expanded-stat-editor'));from lua_runtime import Lua51
lua=Lua51()
for n,data in b.items():
 if n.startswith('Source/') and n.endswith('.lua'):lua.compile(data,'@'+n)
lua.run(fixture.encode(),'@v0165-private-preservation')
fn=next(n for n in ast.parse((H/'build_hidden_aligned_v0150.py').read_text()).body if isinstance(n,ast.FunctionDef) and n.name=='archive');ns={'struct':struct,'Counter':Counter};exec(compile(ast.Module(body=[fn],type_ignores=[]),'archive','exec'),ns)
main='Addon/9ba626afa44a3aa3.patch_0';blob=a[main];tc,fc=struct.unpack_from('<II',blob,4);rows=[];count=0
for i in range(fc):
 row=struct.unpack_from('<7Q6I',blob,72+tc*32+i*80);data=blob[row[2]:row[2]+row[7]]
 if data[8:]==a['Source/runtime.lua']:data=struct.pack('<II',len(b['Source/runtime.lua']),2)+b['Source/runtime.lua'];count+=1
 rows.append((row[0],row[1],data,row))
assert count==1;b[main]=ns['archive'](rows)
for n,v in a.items():
 if n.startswith('Addon/') and n!=main:assert b[n]==v,n
 if n.startswith('Visual/'):assert b[n]==v,n
 if n.startswith('Source/') and n not in [*edits,'Source/runtime.lua','Source/one_two_build_data.py']:assert b[n]==v,n
manifest=json.loads(a['manifest.json']);manifest['Name']='SG-8P Punisher Plasma Pellet Radius Test v0.1.65';manifest['Description']='Pellet explosion radii0.5/0.5/0.5m; normal17 loaded plus one spare17 magazine. Accepted magazine grip retained. Test candidate.';b['manifest.json']=(json.dumps(manifest,indent=2)+'\n').encode()
readme=a['README.txt'].decode();warning=readme.split('Punisher Plasma v0.1.64')[0]
b['README.txt']=(warning+'Punisher Plasma v0.1.65 PELLET RADIUS TEST\n\nPellet explosion radii offsets16/20/24:0.5/0.5/0.5 metres (previous1/1/2). Normal17 rounds, one spare17-round magazine; start/refill/max remain1/1/1. Siege Ready can add magazines. All other tuning, accepted grip/alignment, pellet20/60, reload2x, native thread safety/refusal/rollback/storage and protected weapons preserved.\n\nUser deploys ALL Addon files after unequipping and closing fully; restart, keep game focused during loading. Alt-Tab-from-Chrome startup trigger remains unresolved. Require fresh source_installed=true/Ready before firing. Offline preservation checks PASS; startup/runtime values/gameplay NOTRUN. Final release gated. No publication.\n').encode()
report={'status':'PASS','scope':'Offline actual packaged Lua construction and byte preservation','normal_capacity':17,'normal_start_refill_max_spares':[1,1,1],'pellet_radii_m':[0.5,0.5,0.5],'radius_offsets':[16,20,24],'all_source_profiles_exact064':True,'owned_only_pellet_radius_fields_changed_after_pointer_normalization':True,'visuals_and_native_safety_exact064':True,'source_immutability_epoch_refusal_storage_retention_fixture':'PASS','fresh_startup':'NOTRUN','gameplay':'NOTRUN','baseline_sha256':sha(BASE.read_bytes())}
for n in list(b):
 if n.startswith('Verification/'):b['Baseline064/'+n]=b.pop(n)
b['Verification/scoped-v0165.json']=(json.dumps(report,indent=2)+'\n').encode();b['Verification/private-profile-fixture.lua']=fixture.encode();b['Source/build_pellet_radius_v0165.py']=Path(__file__).read_bytes()
with zipfile.ZipFile(DEST,'x',zipfile.ZIP_DEFLATED) as z:
 for n,v in b.items():z.writestr(n,v)
with zipfile.ZipFile(DEST) as z:assert z.testzip() is None and all(z.read(n)==v for n,v in b.items())
O.mkdir()
for n,v in b.items():
 if n.startswith('Source/'):p=O/n;p.parent.mkdir(parents=True,exist_ok=True);p.write_bytes(v)
report.update(candidate=str(DEST),sha256=sha(DEST.read_bytes()));(O/'package-verification.json').write_text(json.dumps(report,indent=2)+'\n');(O/'private-profile-fixture.lua').write_text(fixture);print(json.dumps(report))
