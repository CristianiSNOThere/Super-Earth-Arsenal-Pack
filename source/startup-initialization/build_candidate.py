from pathlib import Path
import sys,zipfile,re,hashlib,json
sys.path.insert(0,'work/expanded-stat-editor');import build_complete_pack as b;import build_preset_mods as profiles
from lua_runtime import Lua51
root=Path.cwd();out=root/'work/modpack-startup-fix';base=root/'work/super-earth-arsenal-modpack-repo/Super-Earth-Arsenal-Modpack-v1.0.2.zip'
with zipfile.ZipFile(base) as z:files={n:z.read(n) for n in z.namelist()}
rs=b.resource_envelopes(files['Addon/'+b.ARCHIVE_NAME],base.name);archive=b.load_archive_builder();changes=[]
for key,envelope in list(rs.items()):
 body=envelope[8:]
 if body.startswith(b'\x1b'):continue
 s=body.decode('utf-8');old=s
 if 'function api.private_regions(' in s:
  begin=s.index('    function api.private_regions(');end=s.index('\n    function api.',begin+10);region=s[begin:end]
  # Only real data-library allocations are eligible for signature search.
  region=region.replace('local regions={}','local regions={}\n        local allocations={}').replace('local regions = {}','local regions = {}\n        local allocations={}')
  assert 'local allocations={}' in region
  needle="regions[#regions+1]={base=ffi.cast('uint8_t *',info[0].base),size=size}"
  if needle not in region:
   print('region skipped nonstandard',hex(key));continue
  replacement="""local allocation=ffi.cast('uint8_t *',info[0].allocation)
                local identity=api.identity(allocation)
                if allocations[identity]==nil then
                    local head=identity>=0x80000000 and api.read(allocation,32) or nil
                    local eligible=false
                    if head then
                        for offset=0,12,4 do
                            if head:sub(offset+1,offset+4)=='LDLD' and u32(head,offset+4)==1 then eligible=true;break end
                        end
                    end
                    allocations[identity]=eligible
                end
                if allocations[identity] then
                    regions[#regions+1]={base=ffi.cast('uint8_t *',info[0].base),size=size}
                end"""
  region=region.replace(needle,replacement);s=s[:begin]+region+s[end:]
  # Limit work done by each module per frame during discovery.
  s=s.replace('deadline=os.clock()+0.004','deadline=os.clock()+0.0007').replace('deadline = os.clock() + 0.004','deadline = os.clock() + 0.0007')
  # Exact supported damage-table global; existing validators still check all bytes.
  marker="    function api.candidates(module,signature,row_offset,header)\n"
  if marker in s:
   s=s.replace(marker,marker+"""        if not header then
            local slot=ffi.cast('uint8_t *',module)+0x348e1f8
            local target=api.pointer(api.read(slot,8),0)
            local head=target and api.read(target,16)
            if head and u32(head,0)==2 and head:sub(5,8)=='LDLD' and u32(head,12)==3943969754 then
                return {target}
            end
        end
""")
 if "-- HD2-Addon: mods/codex/sterilizer_armor_control" in s:
  helper="""    function api.record_candidates(module)
        local function u32(s,o)
            if not s or #s < o+4 then return nil end
            local a,b,c,d=s:byte(o+1,o+4)
            return a+b*256+c*65536+d*16777216
        end
        local base=ffi.cast('uint8_t *',module)
        local owner=assert(api.pointer(api.read(base+0x346bf98,8),0),'Entity owner pointer unavailable')
        local map=assert(api.pointer(api.read(owner+0xf12bd8,8),0),'Entity source table unavailable')
        local entities=map-26151684
        local magazine,health=entities+576052,entities+9520532
        local status={}
        local seen={}
        for _,region in ipairs(api.private_regions(true)) do
            local head=api.read(region.base,56)
            if head then
                for offset=0,12,4 do
                    if head:sub(offset+1,offset+4)=='LDLD' and u32(head,offset+4)==1
                      and u32(head,offset+8)==0xc63e0b22 and u32(head,offset+12)==11888 then
                        local address=region.base+offset+8248
                        if u32(api.read(address,4),0)==55 and not seen[api.identity(address)] then
                            seen[api.identity(address)]=true;status[#status+1]=address
                        end
                    end
                end
            end
            if api.checkpoint then api.checkpoint('Resolving status allocation header') end
        end
        return {{magazine},status,{health}}
    end
"""
  s=s.replace('    function api.writable(p,n)',helper+'    function api.writable(p,n)',1)
  pattern="        local record_addresses=api.scan_private_many({\n            {signature=MAGAZINE_SIGNATURE,row_offset=0},\n            {signature=ACID_DURATION_SIGNATURE,row_offset=16},\n            {signature=HELLDIVER_HEALTH_SIGNATURE,row_offset=0},\n        },true)"
  assert pattern in s
  s=s.replace(pattern,'        local record_addresses=api.record_candidates(module)')
 # Visible profile names are product names; resource identities remain compatible.
 s=s.replace("name = 'Preset 1 - ","name = '")
 if s!=old:
  Lua51().compile(s.encode(),'@startup-module.lua')
  rs[key]=b.RESOURCE_HEADER.pack(len(s.encode()),2)+s.encode();changes.append({'hash':hex(key),'resource':b.resource_label(envelope),'bytes_before':len(body),'bytes_after':len(s.encode())});(out/(hex(key)[2:]+'.lua')).write_text(s,encoding='utf-8')
