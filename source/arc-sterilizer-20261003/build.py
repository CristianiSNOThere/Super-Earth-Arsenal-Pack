"""Two scoped balance changes from exact published packages; no deployment."""
from pathlib import Path
import hashlib,json,struct,sys,zipfile
H=Path(__file__).resolve().parent;R=H.parents[1];H.mkdir(exist_ok=True)
sys.path.insert(0,str(R/'work/expanded-stat-editor'));import build_complete_pack as b
from lua_runtime import Lua51
lua=Lua51();archive=b.load_archive_builder();OUT=R/'outputs/arc-sterilizer-20261003';OUT.mkdir(exist_ok=True)
BASE=R/'outputs/releases/published-compatibility-20260930';PACK=BASE/'Super-Earth-Arsenal-Modpack-v1.0.8.zip'
sha=lambda x:hashlib.sha256(x).hexdigest().upper()
assert sha(PACK.read_bytes())=='4EABFFF1C8820E851B03FA48641609BEAD658D3C9D4AAAA86F954D64D506D587'
def load(p):
 with zipfile.ZipFile(p) as z:assert z.testzip() is None;return {n:z.read(n) for n in z.namelist()}
def once(s,a,c):assert s.count(a)==1,(a,s.count(a));return s.replace(a,c)
fs=load(PACK);old=b.resource_envelopes(fs['Addon/'+b.ARCHIVE_NAME],'published108');sources={};updated={}
STATUS10=next(l.split("=",1)[1].strip().strip("'") for l in old[0xe54e34210bac937e][8:].decode().splitlines() if l.startswith('local ARC_V10_STATUS'))
STATUS11=STATUS10.replace('buildup 8 -> 0.8','buildup 8 -> 1.2')
def change(s,kind):
 if kind=='arc':
  s=once(s,"[0.8] = 'cdcc4c3f'","[1.2] = '9a99993f'")
  s=once(s,'offset=48,bytes=float_word(0.8)','offset=48,bytes=float_word(1.2)')
  s=once(s,STATUS10,STATUS11);s=once(s,"version='0.10'","version='0.11'")
 else:
  line=next(l for l in s.splitlines() if l.startswith('local ARC_V10_STATUS'))
  s=once(s,line,line+"\nlocal ARC_V11_STATUS='"+STATUS11+"'")
  if kind=='sterilizer':
   s=once(s,"then return 163,65 end","then return 163,65,'cdcc4c3f' end")
   s=once(s,"then return 226,90 end","then return 226,90,'cdcc4c3f' end\n    if state.version=='0.11' and state.status==ARC_V11_STATUS then return 226,90,'9a99993f' end")
   s=once(s,'local arc_normal,arc_durable=peer_arc(arc)','local arc_normal,arc_durable,arc_buildup=peer_arc(arc)')
   s=once(s,"unhex('0000c040'),write='protected'","unhex('00007041'),write='protected'")
   s=once(s,'duration 1 -> 6 seconds','duration 1 -> 15 seconds')
   s=once(s,'supported v0.9/v0.10 result','supported v0.9/v0.10/v0.11 result')
  else:
   s=once(s,'local arc_normal,arc_durable\n','local arc_normal,arc_durable,arc_buildup\n')
   s=once(s,'then arc_normal,arc_durable=163,65','then arc_normal,arc_durable,arc_buildup=163,65,\'cdcc4c3f\'')
   s=once(s,'then arc_normal,arc_durable=226,90',"then arc_normal,arc_durable,arc_buildup=226,90,'cdcc4c3f'\n        elseif arc.version=='0.11' and arc.status==ARC_V11_STATUS then arc_normal,arc_durable,arc_buildup=226,90,'9a99993f'")
  s=once(s,"s:sub(ARC_DAMAGE_OFFSET+49,ARC_DAMAGE_OFFSET+52)~=unhex('cdcc4c3f')","s:sub(ARC_DAMAGE_OFFSET+49,ARC_DAMAGE_OFFSET+52)~=unhex(arc_buildup)")
 lua.compile(s.encode(),'@'+kind+'-candidate');return s
for kind,k in [('arc',0xae1677af849b25e2),('sterilizer',0xe54e34210bac937e),('sai',0x8ba5fd7bc87570d8)]:
 s=change(old[k][8:].decode().replace('\r\n','\n'),kind);sources[kind]=s;updated[k]=struct.pack('<II',len(s.encode()),2)+s.encode();(H/(kind+'-entry.lua')).write_text(s)
