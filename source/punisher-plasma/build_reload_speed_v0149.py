"""Build from immutable046; restore045 reload and set coupled native speed2x.

No deployment, native hook, settings change, or visual/shot-alignment edit.
"""
from pathlib import Path
import hashlib,importlib.util,json,struct,sys,zipfile
from collections import Counter
import native_audit as n
import build_test as b
HERE=Path(__file__).resolve().parent;ROOT=HERE.parents[1]
sys.path.insert(0,str(ROOT/'work/expanded-stat-editor'))
from lua_runtime import Lua51
OUTPUT=ROOT/'outputs/Punisher-Plasma-One-Two-Attachment-Test-v0.1.49.zip'
assert not OUTPUT.exists(),'Never overwrite a versioned package'
baseline=ROOT/'outputs/Punisher-Plasma-One-Two-Attachment-Test-v0.1.46.zip'
working=ROOT/'outputs/Punisher-Plasma-One-Two-Attachment-Test-v0.1.45.zip'
assert hashlib.sha256(baseline.read_bytes()).hexdigest().upper()=='D4AB87A58E2A5DE1C161898FAB7B2F7669785C1705B9CA466AFA14E3295E1354'
assert hashlib.sha256(working.read_bytes()).hexdigest()=='3b3d5b448693271b38067ffb49b065b645303b5b44c29e352f29e0326b410388'
with zipfile.ZipFile(baseline) as z:files={name:z.read(name) for name in z.namelist()}
def resolved(source):
 ns={'__file__':str(HERE/'one_two_build_data.py'),'__name__':'immutable_data'}
 exec(compile(source,'immutable-packaged-data','exec'),ns);return ns['data']()
old=resolved(files['Source/one_two_build_data.py'])
with zipfile.ZipFile(working) as z:
 original_template=resolved(z.read('Source/one_two_build_data.py'))['child_reload_template']
assert struct.unpack_from('<I',original_template,4)[0]==2774
new=dict(old);new['version']='0.1.49-one-two-test';new['child_reload_template']=original_template
assert {k for k in old if old[k]!=new[k]}=={'version','child_reload_template'}
duration=121/60 # native2774 whole242ticks /60 /2; multiplies both timeline/body.
old_profile=files['Source/one_two_source_profile.lua'].decode()
needle='s=change(s,4,reload_template:sub(5,56))'
assert old_profile.count(needle)==1
profile=old_profile.replace(needle,needle+'\n   s=change(s,56,float(121/60)) -- coupled native animation/timeline speed2x')
profile=profile.replace('stock Sweeper ability','known working multi-round underbarrel ability')
guards=[]
for addr,mnemonic,operand in [
 (0x774edb,'movss','xmm0, dword ptr [r14 + 0x38]'),(0x774eef,'call','0x1166ef0'),
 (0x774f06,'divss','xmm0, dword ptr [r14 + 0x38]'),(0x774f0c,'mulss','xmm0, xmm6'),
 (0x774f49,'movss','dword ptr [rsp + 0x20], xmm6'),(0x774f4f,'call','0x7caf40'),
 (0x7cb0f7,'movss','dword ptr [rdi + rbp + 0xc], xmm6'),
 (0x7c8956,'mulss','xmm0, dword ptr [rbx + rdi + 0xc]'),
 (0x1168f3c,'movss','xmm0, dword ptr [rdx + rax + 0xc]'),
 (0x11c2e2f,'call','0x1168eb0'),(0x11c2f87,'movaps','xmm3, xmm7'),
 (0x11c2f9a,'call','qword ptr [r8 + 0x378]')]:
 i=next(n.md.disasm(n.text[addr-n.base:addr-n.base+16],addr))
 assert (i.mnemonic,i.op_str)==(mnemonic,operand),(hex(addr),i.op_str)
 guards.append({'rva':hex(addr),'bytes':i.bytes.hex(),'instruction':mnemonic+' '+operand})