# Rebuild the common tuning runtime from its source generator with compatible IDs.
s=profiles.make_runtime((root/'work/expanded-stat-editor/editor.lua').read_text(encoding='utf-8'))
for before,after in [('arsenal_standalone_weapon','arsenal_preset01'),('ArsenalStandaloneWeaponRuntime','ArsenalPreset01Runtime'),('ARSENAL_STANDALONE_WEAPON_RUNTIME_API','ARSENAL_PRESET_01_RUNTIME_API'),('ARSENAL_STANDALONE_MOD_REGISTRY','ARSENAL_PRESET_01_PROFILE_REGISTRY'),('ArsenalStandaloneMods.log','ArsenalPreset01Mods.log'),('Standalone Weapon Mods','Weapon and Sentry Mods')]:s=s.replace(before,after)
start=s.index('    if not EXT.preset_peer_deadline then EXT.preset_peer_deadline = api.now() + 120 end')
end=s.index('    if not resolve_some(progress, deadline) then return end',start)
s=s[:start]+'''    if api.now() < (EXT.preset_peer_check_at or 0) then return end
    local peers_ready, peer_reason = EXT.preset_peers_ready()
    if not peers_ready then
        EXT.preset_peer_check_at = api.now() + 1
        local message = 'waiting for installed mod: ' .. tostring(peer_reason)
        if state.status ~= message then set_status('preparing', message) end
        return
    end
'''+s[end:]
# Preserve profile values and compatible resource keys; no new namespaces.
(out/'runtime.lua').write_text(s,encoding='utf-8');compiled=Lua51().compile(s.encode(),'@arsenal_preset01_runtime.lua');key=archive.resource_hash('mods/codex/arsenal_preset01_runtime');assert key in rs
rs[key]=b.RESOURCE_HEADER.pack(len(compiled),2)+compiled;changes.append({'hash':hex(key),'resource':'shared weapon and sentry runtime','source':'runtime.lua'})
files['Addon/'+b.ARCHIVE_NAME]=archive.make_archive(rs)
readme=(root/'work/super-earth-arsenal-modpack-repo/README.md').read_text(encoding='utf-8').replace('v1.0.2','v1.0.3')
readme+='\n## Initialization\n\nWait aboard the ship for installed mods to initialize. Weapon and sentry settings apply when their companion mods finish loading. Initialization searches the game data-library allocations and limits work per frame.\n'
files['README.txt']=readme.encode();manifest=json.loads(files['manifest.json']);manifest['Description']='All 15 mods with the gameplay settings listed in the README, including PLAS-39 Semi/Burst. Uses reduced startup scanning and waits for companion initialization. Requires Bingus Shared Loader v18+ and Steam build 25480438.';files['manifest.json']=(json.dumps(manifest,indent=2)+'\n').encode();files['Source/Initialization/runtime.lua']=s.encode()
package=root/'outputs/releases/Super-Earth-Arsenal-Modpack-v1.0.3.zip';b.write_zip(package,files)
with zipfile.ZipFile(package) as z:
 assert z.testzip() is None
 assert b.resource_envelopes(z.read('Addon/'+b.ARCHIVE_NAME),'candidate')==rs
report={'package':str(package),'sha256':hashlib.sha256(package.read_bytes()).hexdigest().upper(),'changes':changes,'resource_count':len(rs),'gameplay_tested':False,'settings_modified':False,'published':False,'notes':'Shared runtime rebuilt with compatible IDs; private signature scans restricted to recognized game data-library allocations. Source records and peer-active guards retained.'}
(out/'validation-v1.0.3.json').write_text(json.dumps(report,indent=2)+'\n');print(json.dumps(report))