# Actual shipped ARC transaction fixture, isolated and using private string data.
test=(R/'work/rapid-arc-thrower/test.py').read_text();start=test.index('    lua += r\'\'\'')+len('    lua += r\'\'\'');end=test.index("\n'''",start)
body=test[start:end].replace('string.char(205,204,76,63)','string.char(154,153,153,63)')
arc_source=sources['arc'];ps=arc_source.index('local patch=(function()')+len('local patch=(function()');pe=arc_source.index('return patch',ps)
fixture='local patch=(function()\n'+arc_source[ps:pe]+'return patch\nend)()\n'
data=R/'work/flag-mod/filediver-master/datalibrary';entities=(data/'generated_entities.dl_bin').read_bytes()
for name,payload in [('DAMAGE',(data/'generated_damage_settings.dl_bin').read_bytes()),('GROUP',entities[7565064:7565064+2724]),('WEAPON',entities[26566228:26566228+1232]),('ARC',(data/'generated_arc_settings.dl_bin').read_bytes())]:fixture+='local '+name+"='"+''.join('\\%03d'%x for x in payload)+"'\n"
fixture+=body;lua.run(fixture.encode(),'@arc-transaction-candidate');(H/'arc-transaction-fixture.lua').write_text(fixture)
# Use prior shipped validator fixtures, including exact old peers and full checksum.
for kind in ['sterilizer','sai']:
 prior=(R/'work/modpack-loading-20260930'/(kind+'-validator-test.lua')).read_text()
 a=prior.index('local validate=(function()');c=prior.index('local path=',a)
 s=sources[kind];ps=s.index('local patch=(function()')+len('local patch=(function()');pe=s.index('return patch',ps)
 validator='validate_damage' if kind=='sterilizer' else 'damage'
 module=s[ps:pe]+'return '+validator
 if kind=='sterilizer':module=module.replace('return '+validator,'return '+validator+',validate_acid_status')
 new=prior[:a]+('local validate,acid=' if kind=='sterilizer' else 'local validate=')+'(function()\n'+module+'\nend)()\n'+prior[c:]
 new=new.replace("local status10=", "local status11=[====["+STATUS11+"]====]\nlocal status10=")
 new=once(new,"ffi.cast('float *',p+15120)[0]=0.8","ffi.cast('float *',p+15120)[0]=(version=='0.11' and status==status11) and 1.2 or 0.8")
 new+= "\ncase('0.11',status11,226,90,false)\ncase('0.12',status11,226,90,true)\ncase('0.10',status11,226,90,true)\ncase('0.11',status11,163,65,true)\nfor _,o in ipairs({15072,15084,15100,15104,15108,15116,15120,10000})do case('0.11',status11,226,90,true,o)end\n"
 if kind=='sterilizer':
  new+=r'''
-- Synthetic private record with exact shipped signature; not gameplay evidence.
local blob=string.char(55,0,0,0)..string.rep('\0',12)..string.char(0,0,0,0,0,0,0,0,157,185,88,189,215,231,188,150,0,0,192,63,0,0,128,63,0,0,128,63)..string.rep('\0',108)
assert(#blob==152)
local api={data_access=function()return true end,read=function()return blob end}
local spec,reason=acid(api,1);assert(spec,reason)
assert(spec.writes[1].offset==40 and spec.writes[1].bytes==string.char(0,0,112,65) and spec.writes[1].write=='protected')
assert(spec.source==blob and #spec.writes==1)
local saved=blob;blob=blob:sub(1,40)..string.char(0,0,192,64)..blob:sub(45)
assert(not acid(api,1),'Already changed/shared Acid record must refuse')
blob=saved:sub(1,16)..string.char(1)..saved:sub(18);assert(not acid(api,1),'Unexpected Acid fields must refuse')
'''
 lua.run(new.encode(),'@'+kind+'-validator-candidate');(H/(kind+'-validator-fixture.lua')).write_text(new)
