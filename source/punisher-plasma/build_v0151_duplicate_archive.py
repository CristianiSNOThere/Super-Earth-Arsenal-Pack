"""Dual-archive coverage diagnostic from immutable050; no deployment or game calls."""
from pathlib import Path
from collections import Counter
import ast, hashlib, importlib.util, json, struct, sys, zipfile

HERE=Path(__file__).resolve().parent;ROOT=HERE.parents[1]
BASE=ROOT/'outputs/Punisher-Plasma-One-Two-Hidden-Aligned-Test-v0.1.50.zip'
DEST=ROOT/'outputs/Punisher-Plasma-One-Two-Dual-Archive-Test-v0.1.51.zip'
OUT=HERE/'dual-archive-v0151'
assert not DEST.exists() and not OUT.exists(), 'Never overwrite versioned artifacts'
sha=lambda b:hashlib.sha256(b).hexdigest()
assert sha(BASE.read_bytes()).upper()=='3B3E5085138377000EA060665801640206039F7CC78636FF2E4181139A10653C'
audit=json.loads((HERE/'v0150-resource-selection-audit.json').read_text())
assert audit['offline']=='PASS' and not audit['pellet_alignment']['candidate_correction_active']
with zipfile.ZipFile(BASE) as z:files={n:z.read(n) for n in z.namelist()}
before=dict(files)
old,new=b'0.1.50-one-two-test',b'0.1.51-one-two-test'
for name in ['Source/runtime.lua','Source/one_two_build_data.py']:
    assert files[name].count(old)==1
    files[name]=files[name].replace(old,new)
    assert files[name].replace(new,old)==before[name]
sys.path.insert(0,str(ROOT/'work/expanded-stat-editor'))
from lua_runtime import Lua51
Lua51().compile(files['Source/runtime.lua'],'@punisher-dual-archive-v0151.lua')
for path,expected in [(Path('D:/SteamLibrary/steamapps/common/Helldivers 2/bin/helldivers2.exe'),'F5FEE03DCFDB2E553A4752C283590950AC13316B376D8196AA556FF0400D5F06'),(Path('D:/SteamLibrary/steamapps/common/Helldivers 2/data/game/game.dll'),'2E2C3B7C2500646DADD5F2B4C6E0504DBB7E7896139F64CDDC0D1813C718F51E')]:
    assert sha(path.read_bytes()).upper()==expected, 'Unsupported game build'
# Reuse only the reviewed pure archive serializer, never execute the050 builder.
tree=ast.parse((HERE/'build_hidden_aligned_v0150.py').read_text())
function=next(x for x in tree.body if isinstance(x,ast.FunctionDef) and x.name=='archive')
namespace={'Counter':Counter,'struct':struct}
exec(compile(ast.Module(body=[function],type_ignores=[]),'reviewed050-archive-serializer','exec'),namespace)
archive=namespace['archive']
main='Addon/9ba626afa44a3aa3.patch_0';blob=files[main]
nt,nf=struct.unpack_from('<II',blob,4);assert (nt,nf)==(2,3)
resources=[];changed=0;retained_payloads=[]
for i in range(nf):
    row=struct.unpack_from('<7Q6I',blob,72+nt*32+i*80)
    payload=blob[row[2]:row[2]+row[7]]
    if payload[8:]==before['Source/runtime.lua']:
        payload=struct.pack('<II',len(files['Source/runtime.lua']),2)+files['Source/runtime.lua'];changed+=1
    else:retained_payloads.append(dict(name=f'{row[0]:016X}',type=f'{row[1]:016X}',sha256=sha(payload)))
    resources.append((row[0],row[1],payload,row))
assert changed==1
files[main]=archive(resources)

