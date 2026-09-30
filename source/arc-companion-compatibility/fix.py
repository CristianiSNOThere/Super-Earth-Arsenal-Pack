from pathlib import Path
import sys, zipfile, json, hashlib, re
ROOT=Path(__file__).resolve().parents[2]; WORK=Path(__file__).resolve().parent
sys.path.insert(0,str(ROOT/'work/expanded-stat-editor'))
import build_complete_pack as b
from lua_runtime import Lua51
runtime=Lua51(); archive=b.load_archive_builder()
STATUS09='Applied: ARC-3 range 55 -> 40 m; charge 1.0/1.1/1.2 -> 0.20/0.22/0.24 s; damage 250/100 -> 163/65; Stun Medium buildup 8 -> 0.8; demolition/force strength/impulse 20/35/10 -> 4/25/2; camera climb 1.0/1.0 -> 0.4/0.4.'
STATUS10='Applied: ARC-3 range 55 -> 45 m; charge 1.0/1.1/1.2 -> 0.307692/0.338462/0.369231 s; damage 250/100 -> 226/90; Stun Medium buildup 8 -> 0.8; demolition/force strength/impulse 20/35/10 -> 4/25/2; camera climb 1.0/1.0 -> 0.4/0.4.'
def once(s,a,c):
    assert s.count(a)==1, a
    return s.replace(a,c)
def fix(s,kind):
    line=next(x for x in s.splitlines() if x.startswith('local ARC_V09_STATUS'))
    s=once(s,line,line+"\nlocal ARC_V10_STATUS='"+STATUS10+"'")
    if kind=='sterilizer':
        s=once(s,"assert(state.version=='0.9' and state.status==ARC_V09_STATUS,\n        'ARC-3 companion status is not a supported v0.9 result')\n    return true", "if state.version=='0.9' and state.status==ARC_V09_STATUS then return 163,65 end\n    if state.version=='0.10' and state.status==ARC_V10_STATUS then return 226,90 end\n    error('ARC-3 companion status is not a supported v0.9/v0.10 result')")
        s=once(s,'local arc_active=peer_arc(arc)','local arc_normal,arc_durable=peer_arc(arc)')
        s=once(s,'if arc_active then','if arc_normal then')
    else:
        s=once(s,"if arc.version~='0.9' or arc.status~=ARC_V09_STATUS then\n            return nil,'unsupported ARC-3 companion result'\n        end", "local arc_normal,arc_durable\n        if arc.version=='0.9' and arc.status==ARC_V09_STATUS then arc_normal,arc_durable=163,65\n        elseif arc.version=='0.10' and arc.status==ARC_V10_STATUS then arc_normal,arc_durable=226,90\n        else return nil,'unsupported ARC-3 companion result' end")
    s=once(s,'u32(s,ARC_DAMAGE_OFFSET+4)~=163 or u32(s,ARC_DAMAGE_OFFSET+8)~=65','u32(s,ARC_DAMAGE_OFFSET+4)~=arc_normal or u32(s,ARC_DAMAGE_OFFSET+8)~=arc_durable')
    s=once(s,"'ARC-3 v0.9 companion values mismatch'","'ARC-3 companion values mismatch'")
    runtime.compile(s.encode(),'@'+kind+'-compatibility.lua')
    return s
def load(p):
    with zipfile.ZipFile(p) as z:
        assert z.testzip() is None
        return {n:z.read(n) for n in z.namelist()}
pack=ROOT/'outputs/releases/published-20260930/Super-Earth-Arsenal-Modpack-v1.0.7.zip'
assert hashlib.sha256(pack.read_bytes()).hexdigest().upper()=='258CE42B2BB11D4C7468D92D82F3952A0EA64775425A783AE45BDE534EAC32EF'
files=load(pack); old=b.resource_envelopes(files['Addon/'+b.ARCHIVE_NAME],'published pack')
updated={};sources={}
for kind in ('sterilizer','sai'):
    keys=[k for k,v in old.items() if b'local ARC_V09_STATUS' in v and (b'local function peer_arc' in v)==(kind=='sterilizer')]
    assert len(keys)==1
    k=keys[0];source=old[k][8:].decode().replace('\r\n','\n');new=fix(source,kind)
    sources[kind]=new; updated[k]=b.RESOURCE_HEADER.pack(len(new.encode()),2)+new.encode()
    (WORK/(kind+'-fixed.lua')).write_text(new,encoding='utf-8')