assert struct.unpack_from('<f',n.rd,0x23c7740-n.rb)[0]==60
case=n.text[0x116772c-n.base+2774-1];target=struct.unpack_from('<I',n.text,0x11673f0-n.base+case*4)[0]
seq=list(n.md.disasm(n.text[target-n.base:target-n.base+6],target))
assert [(i.mnemonic,i.op_str) for i in seq]==[('mov','eax, 0xf2'),('ret','')]
# Execute real immutable shipped profile/modes; only reload row may differ.
script="local ffi=require('ffi')\nlocal function unhex(s)return(s:gsub('..',function(x)return string.char(tonumber(x,16))end))end\nlocal A="+b.literal(old)+'\nlocal B='+b.literal(new)+'\n'
for name,source in [('before',old_profile),('after',profile),('modes',files['Source/mode_profile.lua'].decode())]:script+='local '+name+'=(function()\n'+source+'\nend)()\n'
script+=r'''
local stock={weapon=A.components.weapon.bytes,projectile=A.components.projectile.bytes,magazine=A.components.magazine.bytes}
local x=before(A.source_rows,modes,stock,A.child_reload_template)
local y=after(B.source_rows,modes,stock,B.child_reload_template)
local restored=before(B.source_rows,modes,stock,B.child_reload_template)
assert(#x==8 and #y==8)
for i,r in ipairs(x)do
 local s=y[i];assert(r.before==s.before and r.owner==s.owner and r.index==s.index and r.stride==s.stride)
 if r.role=='child_reload'then
  assert(s.after:sub(1,4)==r.after:sub(1,4) and s.after:sub(61)==r.after:sub(61))
  assert(s.after:sub(5,56)==B.child_reload_template:sub(5,56))
  assert(s.after:sub(1,56)==restored[i].after:sub(1,56) and s.after:sub(61)==restored[i].after:sub(61))
  local f=ffi.new('float[1]');ffi.copy(f,s.after:sub(57,60),4);assert(math.abs(f[0]-121/60)<0.000001)
 else assert(s.after==r.after,'Unrelated profile drift: '..r.role)end
end
'''
Lua51().run(script.encode(),'@v0149-reload-preservation.lua')
runtime=files['Source/runtime.lua'].decode()
assert runtime.count('local D='+b.literal(old))==1 and runtime.count(old_profile)==1
runtime=runtime.replace('local D='+b.literal(old),'local D='+b.literal(new)).replace(old_profile,profile)
Lua51().compile(runtime.encode(),'@punisher-one-two-v049.lua')
# Native helper, planner, registration, observer and tuning remain exact046.
safety=['one_two_source_publish.c','one_two_source_plan.lua','one_two_source_registration.lua','one_two_protection_codegen.py','build_one_two_source_publisher.py','one_two_startup.lua','mode_profile.lua','one_two_ownership_join.lua','one_two_child_observer.lua']
retained={f:hashlib.sha256(files['Source/'+f]).hexdigest() for f in safety}
helper=json.loads(files['Verification/one-two-source-publisher-build.json'])
assert helper['source_sha256']==retained['one_two_source_publish.c']
assert helper['text_relocations']==helper['unwind_relocations']==helper['undefined_external_symbols']==0
for path,digest in [(Path('D:/SteamLibrary/steamapps/common/Helldivers 2/bin/helldivers2.exe'),new['exe_hash']),(Path('D:/SteamLibrary/steamapps/common/Helldivers 2/data/game/game.dll'),new['game_hash'])]:
 assert hashlib.sha256(path.read_bytes()).hexdigest().upper()==digest,'Unsupported installed build'
addon='Addon/9ba626afa44a3aa3.patch_0';raw=files[addon];nt,nf=struct.unpack_from('<II',raw,4);assert (nt,nf)==(2,3)
resources=[];changed=0
for j in range(nf):
 row=struct.unpack_from('<7Q6I',raw,72+nt*32+j*80);payload=raw[row[2]:row[2]+row[7]]
 if payload[8:]==files['Source/runtime.lua']:
  payload=struct.pack('<II',len(runtime.encode()),2)+runtime.encode();changed+=1
 resources.append((row[1],row[0],payload))
assert changed==1
counts=Counter(t for t,_,_ in resources);start=(72+32*len(counts)+80*len(resources)+15)&~15
blob=bytearray(start);entries=[]
for j,(kind,name,payload) in enumerate(resources):
 entries.append(struct.pack('<7Q6I',name,kind,len(blob),0,0,0,0,len(payload),0,0,16,16,j));blob+=payload;blob+=bytes(-len(blob)%16)
