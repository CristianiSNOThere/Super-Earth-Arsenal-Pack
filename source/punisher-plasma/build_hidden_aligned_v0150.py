"""Build the scoped visual/muzzle candidate from immutable v0149, no deployment."""
from pathlib import Path
from collections import Counter
import hashlib, importlib.util, json, struct, sys, zipfile
import build_test as b

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
OUT = HERE / 'hidden-aligned-v0150'
BASE = ROOT / 'outputs/Punisher-Plasma-One-Two-Attachment-Test-v0.1.49.zip'
DEST = ROOT / 'outputs/Punisher-Plasma-One-Two-Hidden-Aligned-Test-v0.1.50.zip'
assert not DEST.exists(), 'Never overwrite a versioned ZIP'
assert hashlib.sha256(BASE.read_bytes()).hexdigest().upper() == '73D8159E5B3E481EA3D78AE0B2110BBEA4E038D10DE718B4CCC17DDD31098647'
audit = json.loads((OUT / 'visual-alignment-audit.json').read_text())
assert audit['status'] == 'PASS' and audit['maximum_matrix_error'] < 2e-6
unit = (OUT / '02cd7321cd8445f5-hidden-aligned.unit').read_bytes()
assert hashlib.sha256(unit).hexdigest() == audit['candidate_sha256']
with zipfile.ZipFile(BASE) as z:
    files = {name:z.read(name) for name in z.namelist()}
before = dict(files)
old_tag, new_tag = '0.1.49-one-two-test', '0.1.50-one-two-test'
runtime = files['Source/runtime.lua'].decode()
assert runtime.count(old_tag) == 1
runtime = runtime.replace(old_tag, new_tag)
files['Source/runtime.lua'] = runtime.encode()
data = files['Source/one_two_build_data.py'].decode()
assert data.count(old_tag) == 1
files['Source/one_two_build_data.py'] = data.replace(old_tag, new_tag).encode()
sys.path.insert(0, str(ROOT / 'work/expanded-stat-editor'))
from lua_runtime import Lua51
Lua51().compile(runtime.encode(), '@punisher-hidden-aligned-v0150.lua')
# No profile/native/tuning change. Runtime changes exactly one version tag.
assert files['Source/runtime.lua'].replace(new_tag.encode(), old_tag.encode()) == before['Source/runtime.lua']
assert files['Source/one_two_build_data.py'].replace(new_tag.encode(), old_tag.encode()) == before['Source/one_two_build_data.py']
retained = {}
for name, payload in before.items():
    if name.startswith('Source/') and name not in ['Source/runtime.lua', 'Source/one_two_build_data.py']:
        assert files[name] == payload
        retained[name] = hashlib.sha256(payload).hexdigest()
# Verify installed EXE/game.dll against the exact baseline build fingerprints.
ns = {'__file__':str(HERE / 'one_two_build_data.py'), '__name__':'immutable049'}
exec(compile(before['Source/one_two_build_data.py'], 'immutable049-data', 'exec'), ns)
d = ns['data']()
for path, digest in [(Path('D:/SteamLibrary/steamapps/common/Helldivers 2/bin/helldivers2.exe'), d['exe_hash']),
                     (Path('D:/SteamLibrary/steamapps/common/Helldivers 2/data/game/game.dll'), d['game_hash'])]:
    assert hashlib.sha256(path.read_bytes()).hexdigest().upper() == digest

def archive(resources, type_rows=None, gpu=b''):
    counts = Counter(r[1] for r in resources)
    start = (72 + len(counts) * 32 + len(resources) * 80 + 15) & ~15
    blob = bytearray(start)
    rows = []
    for index, (name, kind, payload, template) in enumerate(resources):
        alignment = template[10]
        assert alignment in [16, 32, 64, 128, 256]
        blob += bytes(-len(blob) % alignment)
        offset = len(blob)
        r = list(template)
        r[0:3] = [name, kind, offset]
        r[3] = 0
        # Buffer offsets are archive-relative; keep their original intra-resource deltas.
        r[5] = offset + template[5] - template[2] if template[5] else 0
        r[12] = index
        r[7] = len(payload)
        if gpu:
            assert len(resources) == 1 and r[8] == 0 and len(gpu) == r[9]
            r[4] = 0
            r[6] = template[6] - template[4] if template[6] else 0
        else:
            assert r[8] == r[9] == 0
            r[4] = r[6] = 0
        rows.append(struct.pack('<7Q6I', *r))
        blob += payload
        blob += bytes(-len(blob) % 16)
    types = []
    for kind, count in sorted(counts.items()):
        if type_rows and kind in type_rows:
            tr = list(type_rows[kind]);tr[3] = count
        else:tr = [0,0,kind,count,0,16,16]
        types.append(struct.pack('<IIQIIII', *tr))
    header = struct.pack('<III20sQQ24s', 0xf0000011, len(counts), len(resources), b'', len(blob), len(gpu), b'')
    prefix = header + b''.join(types) + b''.join(rows)
    blob[:len(prefix)] = prefix
    return bytes(blob)

