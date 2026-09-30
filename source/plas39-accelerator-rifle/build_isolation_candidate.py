"""Patch current published packages without regenerating other mod resources."""
from pathlib import Path
import hashlib
import json
import re
import zipfile
import build
from lua_runtime import Lua51

ROOT = Path(__file__).resolve().parents[2]
WORK = Path(__file__).resolve().parent
OUT = ROOT / 'outputs/releases'
archive = build.load_archive_builder()
mode, source_report = build.resolve_mode_source()
native, guards = build.resolve_native_source()
implementation = (
    "local make_api = (function()\n" + (WORK / 'windows.lua').read_text() + "\nend)()\n"
    "local patch = (function()\n" + mode + "\nend)()\n"
    "local native = (function()\n" + native + "\nend)()\n"
    "local start = (function()\n" + (WORK / 'startup.lua').read_text() + "\nend)()\n"
    "start(make_api, patch, native)\n"
).encode()
for path, expected in [(build.GAME / 'bin/helldivers2.exe', build.EXE_SHA),
                       (build.GAME / 'data/game/game.dll', build.GAME_DLL_SHA)]:
    assert build.sha(path.read_bytes()) == expected, f'Unsupported game file: {path.name}'
compiled = Lua51().compile(implementation, '@plas39_accelerator_firemode.lua')
envelope = build.RESOURCE_HEADER.pack(len(compiled), 2) + compiled
key = archive.resource_hash(build.IMPL_RESOURCE)
products = [
    (ROOT / 'work/rapid-arc-thrower/release-repo/mods/PLAS-39-Accelerator-Rifle-v1.1.6.zip',
     OUT / 'PLAS-39-Accelerator-Rifle-v1.1.7.zip', 'individual'),
    (ROOT / 'work/super-earth-arsenal-modpack-repo/Super-Earth-Arsenal-Modpack-v1.0.4.zip',
     OUT / 'Super-Earth-Arsenal-Modpack-v1.0.5.zip', 'modpack'),
]
report = {'gameplay_tested': False, 'installed': False, 'published': False,
          'game_process_modified_by_builder': False, 'source_report': source_report,
          'native_guards': guards, 'packages': []}
for source, destination, kind in products:
    with zipfile.ZipFile(source) as z:
        assert z.testzip() is None
        files = {n: z.read(n) for n in z.namelist()}
    manifest = json.loads(files['manifest.json'])
    original_guid = manifest['Guid']
    original_options = manifest['Options']
    original = build.resource_envelopes(files['Addon/' + build.ARCHIVE_NAME])
    assert key in original
    resources = dict(original)
    resources[key] = envelope
    assert [k for k in resources if resources[k] != original[k]] == [key]
    files['Addon/' + build.ARCHIVE_NAME] = archive.make_archive(resources)
    readme = files['README.txt'].decode('utf-8')
    if kind == 'individual':
        manifest['Version'] = '1.1.7'
        manifest['Name'] = 'PLAS-39 Accelerator Rifle v1.1.7'
        # Product description retains every current gameplay value.
        manifest['Description'] = manifest['Description'].replace(
            ' Uses bounded startup discovery and companion initialization guards.', '')
        readme = readme.replace('v1.1.6', 'v1.1.7')
    else:
        readme = readme.replace('v1.0.4', 'v1.0.5').replace('v1.1.6', 'v1.1.7')
        # Correct existing inventory text while retaining stable option identity.
        manifest['Options'][0]['Description'] = manifest['Options'][0]['Description'].replace('all 15 mods', 'all 16 mods')
    if kind=='modpack':
        readme=re.sub(r'\[Download Modpack[^\n]+\n', 'Local modpack candidate v1.0.5; gameplay verification pending.\n', readme, count=1)
    readme += ('\n\nPLAS-39 firing-mode correction\n\n'
               'Semi fires one round at 200 RPM with a 0.01-second minimum charge. '
               'Burst fires three charged rounds, consuming three rounds, with a 0.45-second '
               'minimum charge and 0.12-second spacing between rounds. '
               'Dropped rifles and picking up another Accelerator Rifle no longer prevent '
               'the selected firing mode from applying. Hold R and use Weapon Wheel Left '
               '(default: left-click) to select Semi or Burst.\n\n'
               'Local test candidate: offline checks passed; gameplay verification is pending. '
               'Replace the previous package in Arsenal, Purge and Deploy, and restart the game.\n')
    files['README.txt'] = readme.encode('utf-8')
    assert manifest['Guid'] == original_guid
    assert manifest['Options'][0]['Name'] == original_options[0]['Name']
    assert all('Category' not in o and 'Categories' not in o for o in manifest['Options'])
    assert 'Preset 1' not in manifest['Name'] and 'Preset 1' not in readme
    files['manifest.json'] = (json.dumps(manifest, indent=2) + '\n').encode()
    with zipfile.ZipFile(destination, 'w', zipfile.ZIP_DEFLATED) as z:
        for name, data in files.items():
            z.writestr(name, data)
    with zipfile.ZipFile(destination) as z:
        assert z.testzip() is None
        assert build.resource_envelopes(z.read('Addon/' + build.ARCHIVE_NAME)) == resources
        assert json.loads(z.read('manifest.json'))['Guid'] == original_guid
        assert {n: z.read(n) for n in z.namelist()} == files
    report['packages'].append({
        'file': str(destination.relative_to(ROOT)), 'sha256': build.sha(destination.read_bytes()),
        'base': str(source.relative_to(ROOT)), 'base_sha256': build.sha(source.read_bytes()),
        'resource_count': len(resources), 'changed_resources': [f'{key:016X}'],
        'stable_guid': original_guid, 'stable_option_name': manifest['Options'][0]['Name'],
        'lua_compile': 'passed', 'zip_integrity': 'passed', 'resource_roundtrip': 'passed',
    })
(WORK / 'isolation-implementation-v1.1.7.lua').write_bytes(implementation)
(WORK / 'validation-v1.1.7.json').write_text(json.dumps(report, indent=2) + '\n')
print(json.dumps(report['packages'], indent=2))
