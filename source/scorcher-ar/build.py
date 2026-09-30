from pathlib import Path
import sys,zipfile,json,uuid,hashlib,struct
root=Path.cwd();work=root/'work/scorcher-ar';sys.path.insert(0,'work/expanded-stat-editor')
import build_complete_pack as b
from lua_runtime import Lua51
stock=json.loads((root/'work/expanded-stat-editor/stock_fields.json').read_text())
assert stock['FB8D88A3|EEA5E3CEF1E12C14|136']==20
assert struct.unpack('<f',struct.pack('<I',stock['45171B68|EEA5E3CEF1E12C14|8']))[0]==350
base=root/'work/rapid-arc-thrower/release-repo/mods/P-34-Breacher-v1.0.1.zip'
with zipfile.ZipFile(base) as z:resources=b.resource_envelopes(z.read('Addon/'+b.ARCHIVE_NAME),base.name)
archive=b.load_archive_builder();del resources[archive.resource_hash('mods/codex/preset01_p34_breacher')]
runtime=(root/'work/modpack-startup-fix/runtime.lua').read_text(encoding='utf-8')
# A separate runtime prevents load-order dependence on the older shared runtime,
# which does not expose projectile explosion damage as an editable profile field.
runtime=runtime.replace('local id = blast.damage and read_field(field_at(T_EXPLOSION, xrow + 4, \'u32\', 100000))','local id = read_field(field_at(T_EXPLOSION, xrow + 4, \'u32\', 100000))')
assert "local id = read_field(field_at(T_EXPLOSION, xrow + 4, 'u32', 100000))" in runtime
for old,new in [('ArsenalPreset01Runtime','ScorcherARRuntime'),('ARSENAL_PRESET_01_RUNTIME_API','SCORCHER_AR_RUNTIME_API'),('ARSENAL_PRESET_01_PROFILE_REGISTRY','SCORCHER_AR_PROFILE_REGISTRY'),('ArsenalPreset01Mods.log','ScorcherAR.log')]:runtime=runtime.replace(old,new)
# Restrict the existing catalog without adding top-level locals (LuaJIT limit).
start=runtime.index('local WEAPONS = {');end=runtime.index('\n}',start)+2
runtime=runtime[:start]+"local WEAPONS = {{ 'PLAS-1 Scorcher', 'Primary', 'EEA5E3CEF1E12C14', '' }}"+runtime[end:]
del resources[archive.resource_hash('mods/codex/arsenal_preset01_runtime')]
compiled=Lua51().compile(runtime.encode(),'@scorcher-runtime.lua')
resources[archive.resource_hash('mods/codex/scorcher_ar_runtime')]=b.RESOURCE_HEADER.pack(len(compiled),2)+compiled
name='mods/codex/plas1_scorcher_ar'
source="""-- HD2-Addon: mods/codex/plas1_scorcher_ar
local runtime = require('mods/codex/scorcher_ar_runtime')
local ok, why = runtime.register_profile({
    id = 'plas1_scorcher_ar',
    name = 'PLAS-1 Scorcher AR',
    hash = 'EEA5E3CEF1E12C14',
    values = {
        { hash = 'EEA5E3CEF1E12C14', id = 'capacity', value = 50 },
        { hash = 'EEA5E3CEF1E12C14', id = 'rpm', value = 600 },
        { hash = 'EEA5E3CEF1E12C14', id = 'damage', value = 75 },
        { hash = 'EEA5E3CEF1E12C14', id = 'durable', value = 38 },
        { hash = 'EEA5E3CEF1E12C14', id = 'blast_damage', value = 75 },
        { hash = 'EEA5E3CEF1E12C14', id = 'blast_durable', value = 75 },
        { hash = 'EEA5E3CEF1E12C14', id = 'blast_inner', value = 1.25 },
        { hash = 'EEA5E3CEF1E12C14', id = 'blast_outer', value = 2.5 },
        { hash = 'EEA5E3CEF1E12C14', id = 'mags_start', value = 4 },
        { hash = 'EEA5E3CEF1E12C14', id = 'mags_max', value = 6 },
        { hash = 'EEA5E3CEF1E12C14', id = 'recoil_dh', value = 15 },
        { hash = 'EEA5E3CEF1E12C14', id = 'recoil_dv', value = 15 },
        { hash = 'EEA5E3CEF1E12C14', id = 'recoil_ch', value = 1.5 },
        { hash = 'EEA5E3CEF1E12C14', id = 'recoil_cv', value = 15 }
    },
})
if not ok then error(why) end
return runtime
"""
Lua51().compile(source.encode(),'@scorcher.lua')
resources[archive.resource_hash(name)]=b.RESOURCE_HEADER.pack(len(source.encode()),2)+source.encode()
readme='''# PLAS-1 Scorcher AR v1.0.0

## Current gameplay changes

Increases the magazine from 20 to 50 rounds and fire rate from 350 to 600 RPM. Reduces normal damage from 200 total to 150: 75 impact plus 75 explosion, before armor, hit location and distance falloff. Sets impact durable damage to 38 and explosion durable damage to 75 (113 combined against fully durable targets). Increases the full-damage blast radius from 1 to 1.25 metres and outer blast radius from 2 to 2.5 metres. Starting spare magazines increase from 3 to 4, and maximum spare magazines from 5 to 6; resupply grants 5 magazines. Uses the Scorcher's native Semi and Auto selector. Select Auto in Weapon Functions for continuous fire; at 600 RPM, a 50-round magazine provides approximately five seconds of sustained fire.

## Install

Import the ZIP into Arsenal and enable PLAS-1 Scorcher AR. Keep Bingus Shared Loader at its documented priority, Purge and Deploy, then restart Helldivers 2. Requires Steam build 25480438 and Bingus Shared Loader v15 or newer. It can be used with Super-Earth Arsenal Modpack v1.0.3, which does not contain Scorcher tuning. Startup uses the same shared runtime and companion initialization guards as the weapon tuning mods. Conflicting edits prevent the settings from applying.
'''
readme=readme.replace('## Install','Reduces horizontal/vertical recoil drift from 20 to 15, horizontal camera recoil from 2 to 1.5, and vertical camera recoil from 20 to 15 (25% less per shot).\n\n## Install')
manifest={'Version':1,'Guid':str(uuid.uuid5(uuid.UUID('2a1296c8-274d-4f08-a5a3-b241a26a0a30'),'plas1_scorcher_ar')),'Name':'PLAS-1 Scorcher AR v1.0.0','Description':'50 rounds, 600 RPM, 150 total normal damage and increased blast radius. Native Semi/Auto fire. Requires Bingus Shared Loader v15+ and Steam build 25480438.','Options':[{'Name':'Enable PLAS-1 Scorcher AR','Description':'Applies the magazine, rate, damage and blast radius settings listed in the README.','Include':['Addon']}]}
files={'manifest.json':(json.dumps(manifest,indent=2)+'\n').encode(),'README.txt':readme.encode(),'Addon/'+b.ARCHIVE_NAME:archive.make_archive(resources),'Addon/'+b.ARCHIVE_NAME+'.stream':b'','Addon/'+b.ARCHIVE_NAME+'.gpu_resources':b'','Source/scorcher.lua':source.encode(),'Source/runtime.lua':runtime.encode()}
target=root/'outputs/PLAS-1-Scorcher-AR-v1.0.0.zip';b.write_zip(target,files)
with zipfile.ZipFile(target) as z:
 assert z.testzip() is None
 assert b.resource_envelopes(z.read('Addon/'+b.ARCHIVE_NAME),target.name)==resources
(work/'scorcher.lua').write_text(source);(work/'README.md').write_text(readme)
report={'package':str(target),'sha256':hashlib.sha256(target.read_bytes()).hexdigest().upper(),'stock_capacity':20,'stock_rpm':350,'capacity':50,'rpm':600,'impact_damage':75,'explosion_damage':75,'impact_durable':38,'explosion_durable':75,'inner_radius':1.25,'outer_radius':2.5,'starting_spares':4,'maximum_spares':6,'compilation_and_package_checks':'passed','gameplay_tested':False,'published':False,'settings_modified':False}
report['recoil']={'horizontal_drift':15,'vertical_drift':15,'horizontal_camera':1.5,'vertical_camera':15}
(work/'validation.json').write_text(json.dumps(report,indent=2)+'\n');print(json.dumps(report))