main_name = 'Addon/9ba626afa44a3aa3.patch_0'
raw = files[main_name]
nt, nf = struct.unpack_from('<II', raw, 4)
assert (nt, nf) == (2,3)
resources = [];changed = 0;preserved = []
for i in range(nf):
    r = struct.unpack_from('<7Q6I', raw, 72 + nt * 32 + i * 80)
    payload = raw[r[2]:r[2] + r[7]]
    if payload[8:] == before['Source/runtime.lua']:
        payload = struct.pack('<II', len(runtime.encode()), 2) + runtime.encode();changed += 1
    else:preserved.append((r[0], r[1], hashlib.sha256(payload).hexdigest()))
    resources.append((r[0], r[1], payload, r))
assert changed == 1
files[main_name] = archive(resources)

sp = importlib.util.spec_from_file_location('asset_reader', HERE / 'visual-size/extract_particles.py')
a = importlib.util.module_from_spec(sp);sp.loader.exec_module(a)
stock_archive = '49f1972458f7ccec'
h = a.archive_read(stock_archive, 0, 72)
snt, snf = struct.unpack_from('<II', h, 4)
typebytes = a.archive_read(stock_archive, 72, snt * 32)
type_rows = {struct.unpack_from('<IIQIIII', typebytes, i * 32)[2]:struct.unpack_from('<IIQIIII', typebytes, i * 32) for i in range(snt)}
table = a.archive_read(stock_archive, 72 + snt * 32, snf * 80)
matches = [struct.unpack_from('<7Q6I', table, i * 80) for i in range(snf)
           if struct.unpack_from('<QQ', table, i * 80) == (0x02cd7321cd8445f5, 0xe0a48d0be9a7453f)]
assert len(matches) == 1
row = matches[0]
stock_unit = a.archive_read(stock_archive, row[2], row[7])
assert hashlib.sha256(stock_unit).hexdigest() == audit['stock_sha256']
assert row[8] == 0 and 0 < row[9] < 16777216
gpu = a.archive_read(stock_archive + '.gpu_resources', row[4], row[9])
# Refuse a conflicting installed child-unit override; inspect only local patch headers/tables.
checked = [];conflicts = []
for p in sorted(a.GAME.glob('*.patch_*')):
    if p.suffix in ['.gpu_resources', '.stream']:continue
    try:ph = a.archive_read(p.name, 0, 12)
    except (AssertionError, OSError):raise AssertionError('Unreadable installed patch: ' + p.name)
    assert ph[:4] == b'\x11\x00\x00\xf0', p.name
    pnt, pnf = struct.unpack_from('<II', ph, 4)
    assert pnt < 1000 and pnf < 500000
    pt = a.archive_read(p.name, 72 + pnt * 32, pnf * 80)
    checked.append(p.name)
    for i in range(pnf):
        if struct.unpack_from('<QQ', pt, i * 80) == row[:2]:conflicts.append(p.name)
assert not conflicts, ('Conflicting installed One-Two unit override', conflicts)
visual_name = 'Addon/' + stock_archive + '.patch_0'
assert visual_name not in files
files[visual_name] = archive([(row[0], row[1], unit, row)], type_rows, gpu)
files[visual_name + '.gpu_resources'] = gpu
# Existing049 boot already references the exact child unit; no dependency change.
# Use the existing package type from the049 header instead of guessing its hash.
package_rows = [(name, kind, payload) for name, kind, payload, _ in resources if payload[:8] != struct.pack('<II', len(payload)-8,2)]
assert len(package_rows) == 1
boot = package_rows[0][2]
assert struct.pack('<QQ', row[1], row[0]) in boot, 'Child unit not in retained boot dependencies'