p=HERE/'visual-size/extract_particles.py';sp=importlib.util.spec_from_file_location('stock_reader',p)
a=importlib.util.module_from_spec(sp);sp.loader.exec_module(a)
target=(0x02cd7321cd8445f5,0xe0a48d0be9a7453f)
unit=files['Visual/02cd7321cd8445f5-hidden-aligned.unit']
assert sha(unit)=='8626c0ddd2ce6877063155f43ce191e67a56eac8fc1e80b2729d650ef9a22b21'
source_archive='e16e0aa7740716a2'
h=a.archive_read(source_archive,0,72);tc,fc=struct.unpack_from('<II',h,4)
table=a.archive_read(source_archive,72+tc*32,fc*80)
rows=[struct.unpack_from('<7Q6I',table,i*80) for i in range(fc)]
matches=[r for r in rows if r[:2]==target];assert len(matches)==1
r=matches[0]
assert r[7:10]==(6352,0,558080) and r[5]-r[2]==224 and r[6]-r[4]==640
stock=a.archive_read(source_archive,r[2],r[7]);gpu=a.archive_read(source_archive+'.gpu_resources',r[4],r[9])
assert sha(stock)=='66e64d997d8863d51bf47786409a47c5200bee8e34b3b8ec4eaf0b578740524b'
assert gpu==files['Addon/49f1972458f7ccec.patch_0.gpu_resources']
type_rows={}
for i in range(tc):
    tr=struct.unpack('<IIQIIII',a.archive_read(source_archive,72+i*32,32));type_rows[tr[2]]=tr
# Accept only installed immutable050 visual predecessor; unknown conflicting rows refuse.
installed=[]
for path in a.GAME.glob('*.patch_*'):
    if path.suffix in ['.gpu_resources','.stream']:continue
    b=path.read_bytes();pt,pf=struct.unpack_from('<II',b,4)
    assert b[:4]==bytes.fromhex('110000f0') and pt<1000 and pf<500000
    for i in range(pf):
        row=struct.unpack_from('<7Q6I',b,72+pt*32+i*80)
        if row[:2]==target:
            assert path.name=='49f1972458f7ccec.patch_0' and b==files['Addon/49f1972458f7ccec.patch_0']
            installed.append(path.name)
second='Addon/'+source_archive+'.patch_0';assert second not in files
files[second]=archive([(r[0],r[1],unit,r)],type_rows,gpu)
files[second+'.gpu_resources']=gpu
# The first visual archive and GPU companion remain byte-identical050.
assert all(files[n]==before[n] for n in before if n.startswith('Addon/49f'))
retained={}
for name,payload in before.items():
    if name.startswith('Source/') and name not in ['Source/runtime.lua','Source/one_two_build_data.py']:
        assert files[name]==payload;retained[name]=sha(payload)
manifest=json.loads(files['manifest.json'])
assert manifest['Options'][0]['Include']==['Addon']
manifest['Name']='SG-8P Punisher Plasma Dual Archive Diagnostic v0.1.51'
manifest['Description']='Same050 hidden/aligned unit candidate in both known stock archives. Accepted reload2x and tuning retained; loaded bytes and gameplay require verification.'
files['manifest.json']=(json.dumps(manifest,indent=2)+'\n').encode()
files['README.txt']=b'''Punisher Plasma v0.1.51 - dual archive coverage DIAGNOSTIC
050 installed visual files were exact, but attached child loaded STOCK geometry
and muzzle data. Same stock resource exists in TWO archives. This diagnostic
retains050 unit candidate and adds coverage for e16e0aa7740716a2, preserving
its own main/GPU buffer deltas224/640. Original49f patch remains exact050.
No new hide method. Zero counts have not been tested on a loaded candidate.
Native publication/safety/accepted2x reload/tuning remain unchanged049/050.
Only deliberately sacrificed One-Two child unit resource is overridden.
AR11/Scorcher/unrelated source and native safety code unchanged.
Offline package/math/preservation PASS; fresh051 startup/loaded bytes/rendering/
animated muzzle and actual hipfire/ADS pellet trajectory NOTRUN.
Final tuning remains gated. Baseline050 evidence is historical.

USER DEPLOYS: select unrelated primary before closing. Replace050 with051 via
existing import/Purge/Deploy workflow; never stack Punisher versions. Deploy
all Addon files, including BOTH visual patch files and BOTH GPU companions.
Restart, then tell the agent launched. Agent verifies fresh051 source/20/60 AND
attached child candidate LOD/mesh/muzzle bytes BEFORE interpreting visibility.
Then user checks no pink/visible attachment, normal shot unchanged, pellet
origin/aim in hipfire and ADS, accepted2x reload/interruption retained.
Stop on startup/resource refusal or pink placeholder.049 recovery retained.
Restart after replacement/refusal/removal; no hot unloading native storage.
No agent deployment/game writes/calls/input/settings/publication/schedules.
'''
for name in list(files):
    if name.startswith('Verification/'):files['Baseline050/'+name]=files.pop(name)
