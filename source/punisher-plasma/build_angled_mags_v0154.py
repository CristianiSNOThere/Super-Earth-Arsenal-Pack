"""Immutable053 -> scoped angled rendering + normal15/2/2/2. Offline only."""
from pathlib import Path
from collections import Counter
import ast,hashlib,importlib.util,json,struct,sys,zipfile
H=Path(__file__).resolve().parent;ROOT=H.parents[1];O=H/'angled-v0154'
BASE=ROOT/'outputs/Punisher-Plasma-Grip-Tuning-Test-v0.1.53.zip'
DEST=ROOT/'outputs/Punisher-Plasma-Angled-Grip-Mags-Test-v0.1.54.zip'
assert not DEST.exists(),'Never overwrite a versioned ZIP'
sha=lambda b:hashlib.sha256(b).hexdigest()
assert sha(BASE.read_bytes()).upper()=='29FDEBB2FF6A7E9574D69883D81F0F2A5A4C2E1C94021B2B8798DA284B71C680'
with zipfile.ZipFile(BASE) as z:files={n:z.read(n) for n in z.namelist()};assert z.testzip() is None
before=dict(files);runtime=files['Source/runtime.lua'].decode()
changes={
 'Source/one_two_source_profile.lua':[("word(30)..word(1)..word(1)..word(1)) -- capacity/start/refill/max:30+30","word(15)..word(2)..word(2)..word(2)) -- capacity/start/refill/max:15 loaded + two spare15 magazines")],
 'Source/one_two_startup.lua':[('normal=350/225 blast;60RPM;30 capacity;one spare30 magazine','normal=350/225 blast;60RPM;15 capacity;two spare15 magazines;refill two')],
}
for name,pairs in changes.items():
 old=files[name].decode().replace('\r\n','\n');new=old
 for a,b in pairs:assert new.count(a)==1,(name,a);new=new.replace(a,b)
 assert runtime.count(old)==1;runtime=runtime.replace(old,new);files[name]=new.encode()
assert runtime.count('0.1.53-one-two-test')==1
runtime=runtime.replace('0.1.53-one-two-test','0.1.54-one-two-test');files['Source/runtime.lua']=runtime.encode()
files['Source/one_two_build_data.py']=files['Source/one_two_build_data.py'].replace(b'0.1.53-one-two-test',b'0.1.54-one-two-test')
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
  assert(u(s.after,136)==15 and u(s.after,140)==2 and u(s.after,144)==2 and u(s.after,148)==2)
  assert(r.after:sub(1,136)==s.after:sub(1,136) and r.after:sub(153)==s.after:sub(153))
 else assert(r.after==s.after,'Unrelated source profile changed: '..r.role)end