manifest = json.loads(files['manifest.json'])
manifest['Name'] = 'SG-8P Punisher Plasma Hidden Attachment and Muzzle Test v0.1.50'
manifest['Description'] = 'Hidden One-Two geometry and hierarchy-aligned child muzzle candidate; reload2x retained. Gameplay unverified.'
files['manifest.json'] = (json.dumps(manifest,indent=2)+'\n').encode()
report = dict(status='PASS', scope='Offline candidate build/preservation; engine and gameplay unverified',
    baseline=str(BASE), baseline_sha256=hashlib.sha256(BASE.read_bytes()).hexdigest(),
    visual_audit=audit, all_source_profiles_identical049=True, reload_speed_multiplier=2,
    source_safety_hashes=retained, native_publication_and_thread_safety_unchanged=True,
    runtime_only_version_tag_changed=True, retained_boot_and_entry_resources=preserved,
    visual_resource=row[:2], original_unit_row=row, gpu_bytes_identical_stock=True,
    gpu_sha256=hashlib.sha256(gpu).hexdigest(), installed_patch_inventory=checked,
    conflicting_unit_overrides=conflicts, startup='NOTRUN', gameplay='NOTRUN',
    accepted_tuning='UNCHANGED', final_tuning='GATED', deployment=False, settings_changed=False)
for name in list(files):
    if name.startswith('Verification/'):files['Baseline049/'+name] = files.pop(name)
files['Verification/hidden-aligned-preservation.json'] = (json.dumps(report,indent=2)+'\n').encode()
files['Source/audit_hidden_aligned_v0150.py'] = (HERE / 'audit_hidden_aligned_v0150.py').read_bytes()
files['Source/build_hidden_aligned_v0150.py'] = Path(__file__).read_bytes()
files['Visual/02cd7321cd8445f5-hidden-aligned.unit'] = unit
files['README.txt'] = b'''Punisher Plasma v0.1.50 - hidden attachment and aligned muzzle TEST
Based on immutable v0.1.49. Working reload and 2x speed retained exactly.
Accepted normal/pellet tuning and independent native ammo remain unchanged.
One-Two child mesh/LOD counts zero; only child muzzle local/global pose corrected
through the complete Punisher attachment hierarchy. Other18 joints unchanged.
Native installer/publication/thread safety unchanged. Stock GPU bytes retained.
One-Two donor intentionally affected; AR11/Scorcher and other unit owners excluded.
Offline transform equality PASS. Engine loading, invisibility, animated muzzle
alignment and actual pellet trajectory need gameplay validation. Not a final release.
Conditional final tuning remains gated. No settings changes/publication/schedules.

USER DEPLOYS: equip another primary before closing the game. Replace049 with this
ZIP through the existing import/Purge/Deploy workflow; do not stack versions.
Both .patch_0 and .patch_0.gpu_resources visual files must be deployed together.
Restart; wait for fresh050 source installation and child20/60 before firing.
Then check no pink/geometry, normal shot unchanged, pellet muzzle origin/direction
in hipfire and ADS, and reload/interruption still working at2x. Stop on failure.
Agent checks fresh logs; user handles all deployment and gameplay input.
Restart after replacement/refusal/removal; retained native allocations cannot hot-unload.
Baseline049 and Baseline046 verification files are historical evidence.
'''
with zipfile.ZipFile(DEST, 'x', zipfile.ZIP_DEFLATED) as z:
    for name, payload in files.items():z.writestr(name,payload)
with zipfile.ZipFile(DEST) as z:
    assert z.testzip() is None
    assert all(z.read(name) == payload for name,payload in files.items())
    for filename, expected in [(main_name,resources),(visual_name,[(row[0],row[1],unit,row)])]:
        blob = z.read(filename); tc, rc = struct.unpack_from('<II',blob,4)
        assert rc == len(expected)
        for i,(name,kind,payload,_) in enumerate(expected):
            r = struct.unpack_from('<7Q6I',blob,72+tc*32+i*80)
            assert r[:2] == (name,kind) and blob[r[2]:r[2]+r[7]] == payload
            if filename == visual_name:
                assert r[4] == 0 and r[9] == len(gpu)
                assert r[5]-r[2] == row[5]-row[2] and r[6]-r[4] == row[6]-row[4]
    assert z.read(visual_name+'.gpu_resources') == gpu
report.update(candidate=str(DEST),sha256=hashlib.sha256(DEST.read_bytes()).hexdigest().upper(),
              lua_compile='PASS', archive_roundtrip='PASS', zip_integrity='PASS')
(HERE / 'one-two-v0150-package-verification.json').write_text(json.dumps(report,indent=2)+'\n')
source_folder = OUT / 'Source'
source_folder.mkdir(exist_ok=False)
for name,payload in files.items():
    if name.startswith('Source/'):
        p = source_folder / name[7:];p.parent.mkdir(parents=True,exist_ok=True);p.write_bytes(payload)
print(json.dumps({k:report[k] for k in ['status','candidate','sha256','reload_speed_multiplier','startup','gameplay']},indent=2))