# Exercise the actual shipped validators in a separate LuaJIT process, using
# canonical private fixture data. No game process is opened or written.
windows=(ROOT/'work/sterilizer-mod/windows.lua').read_text()
data=(ROOT/'work/flag-mod/filediver-master/datalibrary/generated_damage_settings.dl_bin').as_posix()
def quote(s):return '[====['+s+']====]'
for kind,source in sources.items():
    start=source.index('local patch=(function()')+len('local patch=(function()')
    end=source.index('return patch',start)
    validator='validate_damage' if kind=='sterilizer' else 'damage'
    module=source[start:end]+'return '+validator
    test="local make_api=(function()\n"+windows+"\nend)()\nlocal validate=(function()\n"+module+"\nend)()\n"
    test+='local path='+quote(data)+'\nlocal status09='+quote(STATUS09)+'\nlocal status10='+quote(STATUS10)+'\n'
    test+='''
local ffi=require('ffi')
local f=assert(io.open(path,'rb'));local original=f:read('*a');f:close()
local function case(version,status,n,d,reject,offset,extra)
    _G.FlagDamagePrototypeV1=nil;_G.SaiFocusModV1=nil;_G.AR11ArbitratorModV1=nil;_G.RapidArcThrowerV1=nil
    local api=make_api();local hold=ffi.new('uint8_t[?]',#original);ffi.copy(hold,original,#original)
    local p=ffi.cast('uint8_t *',hold)
    ffi.cast('uintptr_t *',p+84)[0]=ffi.cast('uintptr_t',p+100)
    local function put(o,v) ffi.cast('uint32_t *',p+o)[0]=v end
    if version then
        _G.RapidArcThrowerV1={active=true,version=version,status=status}
        put(15076,n);put(15080,d);put(15100,4);put(15104,25);put(15108,2)
        ffi.cast('float *',p+15120)[0]=0.8
    end
    if offset then p[offset]=bit.bxor(p[offset],1) end
    if extra then extra(put) end
    local before=api.read(p,#original)
    local ok,result,reason=pcall(validate,api,p)
    assert((ok and result~=nil)==not reject,tostring(version)..': '..tostring(result)..' '..tostring(reason))
    assert(api.read(p,#original)==before,'validator mutated fixture')
end
case(nil,nil,nil,nil,false)
case('0.9',status09,163,65,false)
case('0.10',status10,226,90,false)
case('0.11',status10,226,90,true)
case('0.10',status09,226,90,true)
case('0.10',status10,163,65,true)
case('0.9',status09,226,90,true)
for _,o in ipairs({15072,15084,15100,15104,15108,15116,15120,10000}) do case('0.10',status10,226,90,true,o) end
case('0.10',status10,226,90,false,nil,function(put)
    _G.FlagDamagePrototypeV1={active=true,status='Applied: flag damage 200 -> 300; durable damage 100 -> 150.'}
    put(41980,300);put(41984,150)
    _G.AR11ArbitratorModV1={active=true,version='0.2',status='Applied: AR-11 rifle damage 70 -> 80; rifle magazine 45 -> 65; underbarrel magazine remains 4 and reserve ammo 20 -> 30; stagger 20 -> 25 with push force 20 unchanged; ergonomics 29 -> 40 with the default optic.'}
    put(10592,80);put(12672,25)
'''
    if kind=='sterilizer':test+="_G.SaiFocusModV1={active=true,status='Applied: SAI normal damage 80 -> 90; durable damage 4 -> 21; Focus Lens spread 75 -> 0.5 MRAD on both axes.'};put(4208,90);put(4212,21)\n"
    test+='end)\n'
    (WORK/(kind+'-validator-test.lua')).write_text(test,encoding='utf-8')
    runtime.run(test.encode(),'@'+kind+'-validator-test.lua')

