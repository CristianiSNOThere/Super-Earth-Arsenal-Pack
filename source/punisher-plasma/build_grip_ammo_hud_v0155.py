"""Immutable054 -> measured render placement, normal15/1/1/1, LEFT display.
Offline builder. No deployment, game access or animation edits.
"""
from pathlib import Path
import ast,hashlib,json,struct,sys,zipfile
from collections import Counter
import numpy as np
H=Path(__file__).resolve().parent;ROOT=H.parents[1];O=H/'grip-ammo-hud-v0155'
BASE=ROOT/'outputs/Punisher-Plasma-Angled-Grip-Mags-Test-v0.1.54.zip'
DEST=ROOT/'outputs/Punisher-Plasma-Grip-Ammo-Left-HUD-Test-v0.1.55.zip'
assert not DEST.exists(),'Immutable version already exists'
sha=lambda b:hashlib.sha256(b).hexdigest()
assert sha(BASE.read_bytes()).upper()=='0B1A2CC7D01AB228C59C549E2FEEE37C70569FE296F56592E89819875ABBAA3D'
O.mkdir(exist_ok=True)
with zipfile.ZipFile(BASE) as z:files={n:z.read(n) for n in z.namelist()};assert z.testzip() is None
before=dict(files)
tree=ast.parse((H/'audit_hidden_aligned_v0150.py').read_text());fn=next(n for n in tree.body if isinstance(n,ast.FunctionDef) and n.name=='joints')
ns={'np':np,'struct':struct};exec(compile(ast.Module(body=[fn],type_ignores=[]),'joints','exec'),ns)
unit=before['Visual/02cd7321cd8445f5-angled.unit'];donor=(H/'unused-grip-assets/411c4fd07740a7dd.unit').read_bytes()
cs,cc,cp,cm,cn=ns['joints'](unit);ds,dc,dp,dm,dn=ns['joints'](donor)
reports=[json.loads((H/'angled-v0154'/f).read_text()) for f in ['held-world-join-20261003.json','held-world-join-second-20261003.json']]
targets=[]
for r in reports:
 assert r['status']=='PASS' and r['game_calls']==r['game_writes']==0
 child=next(x for x in r['controllers'] if x['role']=='child');character=next(x for x in r['controllers'] if x['role']=='wielder')
 assert any(x['constraint_hash']=='0xc92a44d' and x['target_unit_id']==child['unit_id'] and x['target_node']==12 for x in character['ik_bindings'])
 assert child['maximum_sample_drift']<0.01 and child['joint_count']==19
 mats={int(i):np.array(m).reshape(4,4).T for i,m in child['world_matrices'].items()}
 target=np.linalg.inv(mats[0])@mats[12];targets.append(target)
 for i in [13,15,16,17,18]:assert np.max(np.abs(np.linalg.inv(mats[0])@mats[i]-cm[i]))<0.00005
assert np.max(np.abs(targets[0]-targets[1]))<0.00005
# Use a measured rigid target: remove numerical scale/shear from VM_READ matrix.
target=targets[0].copy();u,_,v=np.linalg.svd(target[:3,:3]);target[:3,:3]=u@v
assert np.linalg.det(target[:3,:3])>0.99999
assert np.max(np.abs(target-targets[0]))<0.000001
mesh=struct.unpack_from('<I',donor,100)[0];count=struct.unpack_from('<I',donor,mesh)[0];assert count==4
newunit=bytearray(unit);allowed=set();placements=[]
for i in range(count):
 info=mesh+struct.unpack_from('<I',donor,mesh+4+i*4)[0];dj=struct.unpack_from('<I',donor,info+48)[0]
 j=15+i;assert not any(p==j and k!=j for k,p in enumerate(cp))
 desired=target@np.linalg.inv(dm[dn(0x67c94e4b)])@dm[dj]
 local=np.linalg.inv(cm[cp[j]])@desired;lo=cs+j*64;go=cs+cc*64+j*64
 old=struct.unpack_from('<16f',unit,lo)
 struct.pack_into('<16f',newunit,lo,*(list(local[:3,:3].T.flatten())+list(local[:3,3])+list(old[12:])))
 struct.pack_into('<16f',newunit,go,*desired.T.flatten())
 allowed.update(range(lo,lo+48));allowed.update(range(go,go+64))
 placements.append({'node':j,'matrix':desired.tolist()})