header=struct.pack('<III20sQQ24s',0xf0000011,len(counts),len(resources),b'',len(blob),0,b'')+b''.join(struct.pack('<IIQIIII',0,0,t,count,0,16,16) for t,count in sorted(counts.items()))+b''.join(entries)
blob[:len(header)]=header
manifest=json.loads(files['manifest.json']);manifest['Name']='SG-8P Punisher Plasma One-Two Attachment Test v0.1.49'
manifest['Description']='Original working multi-round underbarrel reload restored, coupled native reload speed2x. Gameplay unverified.'
report={'status':'PASS','scope':'Immutable046 source/runtime/archive preservation and native coupled-speed dataflow',
 'baseline_sha256':hashlib.sha256(baseline.read_bytes()).hexdigest(),'reload_template_from':'immutable045 known working2774 normal/fast sequence',
 'source_records':8,'only_changed_profile':'child_reload','other_seven_profiles_identical':True,'parent_IK_preset_identical046':True,
 'duration_seconds':duration,'nominal_speed_multiplier':2,'nominal_first_insertion_seconds':0.75,'nominal_repeat_seconds':1/6,
 'timing_limitation':'Native ability modifiers and actual instantiated record selection/runtime latency still require fresh native/gameplay verification',
 'native_instruction_guards':guards,'native_safety_source_hashes':retained,'no_new_hooks_or_DLL':True,
 'lua_profile_execution':'PASS','lua_compile':'PASS','fresh_startup':'NOTRUN','native20_60':'NOTRUN','gameplay':'NOTRUN',
 'hiding':'NOT IMPLEMENTED','shot_alignment':'NOT IMPLEMENTED','final_tuning':'GATED','deployment':False,'settings_changed':False,'published':False}
files[addon]=bytes(blob);files['Source/runtime.lua']=runtime.encode();files['Source/one_two_source_profile.lua']=profile.encode()
datapy=files['Source/one_two_build_data.py'].decode().replace("d['child_reload_template']=reload","d['child_reload_template']=bytes.fromhex('"+original_template.hex()+"')").replace('0.1.46-one-two-test','0.1.49-one-two-test')
assert resolved(datapy)==new
files['Source/one_two_build_data.py']=datapy.encode()
# Historical verifier outputs are retained with explicit baseline names.
for name in list(files):
 if name.startswith('Verification/'):files['Baseline046/'+name]=files.pop(name)
files['Verification/reload-speed-preservation.json']=(json.dumps(report,indent=2)+'\n').encode()
files['manifest.json']=(json.dumps(manifest,indent=2)+'\n').encode()
files['README.txt']=b'''Punisher Plasma v0.1.49 - original multi-round reload, speed2x
Built from immutable046; reload ability/normal-fast event sequence restored
from known working045. Parent preset and IK2 exactly046. 20loaded/60loose
spares and all accepted tuning unchanged. No Sweeper animation, new hook orDLL.
Native duration override scales timeline and body animation together.
Nominal first insertion0.75s/repeat0.1667s; actual gameplay timing UNVERIFIED.
Fresh startup/native20/60/one-R continuous reload/gameplay NOTRUN.
Attachment hiding and shot alignment are subsequent separate changes.
Final conditional tuning remains gated. AR11/Scorcher/unrelated weapons retained.

User deploys. Select an unrelated primary before closing the game; replace
the previous Punisher test with this ZIP using your existing import/PurgeDeploy
workflow, then restart. Do not stack versions. Wait for fresh source Ready
and child20/60 verification before testing reload. Check original motion,
one-R continuous loading, firing interruption and ammunition independence.
Retained allocations are not hot-unloaded. Restart after refusal/replacement.
Baseline046/Verification contains HISTORICAL046 checks, not fresh049 evidence.
No settings changes, publication or schedules.
'''
files['Source/build_reload_speed_v0149.py']=Path(__file__).read_bytes()
folder=HERE/'reload-speed-v0149';folder.mkdir(exist_ok=False)
for name,value in files.items():
 if name.startswith('Source/'):
  path=folder/name[7:];path.parent.mkdir(parents=True,exist_ok=True);path.write_bytes(value)
with zipfile.ZipFile(OUTPUT,'x',zipfile.ZIP_DEFLATED) as z:
 for name,value in files.items():z.writestr(name,value)
with zipfile.ZipFile(OUTPUT) as z:
 assert z.testzip() is None and all(z.read(name)==value for name,value in files.items())
 parsed=z.read(addon)
 for j,(kind,name,payload) in enumerate(resources):
  row=struct.unpack_from('<7Q6I',parsed,72+nt*32+j*80);assert row[:2]==(name,kind) and parsed[row[2]:row[2]+row[7]]==payload
report.update(candidate=str(OUTPUT),sha256=hashlib.sha256(OUTPUT.read_bytes()).hexdigest().upper(),zip_integrity='PASS',archive_roundtrip='PASS')
(HERE/'one-two-v0149-package-verification.json').write_text(json.dumps(report,indent=2)+'\n')
print(json.dumps({k:report[k] for k in ['status','candidate','sha256','duration_seconds','nominal_speed_multiplier','fresh_startup','gameplay']},indent=2))