report=dict(offline='PASS',startup='NOTRUN',gameplay='NOTRUN',deployment=False,publication=False,settings=False,arc=dict(stun_medium_buildup=1.2),sterilizer=dict(acid_storm_duration=15,shared_status=True),packages=[])
for base,name,version in [(PACK,'Super-Earth-Arsenal-Modpack','1.0.9'),(R/'outputs/releases/published-20260930/ARC-3-Rapid-Arc-Thrower-v0.10.zip','ARC-3-Rapid-Arc-Thrower','0.11'),(BASE/'TX-41-Sterilizer-v0.10.zip','TX-41-Sterilizer','0.11'),(BASE/'SAI-Focus-Precision-v0.7.zip','SAI-Focus-Precision','0.8')]:
 dest=OUT/(name+'-v'+version+'.zip');assert not dest.exists()
 fs=load(base);original=dict(fs);rs=b.resource_envelopes(fs['Addon/'+b.ARCHIVE_NAME],base.name);prev=dict(rs);keys=set(updated)&set(rs)
 assert len(keys)==(3 if base==PACK else 1)
 for k in keys:assert rs[k]==old[k];rs[k]=updated[k]
 fs['Addon/'+b.ARCHIVE_NAME]=archive.make_archive(rs)
 for n,payload in list(fs.items()):
  if n.startswith('Source/') and n.endswith('.lua'):
   for k in keys:
    if payload==old[k][8:]:fs[n]=updated[k][8:]
   # Module-only ARC Source files are reviewed exact substitutions below.
   if name.startswith('ARC') and n=='Source/arc_patch.lua':
    t=payload.decode();t=once(t,"[0.8] = 'cdcc4c3f'","[1.2] = '9a99993f'");t=once(t,'offset=48,bytes=float_word(0.8)','offset=48,bytes=float_word(1.2)');t=once(t,STATUS10,STATUS11);fs[n]=t.encode()
   if name.startswith('ARC') and n=='Source/startup.lua':fs[n]=once(payload.decode(),"version='0.10'","version='0.11'").encode()
 m=json.loads(fs['manifest.json']);identity=m['Guid'],m['Options'];m['Name']=m['Name'].rsplit(' v',1)[0]+' v'+version
 m['Description']=m.get('Description','').replace('stun buildup to 0.8','stun buildup to 1.2').replace('6 seconds','15 seconds')
 fs['manifest.json']=(json.dumps(m,indent=2)+'\n').encode()
 notes='''Offline test candidate. User handles deployment/gameplay; no publication.
ARC-3 Stun Medium buildup0.8 ->1.2; other ARC settings retained.
TX-41 Acid Storm duration6 ->15seconds; shared Acid Storm status also affected.
SAI/Sterilizer exact ARC0.11 compatibility guards updated; other tuning retained.
Offline shipped LuaJIT transactions/rollback, peer versions/values/checksum,
Acid field guard/scope and ZIP/resource checks passed. Startup/gameplay NOTRUN.
Use complete modpack OR individual Arc+Sterilizer+SAI candidates, never both.
Do not deploy while testing Punisher. Replace existing versions and restart when
ready. Check fresh startup logs before testing weapons. No settings changes.
'''
 for n in ['README.txt','README.md']:
  if n in fs:fs[n]=notes.encode()+b'\nHistorical baseline documentation follows; values above supersede it.\n'+fs[n]
 fs['Verification/scoped-adjustments.json']=(json.dumps({k:v for k,v in report.items() if k!='packages'},indent=2)+'\n').encode()
 for n,payload in fs.items():
  if n.startswith('Source/') and n.endswith('.lua'):lua.compile(payload,'@'+n)
 with zipfile.ZipFile(dest,'x',zipfile.ZIP_DEFLATED) as z:
  for n,payload in fs.items():z.writestr(n,payload)
 actual=load(dest);assert actual==fs;assert b.resource_envelopes(actual['Addon/'+b.ARCHIVE_NAME],name)==rs
 assert (m['Guid'],m['Options'])==identity
 assert {k for k in rs if rs[k]!=prev[k]}==keys
 for n,payload in original.items():
  if n.startswith('Addon/') and n!='Addon/'+b.ARCHIVE_NAME:assert fs[n]==payload
 report['packages'].append(dict(file=str(dest),sha256=sha(dest.read_bytes()),changed_resources=[f'{k:016X}' for k in sorted(keys)],unchanged_resources=len(rs)-len(keys)))
(H/'validation.json').write_text(json.dumps(report,indent=2)+'\n');print(json.dumps(report,indent=2))