newunit=bytes(newunit);assert len(newunit)==len(unit)
assert all(a==b or i in allowed for i,(a,b) in enumerate(zip(unit,newunit)))
_,_,ap,am,_=ns['joints'](newunit);assert ap==cp
for i in range(15):
 for start in [cs,cs+cc*64]:assert newunit[start+i*64:start+(i+1)*64]==unit[start+i*64:start+(i+1)*64]
for basename in ['49f1972458f7ccec','e16e0aa7740716a2']:
 name='Addon/'+basename+'.patch_0';b=bytearray(files[name]);tc,fc=struct.unpack_from('<II',b,4)
 row=next(struct.unpack_from('<7Q6I',b,72+tc*32+i*80) for i in range(fc) if struct.unpack_from('<Q',b,72+tc*32+i*80)[0]==0x02cd7321cd8445f5)
 assert b[row[2]:row[2]+row[7]]==unit and row[7]==len(newunit)
 b[row[2]:row[2]+row[7]]=newunit;files[name]=bytes(b)
 assert files[name][:row[2]]==before[name][:row[2]] and files[name][row[2]+row[7]:]==before[name][row[2]+row[7]:]
runtime=files['Source/runtime.lua'].decode()
changes={
 'Source/one_two_source_profile.lua':[
  ('s=change(s,184,word(11)..word(3))',
   "-- Native function11 reads these parent-owned display fields for its two LEFT choices.\n   s=change(s,160,string.char(0xa7,0x0d,0x93,0x91,0xc0,0xe4,0xd9,0x07,0xbb,0x6b,0x89,0x2f,0x96,0xb0,0x7b,0x06))\n   s=change(s,176,word(0xf3222616)..word(0xff4b018d)) -- stock localized NORMAL / SHOTGUN\n   s=change(s,184,word(11)..word(0)) -- preserve LEFT underbarrel dispatch; remove redundant right Semi"),
  ('word(15)..word(2)..word(2)..word(2)) -- capacity/start/refill/max:15 loaded + two spare15 magazines',
   'word(15)..word(1)..word(1)..word(1)) -- capacity/start/refill/max:15 loaded + one spare15 magazine')],
 'Source/one_two_startup.lua':[
  ('normal=350/225 blast;60RPM;15 capacity;two spare15 magazines;refill two',
   'normal=350/225 blast;60RPM;15 capacity;one spare15 magazine;refill one;LEFT NORMAL/SHOTGUN')]
}
for name,pairs in changes.items():
 old=files[name].decode().replace('\r\n','\n');new=old
 for a,b in pairs:assert new.count(a)==1,(name,a);new=new.replace(a,b)
 assert runtime.count(old)==1;runtime=runtime.replace(old,new);files[name]=new.encode()
assert runtime.count('0.1.54-one-two-test')==1
runtime=runtime.replace('0.1.54-one-two-test','0.1.55-one-two-test');files['Source/runtime.lua']=runtime.encode()
files['Source/one_two_build_data.py']=files['Source/one_two_build_data.py'].replace(b'0.1.54-one-two-test',b'0.1.55-one-two-test')
sys.path.insert(0,str(ROOT/'work/expanded-stat-editor'));from lua_runtime import Lua51
lua=Lua51()
for name,b in files.items():
 if name.startswith('Source/') and name.endswith('.lua'):lua.compile(b,'@'+name)