report=dict(status='PASS',scope='Offline dual-archive coverage diagnostic; no engine-selection/render/trajectory proof',baseline_sha256=sha(BASE.read_bytes()),unchanged_source_hashes=retained,runtime_data_only_version_changed=True,first_visual_archive_identical050=True,second_visual_archive=source_archive,second_original_row=r,second_main_buffer_delta=224,second_gpu_buffer_delta=640,unit_cpu_sha256=sha(unit),gpu_sha256=sha(gpu),gpu_identical_stock=True,retained_boot_and_entry_payloads=retained_payloads,accepted_reload2x=True,accepted_tuning_unchanged=True,native_publication_thread_safety_unchanged=True,installed_predecessor_unit_overrides=installed,fingerprints='PASS',lua_compile='PASS',fresh051_startup='NOTRUN',loaded051_child_bytes='NOTRUN',geometry='NOTRUN',pellet_trajectory='NOTRUN',final_tuning='GATED',game_writes=0,game_calls=0,deployment=False,settings=False,publication=False,schedules=False)
files['Verification/dual-archive-preservation.json']=(json.dumps(report,indent=2)+'\n').encode()
files['Source/build_v0151_duplicate_archive.py']=Path(__file__).read_bytes()
with zipfile.ZipFile(DEST,'x',zipfile.ZIP_DEFLATED) as z:
    for name,payload in files.items():z.writestr(name,payload)
with zipfile.ZipFile(DEST) as z:
    assert z.testzip() is None and all(z.read(n)==b for n,b in files.items())
    for name,delta_main,delta_gpu in [('Addon/49f1972458f7ccec.patch_0',1360,2176),(second,224,640)]:
        b=z.read(name);tc,fc=struct.unpack_from('<II',b,4);assert (tc,fc)==(1,1)
        row=struct.unpack_from('<7Q6I',b,72+tc*32)
        assert row[:2]==target and b[row[2]:row[2]+row[7]]==unit
        assert row[5]-row[2]==delta_main and row[6]-row[4]==delta_gpu
        assert row[8]==0 and row[9]==len(gpu) and z.read(name+'.gpu_resources')==gpu
    b=z.read(main);tc,fc=struct.unpack_from('<II',b,4);assert fc==len(resources)
    for i,(name,kind,payload,_) in enumerate(resources):
        row=struct.unpack_from('<7Q6I',b,72+tc*32+i*80)
        assert row[:2]==(name,kind) and b[row[2]:row[2]+row[7]]==payload
OUT.mkdir()
for name,payload in files.items():
    if name.startswith('Source/'):
        p=OUT/name;p.parent.mkdir(parents=True,exist_ok=True);p.write_bytes(payload)
report.update(candidate=str(DEST),sha256=sha(DEST.read_bytes()).upper(),zip_integrity='PASS',archive_roundtrip='PASS')
(HERE/'one-two-v0151-package-verification.json').write_text(json.dumps(report,indent=2)+'\n')
print(json.dumps({k:report[k] for k in ['status','candidate','sha256','fresh051_startup','loaded051_child_bytes','pellet_trajectory']},indent=2))