end
'''
lua.run(fixture.encode(),'@v0154-private-profile-fixture');(O/'private-profile-fixture.lua').write_text(fixture)
tree=ast.parse((H/'build_hidden_aligned_v0150.py').read_text());fn=next(n for n in tree.body if isinstance(n,ast.FunctionDef) and n.name=='archive')
ns={'struct':struct,'Counter':Counter};exec(compile(ast.Module(body=[fn],type_ignores=[]),'serializer','exec'),ns)
main='Addon/9ba626afa44a3aa3.patch_0';blob=files[main];tc,fc=struct.unpack_from('<II',blob,4);resources=[];replaced=0
for i in range(fc):
 r=struct.unpack_from('<7Q6I',blob,72+tc*32+i*80);p=blob[r[2]:r[2]+r[7]]
 if p[8:]==before['Source/runtime.lua']:p=struct.pack('<II',len(files['Source/runtime.lua']),2)+files['Source/runtime.lua'];replaced+=1
 resources.append((r[0],r[1],p,r))
assert replaced==1;files[main]=ns['archive'](resources)
# Preserve complete stock donor archive backing buffers. Translate CPU addresses
# instead of guessing the donor's negative MainBufferOffset delta.
p=H/'visual-size/extract_particles.py';spec=importlib.util.spec_from_file_location('read_archive',p);a=importlib.util.module_from_spec(spec);spec.loader.exec_module(a)
archive='8241a28246a6466e';header=a.archive_read(archive,0,72);nt,nf=struct.unpack_from('<II',header,4)
cpu_len=a.archives[archive][0];gpu_len=a.archives[archive+'.gpu_resources'][0]
cpu=a.archive_read(archive,0,cpu_len);gpu=a.archive_read(archive+'.gpu_resources',0,gpu_len)
rows=[struct.unpack_from('<7Q6I',cpu,72+nt*32+i*80) for i in range(nf)]
stream_len=max(r[3]+r[8] for r in rows);stream=a.archive_read(archive+'.stream',0,stream_len) if stream_len else b''
unit=(O/'02cd7321cd8445f5-angled.unit').read_bytes();donor=(H/'unused-grip-assets/411c4fd07740a7dd.unit').read_bytes()
dr=next(r for r in rows if r[0]==0x411c4fd07740a7dd);assert cpu[dr[2]:dr[2]+dr[7]]==donor
assert gpu[dr[4]:dr[4]+dr[9]]==(H/'unused-grip-assets/411c4fd07740a7dd.gpu').read_bytes()
mat=struct.unpack_from('<I',donor,112)[0];mc=struct.unpack_from('<I',donor,mat)[0]
materials=struct.unpack_from('<'+str(mc)+'Q',donor,mat+4+mc*4)
keys=struct.unpack_from('<'+str(mc)+'I',donor,mat+4);material_map=dict(zip(keys,materials))
mesh=struct.unpack_from('<I',donor,100)[0];used=set()
for i in range(struct.unpack_from('<I',donor,mesh)[0]):
 mh=mesh+struct.unpack_from('<I',donor,mesh+4+i*4)[0];n,off=struct.unpack_from('<II',donor,mh+104)
 used.update(material_map[k] for k in struct.unpack_from('<'+str(n)+'I',donor,mh+off))
stock_child=(H/'one-two-visual/02cd7321cd8445f5-stock.unit').read_bytes()
sm=struct.unpack_from('<I',stock_child,112)[0];sn=struct.unpack_from('<I',stock_child,sm)[0]
stock_materials=set(struct.unpack_from('<'+str(sn)+'Q',stock_child,sm+4+sn*4))
# The shared default75F87AD2AE08E9C2 is already an unchanged OneTwo dependency.
assert used<={r[0] for r in rows if r[1]==0xeac0b497876adedf}|stock_materials,[hex(x) for x in used]
visual_checks=[]
for basename in ['49f1972458f7ccec','e16e0aa7740716a2']:
 name='Addon/'+basename+'.patch_0';old=before[name];ot,of=struct.unpack_from('<II',old,4);assert of==1
 target=list(struct.unpack_from('<7Q6I',old,72+ot*32));assert target[0]==0x02cd7321cd8445f5
 counts=Counter(r[1] for r in rows);counts[target[1]]+=1
 start=(72+len(counts)*32+(len(rows)+1)*80+63)&~63
 new=bytearray(start);new+=unit;new+=bytes(-len(new)%64);donor_base=len(new);new+=cpu
 target[5]=start+target[5]-target[2];target[2]=start;target[7]=len(unit)
 target[3]=0;target[8]=0;target[4]=dr[4];target[6]=dr[6];target[9]=dr[9];target[12]=len(rows)
 translated=[]
 for r in rows:
  r=list(r);r[2]+=donor_base
  if r[5]:r[5]+=donor_base
  translated.append(r)
 types=[]
 for kind,count in sorted(counts.items()):
  t=next(list(struct.unpack_from('<IIQIIII',cpu,72+i*32)) for i in range(nt) if struct.unpack_from('<Q',cpu,72+i*32+8)[0]==kind);t[3]=count;types.append(struct.pack('<IIQIIII',*t))
 prefix=struct.pack('<III20sQQ24s',0xf0000011,len(counts),len(rows)+1,b'',len(new),len(gpu),b'')+b''.join(types)+b''.join(struct.pack('<7Q6I',*r) for r in translated+[target])
 new[:len(prefix)]=prefix;new=bytes(new)
 for original,r in zip(rows,translated):
  assert new[r[2]:r[2]+r[7]]==cpu[original[2]:original[2]+original[7]]
  assert (r[5]-r[2]==original[5]-original[2]) if original[5] else r[5]==0
 assert new[target[2]:target[2]+target[7]]==unit
 assert target[5]-target[2]==struct.unpack_from('<7Q6I',old,72+ot*32)[5]-struct.unpack_from('<7Q6I',old,72+ot*32)[2]
 files[name]=new;files[name+'.gpu_resources']=gpu
 if stream:files[name+'.stream']=stream
 visual_checks.append(dict(archive=basename,resources=len(rows)+1,stock_dependency_bytes_identical=True,target_cpu_buffer_delta=target[5]-target[2],target_gpu_buffer_delta=target[6]-target[4],gpu_sha256=sha(gpu),stream_sha256=sha(stream)))
retained={}
for name,b in before.items():
 if name.startswith('Source/') and name not in {*changes,'Source/runtime.lua','Source/one_two_build_data.py'}:assert files[name]==b;retained[name]=sha(b)
 # All nonvisual addon resources except embedded runtime remain exact.
 if name.startswith('Addon/') and not any(name.startswith('Addon/'+x) for x in ['49f1972458f7ccec','e16e0aa7740716a2','9ba626afa44a3aa3']):assert files[name]==b
assert files['Source/owned_profile.lua']==before['Source/owned_profile.lua']
for path,digest in [('D:/SteamLibrary/steamapps/common/Helldivers 2/bin/helldivers2.exe','F5FEE03DCFDB2E553A4752C283590950AC13316B376D8196AA556FF0400D5F06'),('D:/SteamLibrary/steamapps/common/Helldivers 2/data/game/game.dll','2E2C3B7C2500646DADD5F2B4C6E0504DBB7E7896139F64CDDC0D1813C718F51E')]:assert sha(Path(path).read_bytes()).upper()==digest
manifest=json.loads(files['manifest.json']);guid=manifest['Guid'];options=manifest['Options']
manifest['Name']='SG-8P Punisher Plasma Angled Grip and Mags Test v0.1.54'
manifest['Description']='Angled foregrip rendering on retained One-Two skeleton/function. Normal15 rounds plus two spare15 magazines; refill two. Gameplay verification pending.'
files['manifest.json']=(json.dumps(manifest,indent=2)+'\n').encode()
files['README.txt']=b'''Punisher Plasma v0.1.54 - angled grip and normal magazines TEST
Normal:15 loaded; starting/refill/max two spare15-round magazines.
Game ammo modifiers/boosters can increase effective supply; base configuration2/2.
Normal350/225 blast,60RPM; pellet20 loaded60 loose, accepted2x reload retained.
Visible angled-grip mesh replaces hidden One-Two rendering only. Functional
19-joint hierarchy, IK12, muzzle13, bones/controller and weapon behavior retained.
No animation clips edited. Hand fit/material rendering remain UNVERIFIED.
Offline packaged Lua profile execution/compilation and archive byte checks PASS.
Fresh startup, loaded geometry/ammo and gameplay NOTRUN. LEFT mode-menu issue
remains unresolved; this candidate does not change menu dispatch.
Known user-reported incompatibility: equipping the actual One-Two weapon with
this mod causes a crash at mission launch. Not independently reproduced.
USER DEPLOYS all Addon files including both CPU/GPU/STREAM archive sets.
Replace053; never stack versions. Use existing import/Purge/Deploy workflow,
restart game and report launched. Agent verifies fresh startup before firing.
User checks hand fit idle/hipfire/ADS/reload, preserved pellet alignment,
normal15 loaded and spare counts/resupply, independent pellet20/60 ammo.
Stop on source refusal/pink/missing grip/crash. Restart after replacement,
refusal or removal. Native hooks/storage are not hot-unload safe.
User handles deployment/gameplay. No agent settings/publication/schedules.
'''
for name in list(files):
 if name.startswith('Verification/'):files['Baseline053/'+name]=files.pop(name)
for name in list(files):
 if name.startswith('Visual/'):files['Baseline053/'+name]=files.pop(name)
files['Visual/02cd7321cd8445f5-angled.unit']=unit
report=dict(status='PASS',scope='Offline only',normal=dict(capacity=15,starting_spares=2,refill_spares=2,max_spares=2),lua_execution='PASS',lua_compile='PASS',visual_archives=visual_checks,visual=json.loads((O/'visual-draft-audit.json').read_text()),retained_source_hashes=retained,native_thread_safety_unchanged=True,normal_and_pellet_tuning_unchanged=True,startup='NOTRUN',loaded_resources='NOTRUN',gameplay='NOTRUN',deployment=False,game_access=False,menu='Unresolved; unchanged',one_two_crash='User-reported mission-launch crash; not independently reproduced')
files['Verification/scoped-v0154.json']=(json.dumps(report,indent=2)+'\n').encode();files['Verification/private-profile-fixture.lua']=fixture.encode()
files['Source/build_angled_mags_v0154.py']=Path(__file__).read_bytes();files['Source/prepare_angled_visual_v0154.py']=(H/'prepare_angled_visual_v0154.py').read_bytes()
with zipfile.ZipFile(DEST,'x',zipfile.ZIP_DEFLATED) as z:
 for name,b in files.items():z.writestr(name,b)
with zipfile.ZipFile(DEST) as z:
 assert z.testzip() is None and all(z.read(n)==b for n,b in files.items())
 assert json.loads(z.read('manifest.json'))['Guid']==guid and json.loads(z.read('manifest.json'))['Options']==options
for name,b in files.items():
 if name.startswith('Source/'):p=O/name;p.parent.mkdir(parents=True,exist_ok=True);p.write_bytes(b)
report.update(candidate=str(DEST),sha256=sha(DEST.read_bytes()).upper(),zip_integrity='PASS');(O/'package-verification.json').write_text(json.dumps(report,indent=2)+'\n')
print(json.dumps({k:report[k] for k in ['status','candidate','sha256','normal','startup','gameplay']},indent=2))