fixture="local ffi=require('ffi')\nlocal function unhex(s)return(s:gsub('..',function(x)return string.char(tonumber(x,16))end))end\n"+next(l for l in runtime.splitlines() if l.startswith('local D='))+'\n'
for label,name,source in [('old','Source/one_two_source_profile.lua',before),('new','Source/one_two_source_profile.lua',files),('modes','Source/mode_profile.lua',files)]:fixture+='local '+label+'=(function()\n'+source[name].decode()+'\nend)()\n'
fixture+=r'''
local function u(s,o)local b=ffi.new('uint32_t[1]');ffi.copy(b,s:sub(o+1,o+4),4);return tonumber(b[0])end
local stock={weapon=D.components.weapon.bytes,projectile=D.components.projectile.bytes,magazine=D.components.magazine.bytes}
local a=old(D.source_rows,modes,stock,D.child_reload_template)
local b=new(D.source_rows,modes,stock,D.child_reload_template)
assert(#a==8 and #b==8)
for i,r in ipairs(a)do local s=b[i]
 assert(r.role==s.role and r.before==s.before and r.owner==s.owner and r.index==s.index and r.stride==s.stride)
 if r.role=='parent_magazine'then
  assert(u(s.after,136)==15 and u(s.after,140)==1 and u(s.after,144)==1 and u(s.after,148)==1)
  assert(r.after:sub(1,140)==s.after:sub(1,140) and r.after:sub(153)==s.after:sub(153))
 elseif r.role=='parent_weapon'then
  assert(r.after:sub(1,160)==s.after:sub(1,160) and r.after:sub(193)==s.after:sub(193))
  assert(u(s.after,160)==0x91930da7 and u(s.after,164)==0x07d9e4c0)
  assert(u(s.after,168)==0x2f896bbb and u(s.after,172)==0x067bb096)
  assert(u(s.after,176)==0xf3222616 and u(s.after,180)==0xff4b018d)
  assert(u(s.after,184)==11 and u(s.after,188)==0)
  assert(u(s.after,144)==2 and u(s.after,148)==0 and u(s.after,152)==0 and u(s.after,156)==8)
 else assert(r.after==s.after,'Unrelated source profile changed: '..r.role)end
end
'''
lua.run(fixture.encode(),'@v0155-private-profile-fixture');(O/'private-profile-fixture.lua').write_text(fixture)
tree=ast.parse((H/'build_hidden_aligned_v0150.py').read_text());fn=next(n for n in tree.body if isinstance(n,ast.FunctionDef) and n.name=='archive')
ns={'struct':struct,'Counter':Counter};exec(compile(ast.Module(body=[fn],type_ignores=[]),'serializer','exec'),ns)
main='Addon/9ba626afa44a3aa3.patch_0';blob=files[main];tc,fc=struct.unpack_from('<II',blob,4);resources=[];replaced=0
for i in range(fc):
 r=struct.unpack_from('<7Q6I',blob,72+tc*32+i*80);p=blob[r[2]:r[2]+r[7]]
 if p[8:]==before['Source/runtime.lua']:p=struct.pack('<II',len(files['Source/runtime.lua']),2)+files['Source/runtime.lua'];replaced+=1
 resources.append((r[0],r[1],p,r))
assert replaced==1;files[main]=ns['archive'](resources)
retained={}
for name,b in before.items():
 if name.startswith('Source/') and name not in {*changes,'Source/runtime.lua','Source/one_two_build_data.py'}:assert files[name]==b;retained[name]=sha(b)
 if name.startswith('Addon/') and name not in [main,'Addon/49f1972458f7ccec.patch_0','Addon/e16e0aa7740716a2.patch_0']:assert files[name]==b