# Update templates and local generated entry points without replacing their
# discovery/transaction implementations with an older release.
for kind,folder in [('sterilizer','sterilizer-mod'),('sai','sai-mod')]:
    for name in ([ 'sterilizer_patch.lua' ] if kind=='sterilizer' else ['sai_patch.lua'])+['patch_resolved.lua','entry.lua']:
        p=ROOT/'work'/folder/name
        s=p.read_text();p.write_text(fix(s,kind),encoding='utf-8')

out=ROOT/'outputs/releases/compatibility-fix-20260930';out.mkdir(parents=True,exist_ok=True)
report={'result':'passed','gameplay_verified':False,'installed':False,'published':False,'tests':['Actual shipped LuaJIT validators: stock and ARC v0.9/v0.10','ARC before SAI and Sterilizer with supported Flag/AR11/SAI peers','Unknown version/status and mismatched balance rejected','Identity/status/force/buildup/unrelated full-table edits rejected','Validator fixtures unchanged','All unrelated resource envelopes and gameplay settings preserved','Manifest GUIDs and option identities preserved','ZIP/resource roundtrip'],'packages':[]}
repo=ROOT/'work/rapid-arc-thrower/release-repo/mods'
for base,name,version in [(pack,'Super-Earth-Arsenal-Modpack','1.0.8'),(repo/'TX-41-Sterilizer-v0.9.zip','TX-41-Sterilizer','0.10'),(repo/'SAI-Focus-Precision-v0.6.zip','SAI-Focus-Precision','0.7')]:
    fs=load(base); rs=b.resource_envelopes(fs['Addon/'+b.ARCHIVE_NAME],base.name);before=dict(rs)
    changed=[k for k in updated if k in rs]
    assert len(changed)==(2 if base==pack else 1)
    for k in changed:
        assert rs[k]==old[k], 'individual/pack runtime differs'
        rs[k]=updated[k]
    assert {k for k in rs if rs[k]!=before[k]}==set(changed)
    fs['Addon/'+b.ARCHIVE_NAME]=archive.make_archive(rs)
    manifest=json.loads(fs['manifest.json']);identity=(manifest['Guid'],manifest['Options'])
    manifest['Name']=manifest['Name'].rsplit(' v',1)[0]+' v'+version
    fs['manifest.json']=(json.dumps(manifest,indent=2)+'\n').encode()
    assert (manifest['Guid'],manifest['Options'])==identity
    # Keep product descriptions and all current settings; update version labels.
    previous='1.0.7' if base==pack else ('0.9' if 'Sterilizer' in name else '0.6')
    if 'README.txt' in fs:fs['README.txt']=fs['README.txt'].decode().replace('v'+previous,'v'+version).encode()
    for n in list(fs):
        if n.startswith('Source/') and n.endswith('.lua') and b'local ARC_V09_STATUS' in fs[n]:
            kind='sterilizer' if b'local function peer_arc' in fs[n] else 'sai'
            fs[n]=fix(fs[n].decode().replace('\r\n','\n'),kind).encode()
    dest=out/(name+'-v'+version+'.zip');b.write_zip(dest,fs)
    actual=load(dest);assert actual==fs
    assert b.resource_envelopes(actual['Addon/'+b.ARCHIVE_NAME],dest.name)==rs
    assert all(actual[n]==load(base)[n] for n in actual if n.startswith('Addon/') and n!='Addon/'+b.ARCHIVE_NAME)
    report['packages'].append({'file':str(dest),'sha256':hashlib.sha256(dest.read_bytes()).hexdigest().upper(),'changed_resources':[f'{k:016x}' for k in changed],'resources':len(rs)})
(WORK/'validation.json').write_text(json.dumps(report,indent=2)+'\n')
print(json.dumps(report,indent=2))
