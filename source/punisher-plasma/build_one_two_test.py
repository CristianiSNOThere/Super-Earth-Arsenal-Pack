"""Version046 testable automatic native attachment candidate. NEVER deploys."""
from pathlib import Path
import struct,json,hashlib,zipfile,importlib.util,sys
from collections import Counter
import one_two_build_data as builddata
import build_test as baseline
base=Path(__file__).resolve().parent;root=base.parents[1]
sys.path.insert(0,str(root/'work/expanded-stat-editor'))
from lua_runtime import Lua51
def main():
 out=root/'outputs/Punisher-Plasma-One-Two-Attachment-Test-v0.1.46.zip';assert not out.exists(),'Never overwrite a versioned build'
 reports=['one-two-loadout-assets.json','one-two-source-publisher-verification.json','one-two-integration-verification.json','one-two-ownership-join-verification.json','one-two-ammo-flag-audit.json','tuning-v0126-verification.json','sweeper-reload-timing-audit.json']
 for n in reports:
  r=json.loads((base/n).read_text());assert r.get('status',r.get('result'))=='PASS',n
 verification=json.loads((base/'one-two-integration-verification.json').read_text())
 for n,digest in verification['source_sha256'].items():assert hashlib.sha256((base/n).read_bytes()).hexdigest()==digest,('Stale test',n)
 prior=json.loads((base/'tuning-v0126-verification.json').read_text())
 for n,digest in prior['source_hashes'].items():assert hashlib.sha256((base/n).read_bytes()).hexdigest()==digest,('Accepted baseline drift',n)
 helper=json.loads((base/'one-two-source-publisher-build.json').read_text())
 assert helper['source_sha256']==hashlib.sha256((base/'one_two_source_publish.c').read_bytes()).hexdigest()
 assert helper['derived_barrier_sha256']==hashlib.sha256((base/'private_delta_publish.c').read_bytes()).hexdigest()
 assert helper['protection_codegen_sha256']==hashlib.sha256((base/'one_two_protection_codegen.py').read_bytes()).hexdigest()
 assert helper['text_relocations']==helper['unwind_relocations']==helper['undefined_external_symbols']==0
 d=builddata.data()
 for path,digest in [(Path('D:/SteamLibrary/steamapps/common/Helldivers 2/bin/helldivers2.exe'),d['exe_hash']),(Path('D:/SteamLibrary/steamapps/common/Helldivers 2/data/game/game.dll'),d['game_hash'])]:
  assert hashlib.sha256(path.read_bytes()).hexdigest().upper()==digest,('Unsupported installed build',str(path))
 spec=importlib.util.spec_from_file_location('one_two_archive',root/'work/flag-mod/BingusSharedLoader-main/scripts/archive.py');archive=importlib.util.module_from_spec(spec);spec.loader.exec_module(archive)
 namehash=archive.resource_hash
 # Fresh read-only installed patch inventory: never silently override another
 # mod's packages/boot replacement. Ordinary Lua-only addons are unaffected.
 game=Path('D:/SteamLibrary/steamapps/common/Helldivers 2/data');conflicts=[];checked=[];recognized=[]
 priorzip=root/'outputs/Punisher-Plasma-One-Two-Attachment-Test-v0.1.45.zip'
 assert hashlib.sha256(priorzip.read_bytes()).hexdigest().upper()=='3B3D5B448693271B38067FFB49B065B645303B5B44C29E352F29E0326B410388'
 with zipfile.ZipFile(priorzip) as z:priorpayload=z.read('Addon/9ba626afa44a3aa3.patch_0')
 reader_spec=importlib.util.spec_from_file_location('one_two_reader',base/'visual-size/extract_particles.py');reader=importlib.util.module_from_spec(reader_spec);reader_spec.loader.exec_module(reader)
 for path in sorted(game.glob('*.patch_*')):
  if not path.name.rsplit('.patch_',1)[1].isdigit():continue
  h=reader.archive_read(path.name,0,12);assert h[:4]==b'\x11\0\0\xf0',('Unknown installed patch',path.name)
  nt,nf=struct.unpack_from('<II',h,4);assert nt<1000 and nf<500000
  table=reader.archive_read(path.name,72+32*nt,80*nf);checked.append(path.name)
  for i in range(nf):
   r=struct.unpack_from('<7Q6I',table,i*80)
   if r[0]==0x9ba626afa44a3aa3 and r[1]==namehash('package'):
    if path.read_bytes()==priorpayload:recognized.append(path.name)
    else:conflicts.append(path.name)
 assert not conflicts,('Installed boot-package conflict; cannot safely build this route',conflicts)
 assert len(recognized)<=1,'Duplicate deployed predecessor'
 (base/'one-two-installed-resource-audit.json').write_text(json.dumps(dict(status='PASS',checked_patches=checked,boot_overrides=conflicts,recognized_exact_v0145=recognized,scope='Read-only installed patch headers; whole predecessor archive byte equality'),indent=2)+'\n')
 stock=(base/'stock_boot-loadout.package').read_bytes();donor=(base/'one_two-loadout.package').read_bytes()
 assert hashlib.sha256(stock).hexdigest()=='b9161444248cb140337b33e177e74a037827dece44630ba7ab9b2dc5c3367d1c'
 assert stock==(base/'visual-size/stock-boot.package').read_bytes()
 assets=json.loads((base/'one-two-loadout-assets.json').read_text())
 assert hashlib.sha256(donor).hexdigest()==assets['packages']['one_two']['sha256']
 original={struct.unpack_from('<QQ',stock,o) for o in range(16,len(stock),16)}
 additions=[struct.unpack_from('<QQ',donor,o) for o in range(16,len(donor),16) if struct.unpack_from('<QQ',donor,o) not in original]
 assert len(additions)==len(set(additions))==70
 boot=bytearray(stock);struct.pack_into('<I',boot,8,4051+len(additions));boot+=b''.join(struct.pack('<QQ',*p) for p in additions)
 inverse=bytearray(boot[:len(stock)]);struct.pack_into('<I',inverse,8,4051);assert bytes(inverse)==stock
 assert all(n!=0x07e4ec4c10cedd76 for _,n in additions),'Failed visual candidate reintroduced'
 modules={'owned':'owned_profile.lua','registry':'registry_transaction.lua','runtime':'loyalist_runtime.lua','modes':'mode_profile.lua',
  'profile':'one_two_source_profile.lua','plan':'one_two_source_plan.lua','registration':'one_two_source_registration.lua','observe':'one_two_child_observer.lua','join':'one_two_ownership_join.lua'}
 windows=(root/'work/plas39-accelerator-rifle/windows.lua').read_text().replace('Plas39QuickShotMemoryInfoV1','PunisherPlasmaMemoryInfoTest1')
 abi=(base/'private_delta_registration.lua').read_text().split('return function(api,image,plan,helper,test_system)')[0]
 helperdata=dict(code=bytes.fromhex(helper['text_hex']),unwind=bytes.fromhex(helper['unwind_hex']),end=helper['function_end'])
 code="local function unhex(s)return(s:gsub('..',function(x)return string.char(tonumber(x,16))end))end\nlocal D="+baseline.literal(d)+'\nlocal helper='+baseline.literal(helperdata)+'\n'
 code+='do\n'+abi+'\nend\nlocal modules={}\n'
 for key,file in modules.items():code+='modules.'+key+'=(function()\n'+(base/file).read_text(encoding='utf-8-sig')+'\nend)()\n'
 for key,source in [('make_api',windows),('bridge',(base/'bridge.lua').read_text().replace('Plas39QuickShotMemoryInfoV1','PunisherPlasmaMemoryInfoTest1')),('prepare',(base/'prepare.lua').read_text()),('start',(base/'one_two_startup.lua').read_text())]:code+='local '+key+'=(function()\n'+source+'\nend)()\n'
 code+='start(make_api,bridge,prepare,D,modules,helper)\n';code=code.encode();Lua51().compile(code,'@punisher-one-two-v046.lua')
 assert b'test_system.invoke' in code # Optional testing seam only; real start supplies NO test backend.
 assert code.endswith(b'start(make_api,bridge,prepare,D,modules,helper)\n')
 entry='mods/codex/punisher_plasma_first_test';impl=entry+'_impl'
 entrycode=('-- HD2-Addon: '+entry+'\nreturn require("'+impl+'")\n').encode()
 resources=[(namehash('lua'),namehash(entry),struct.pack('<II',len(entrycode),2)+entrycode),(namehash('lua'),namehash(impl),struct.pack('<II',len(code),2)+code),(namehash('package'),0x9ba626afa44a3aa3,bytes(boot))]
 resources.sort();counts=Counter(t for t,_,_ in resources);start=(72+32*len(counts)+80*len(resources)+15)&~15
 blob=bytearray(start);entries=[]
 for i,(kind,name,data) in enumerate(resources):
  entries.append(struct.pack('<7Q6I',name,kind,len(blob),0,0,0,0,len(data),0,0,16,16,i));blob+=data;blob+=bytes(-len(blob)%16)
 table=struct.pack('<III20sQQ24s',0xf0000011,len(counts),len(resources),b'',len(blob),0,b'')+b''.join(struct.pack('<IIQIIII',0,0,t,n,0,16,16)for t,n in sorted(counts.items()))+b''.join(entries);blob[:len(table)]=table
 def check(payload):
  tc,rc=struct.unpack_from('<II',payload,4);assert (tc,rc)==(2,3)
  for i,(t,n,data) in enumerate(resources):
   r=struct.unpack_from('<7Q6I',payload,72+32*tc+80*i);assert r[:2]==(n,t) and payload[r[2]:r[2]+r[7]]==data
 check(blob)
 old=root/'outputs/Punisher-Plasma-Native-Child-Test-v0.1.38.zip'
 assert hashlib.sha256(old.read_bytes()).hexdigest().upper()=='BA7C8A375F749DF99BD9A9E19B6DA204B54EDC80266B8332D94B9F3A49612025'
 with zipfile.ZipFile(old) as z:manifest=json.loads(z.read('manifest.json'))
 manifest['Name']='SG-8P Punisher Plasma One-Two Attachment Test v0.1.46'
 manifest['Description']='Automatic native One-Two pellet attachment prototype:20 loaded capacity/60 loose spares. Start with another primary. Gameplay unverified.'
 readme='''SG-8P Punisher Plasma One-Two Attachment Test v0.1.46

TEST PROTOTYPE, NOT A FINISHED OR GAMEPLAY-VERIFIED RELEASE.
Requires supported Steam build25480438 and existing Bingus Shared Loader.
Same GUID and options replace the prior Punisher candidate. Keep old ZIPs.

SWEEPER RELOAD TIMING CANDIDATE
Copies stock SG-97 Sweeper reload ability2773 and its normal/fast animation
events into sole-owned One-Two child reload152. Sweeper and AR-11 untouched.
Preserves capacity20,60 loose spares,insertion1,chamber0, all accepted tuning,
and One-Two movement/manual flags,duration0(native default),deposit and voices.
Native default whole-ability duration130frames versus launcher242frames;
this DOES NOT prove first insertion or fire-unlock latency. No guessed speed
scale or manual ammo filling. User must test reload-one/fire/reload promptly.
Mesh remains VISIBLE in this timing candidate; meshless One-Two draft is
offline only and not packaged. Muzzle alignment and blank UI icon unresolved.
Same native helper/full thread barrier and readonly restore semantics.
Read-only ammo history now retains the most recent100 events with tick times;
250ms sampling cannot measure reload input time or exact animation timing.

MANUAL TEST
1. Before closing your existing game, equip another primary, such as AR-11.
   Do not start this candidate with Punisher or One-Two already equipped.
2. Import this ZIP as the replacement, use your usual Purge/Deploy, restart.
3. Wait on ship for PunisherOneTwoTest.log to say source_installed=true and
   Ready. Only then select Punisher Plasma. Wait before firing so initial
   loaded20/spares60 can be observed. Send the fresh log first.
4. If startup/child initialization passes, use the normal hold-R underbarrel
   selector to switch firing branch. Test empty pellet reload: fire immediately after the FIRST inserted
   round, then reload and fire one again. Compare preparation delay with045.
   A short video including reload input/animation/ammo is useful. Also test
   repeated pellet reloads at0,1,19 and20 loaded; interrupt reload,
   fire and reload again. Test low reserve, a normal shot,
   switching back, resupply, and check that the two ammo pools are independent.
   Normal remains single175/113 blast at120RPM,20 capacity/six spare magazines.
   Pellets:9,25/9 impact+25/9 blast each,AP3 all angles,100RPM,100/90MRAD,
   20 capacity and60 LOOSE spare rounds. Loading comes from native creation;
   the mod never forces current loaded rounds or repeatedly tops up inventory.
5. Compare AR-11 and Scorcher. Child mount/muzzle/HUD/reload/animation and
   drop/re-equip/mission lifecycle need gameplay verification.

DESIGN / LIMITS
Replaces Punisher's grip with the existing One-Two child. One-Two's launcher
is deliberately sacrificed. Stock unit, bones, state-machine, particle and
GPU bytes are retained; child geometry may be visible. Animation differences
are accepted, invisibility/muzzle alignment are NOT established.
Adds70 exact existing One-Two package dependency references to the stock boot
package, preserving all4051 original entries and other header bytes. No stock
visual assets are edited. Build-time installed audit found no competing boot
package override; do not select a conflict winner without inspection.

Installs eight solely-owned source records through a native thread transaction
before equipment creation. All old words, root/loader ledger/source pointers,
code, owned tuning and full factory-absence snapshots must pass under worker
suspension. Changed/unrecognized state refuses; exact readonly private source pages are temporarily writable and restored; definite busy may
retry boundedly. No native factory call or custom creation hook is installed.
The game creates/initializes/attaches/removes its normal child. Later observer
is read-only. Existing update callback return values are preserved.
Retained helper/source/tuning storage is not hot-unloaded or rolled back.
Restart after any refusal, replacement or removal. If already-target refusal
occurs, select another primary, close, then start fresh again.

Accepted flight,forces,burning,sway50%,pellet effects and tuning retained.
Child ProjectileWeapon is the WHOLE accepted pellet profile, including original
zeroing, speed, damage/AP addends, shakes, casing/muzzle/audio; child recoil/sway
match accepted Punisher. Donor grenade firing fields are not inherited.
Conditional normal350/225,60RPM,30loaded+30spare remains gated and is NOT applied.
AR-11/Scorcher/unrelated weapon records are outside the edit scope.
OFFLINE profile/planner/native worker/adapter/observer/archive/compile checks
PASS. Fresh046 startup/child20/60/reload timing/animation/gameplay NOTRUN.
Prior045 ammo/reload/refill successes do not prove046 behavior.
User handles all deployment and gameplay. No settings/publication/schedules.
'''
 addon='Addon/9ba626afa44a3aa3.patch_0'
 files={'manifest.json':(json.dumps(manifest,indent=2)+'\n').encode(),'README.txt':readme.encode(),'Source/runtime.lua':code,addon:bytes(blob),addon+'.stream':b'',addon+'.gpu_resources':b''}
 for f in set(modules.values())|{'prepare.lua','bridge.lua','one_two_startup.lua','one_two_source_publish.c','one_two_build_data.py','build_one_two_test.py','one_two_protection_codegen.py','build_one_two_source_publisher.py'}:files['Source/'+f]=(base/f).read_bytes()
 files['Source/delta-abi.lua']=abi.encode()
 files['Verification/sweeper-reload-audit.json']=(base/'sweeper-reload-audit.json').read_bytes()
 for n in reports+['one-two-source-publisher-build.json','one-two-installed-resource-audit.json']:files['Verification/'+n]=(base/n).read_bytes()
 with zipfile.ZipFile(out,'w',zipfile.ZIP_DEFLATED) as z:
  for n,v in files.items():z.writestr(n,v)
 with zipfile.ZipFile(out) as z:
  assert z.testzip() is None and all(z.read(n)==v for n,v in files.items());check(z.read(addon))
 with zipfile.ZipFile(old) as z:oldmanifest=json.loads(z.read('manifest.json'))
 assert manifest['Guid']==oldmanifest['Guid'] and manifest['Options']==oldmanifest['Options']
 result=dict(status='PASS',candidate=str(out),sha256=hashlib.sha256(out.read_bytes()).hexdigest().upper(),lua_compile='PASS',archive_roundtrip='PASS',zip_integrity='PASS',resources=3,
  boot_original_entries_preserved=4051,boot_existing_dependency_additions=70,stock_visual_asset_edits=0,installed_boot_conflicts=conflicts,reload_candidate="child-only Sweeper2773 normal/fast ability/events; insertion/fire-unlock timing unverified",menu_icon="UNRESOLVED",source_target_records=8,child_projectile_profile='whole accepted pellet profile',child_recoil_sway='accepted Punisher',
  accepted_baseline_preserved=True,guid_options_preserved=True,deployment=False,settings_changed=False,published=False,
  fresh_startup='NOTRUN',native_child_creation='NOTRUN',native20_60='NOTRUN',gameplay='NOTRUN')
 (base/'one-two-v0146-package-verification.json').write_text(json.dumps(result,indent=2)+'\n')
 (base/'assembled-one-two-v0146.lua').write_bytes(code)
 print(json.dumps(result,indent=2))
if __name__=='__main__':main()