for path,digest in [('D:/SteamLibrary/steamapps/common/Helldivers 2/bin/helldivers2.exe','F5FEE03DCFDB2E553A4752C283590950AC13316B376D8196AA556FF0400D5F06'),('D:/SteamLibrary/steamapps/common/Helldivers 2/data/game/game.dll','2E2C3B7C2500646DADD5F2B4C6E0504DBB7E7896139F64CDDC0D1813C718F51E')]:assert sha(Path(path).read_bytes()).upper()==digest
manifest=json.loads(files['manifest.json']);guid=manifest['Guid'];options=manifest['Options']
manifest['Name']='SG-8P Punisher Plasma Grip, Ammo and Left HUD Test v0.1.55'
manifest['Description']='Measured grip position/orientation candidate; normal15/1/1/1 ammo; LEFT Normal/Shotgun selector. Gameplay verification pending.'
files['manifest.json']=(json.dumps(manifest,indent=2)+'\n').encode()
files['README.txt']=b'''Punisher Plasma v0.1.55 TEST
Grip position AND orientation use two fresh held054 node12 captures. Only
render nodes15..18 change; functional nodes0..14, muzzle, hierarchy, controller,
animation clips, accepted2x reload and all native safety remain unchanged.
This static placement is a TEST; hand contact across idle/ADS/reload UNVERIFIED.
Normal capacity/start/refill/max:15/1/1/1. Modifiers/boosters may increase counts.
LEFT choices use native function11, stock localized NORMAL and SHOTGUN labels
and existing stock bullet/shotgun icons. Redundant RIGHT Semi selector removed.
Native remembered selection and normal2/underbarrel8 routing unchanged.
Normal350/225 blast60RPM; pellets20 loaded60 loose and accepted tuning retained.
Offline source Lua execution/compilation and scoped byte checks PASS.
Fresh055 startup/loaded-state and gameplay NOTRUN. Final release stays gated.
User-reported actual One-Two mission-launch crash remains unverified.
Replace054 with055; never stack versions. Import/Purge/Deploy all Addon files,
including both CPU/GPU/STREAM sets, then restart and report launched.
Wait for fresh055 source_installed=true and Ready before testing.
Check grip idle/hipfire/ADS/reload and muzzle alignment; LEFT mode labels/icons
and switching; normal15 and spares/refill; independent pellet20/60 ammo.
Stop on source refusal/missing grip/crash; restart after replacement/removal.
Native retained storage is not hot-unload safe. User deploys/gameplays.
'''
for name in list(files):
 if name.startswith('Verification/') or name.startswith('Visual/'):files['Baseline054/'+name]=files.pop(name)
files['Visual/02cd7321cd8445f5-grip-placement.unit']=newunit
report={'status':'PASS','scope':'Offline scoped candidate, no gameplay proof',
 'baseline_sha256':sha(BASE.read_bytes()).upper(),'normal':{'capacity':15,'starting_spares':1,'refill_spares':1,'max_spares':1},
 'geometry':{'only_render_nodes':[15,16,17,18],'functional_nodes_0_to14_exact':True,
 'hierarchy_bones_controller_exact':True,'animation_edits':False,'measured_target':target.tolist(),
 'capture_target_matrix_difference':float(np.max(np.abs(targets[0]-targets[1]))),
 'old_target_position_error_m':float(np.linalg.norm(target[:3,3]-cm[12][:3,3])),
 'placements':placements,'unit_sha256':sha(newunit)},
 'left_hud':{'function':11,'right_function':0,'labels':['NORMAL','SHOTGUN'],'source_display_range':[160,192],
 'dispatch_modes_unchanged':[2,0,0,8],'native_audit':'left-hud-native-audit-v0155.json'},
 'retained_source_hashes':retained,'lua_execution':'PASS','lua_compile':'PASS',
 'native_thread_safety_unchanged':True,'tuning_reload_muzzle_protected_weapons_unchanged':True,
 'startup':'NOTRUN','loaded_state':'NOTRUN','gameplay':'NOTRUN','deployment':False,'publication':False}
for f in ['left-hud-native-audit-v0155.json','left-hud-icon-stock-locations.json','left-hud-localization-lookup.json']:
 files['Verification/'+f]=(H/f).read_bytes()
files['Verification/scoped-v0155.json']=(json.dumps(report,indent=2)+'\n').encode()
files['Verification/private-profile-fixture.lua']=fixture.encode()
files['Source/build_grip_ammo_hud_v0155.py']=Path(__file__).read_bytes()
with zipfile.ZipFile(DEST,'x',zipfile.ZIP_DEFLATED) as z:
 for name,b in files.items():z.writestr(name,b)
with zipfile.ZipFile(DEST) as z:
 assert z.testzip() is None and all(z.read(n)==b for n,b in files.items())
 assert json.loads(z.read('manifest.json'))['Guid']==guid and json.loads(z.read('manifest.json'))['Options']==options
for name,b in files.items():
 if name.startswith('Source/'):p=O/name;p.parent.mkdir(parents=True,exist_ok=True);p.write_bytes(b)
(O/'02cd7321cd8445f5-grip-placement.unit').write_bytes(newunit)
report.update(candidate=str(DEST),sha256=sha(DEST.read_bytes()).upper(),zip_integrity='PASS')
(O/'package-verification.json').write_text(json.dumps(report,indent=2)+'\n')
print(json.dumps({k:report[k] for k in ['status','candidate','sha256','normal','startup','gameplay']},indent=2))
