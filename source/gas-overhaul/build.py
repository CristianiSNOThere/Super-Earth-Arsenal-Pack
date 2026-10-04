from pathlib import Path
import hashlib, json, struct, sys, zipfile

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(ROOT/'work/expanded-stat-editor'))
import build_complete_pack as b
from lua_runtime import Lua51
lua = Lua51()
archive = b.load_archive_builder()
OUT = ROOT/'outputs/gas-overhaul-20261004'
OUT.mkdir(parents=True, exist_ok=True)
KEY = 0xe54e34210bac937e
sha = lambda x: hashlib.sha256(x).hexdigest().upper()

def envelopes(blob,label):
    tc,count=struct.unpack_from('<II',blob,4);out={}
    for j in range(count):
        at=72+32*tc+j*80
        key,kind,offset=struct.unpack_from('<QQQ',blob,at)
        length=struct.unpack_from('<I',blob,at+56)[0]
        out[(key,kind)]=blob[offset:offset+length]
    return out

def patch_archive(blob,payload):
    tc,count=struct.unpack_from('<II',blob,4);out=bytearray(blob)
    for j in range(count):
        at=72+32*tc+j*80
        key,kind=struct.unpack_from('<QQ',blob,at)
        if key==KEY and kind==b.LUA_TYPE:
            offset=len(out)
            out.extend(payload)
            struct.pack_into('<Q',out,at+16,offset)
            struct.pack_into('<I',out,at+56,len(payload))
            return bytes(out)
    raise AssertionError('Missing gas Lua resource')


def load(p):
    with zipfile.ZipFile(p) as z:
        assert z.testzip() is None
        return {n:z.read(n) for n in z.namelist()}

individual = ROOT/'outputs/releases/published-individual-20261003/TX-41-Sterilizer-v0.11.zip'
pack = ROOT/'outputs/releases/punisher-20261004/Super-Earth-Arsenal-Modpack-v1.0.10.zip'
original = load(individual)
old = b.resource_envelopes(original['Addon/'+b.ARCHIVE_NAME], individual.name)[KEY]
source = old[8:].decode('utf-8').replace('\r\n','\n')
assert source == (ROOT/'work/arc-sterilizer-20261003/sterilizer-entry.lua').read_text().replace('\r\n','\n')
data = (ROOT/'work/flag-mod/filediver-master/datalibrary/generated_damage_settings.dl_bin').read_bytes()
records = [29,65,66,67,391,447,448,449]
offsets={29:2380,65:5420,66:5496,67:5572,391:28980,447:33464,448:33540,449:33616}
rows = [(i,offsets[i],data[offsets[i]:offsets[i]+76]) for i in records]
for i,o,row in rows:
    assert struct.unpack_from('<I',row)[0]==i and row[60:]==bytes(16)
dog=rows[0][2]
def once(s, before, after):
    assert s.count(before) == 1, before
    return s.replace(before,after)

guards = ''.join("    if s:sub(%d,%d)~=unhex('%s') then return nil,'Gas Overhaul record %d mismatch' end\n"%(o+1,o+76,row.hex(),i) for i,o,row in rows)
source=once(source,"    if u32(s,GAS_DOT_OFFSET)~=532",guards+"    if u32(s,GAS_DOT_OFFSET)~=532")
edits=''.join("        {offset=%d,bytes=pack32(55)..unhex('0000803f'),write='normal'},\n"%(o+60) for i,o,row in rows)
source=once(source,"        {offset=DAMAGE_STATUS_OFFSET,bytes=desired_statuses,write='normal'},","        {offset=DAMAGE_STATUS_OFFSET,bytes=desired_statuses,write='normal'},\n"+edits)
source=once(source,'Acid Storm armor reduction added and duration 1 -> 15 seconds.','Gas Overhaul: Acid Storm armor reduction added to player gas hit records; duration 1 -> 15 seconds.')
source = source.replace("version='0.8'", "version='0.12-gas-overhaul-test'")
source = once(source, 'SterilizerArmorControl v0.8\\n', 'SterilizerArmorControl v0.12-gas-overhaul-test\\n')
lua.compile(source.encode(), '@sterilizer-dog-breath-candidate')
(HERE/'sterilizer-entry.lua').write_text(source,encoding='utf-8')

# Reuse the accepted native validator/peer/checksum fixtures with the actual new module.
fixture = (ROOT/'work/arc-sterilizer-20261003/sterilizer-validator-fixture.lua').read_text()
a=fixture.index('local validate,acid='); c=fixture.index('local path=',a)
ps=source.index('local patch=(function()')+len('local patch=(function()');pe=source.index('return patch',ps)
module=source[ps:pe]
fixture=fixture[:a]+'local validate,acid=(function()\n'+module+'return validate_damage,validate_acid_status\nend)()\n'+fixture[c:]
fixture=once(fixture,"    assert(api.read(p,#original)==before,'validator mutated fixture')","    assert(api.read(p,#original)==before,'validator mutated fixture')\n    if not reject then assert(#result.writes==10,'Expected ten scoped damage-table writes') end")
for i,o,row in rows:
    fixture += "\ncase(nil,nil,nil,nil,true,%d)\n"%o
lua.run(fixture.encode(),'@dog-breath-validator-fixture')
(HERE/'validator-fixture.lua').write_text(fixture,encoding='utf-8')

# Exercise the shipped transaction/rollback path using private fixtures only.
txmodule=module.replace('return patch','return patch')
txmodule += '\npatch._set_plans=function(plans) find_damage=function() return plans[1] end; validate_one=function(_,_,_,label) return plans[({magazine=2,[\"acid status\"]=3,[\"Helldiver health\"]=4})[label]] end end\nreturn patch\n'
tx='local patch=(function()\n'+txmodule+'end)()\n'+r'''
local function check(fail)
 local blobs={[1000]=string.rep('A',16),[2000]=string.rep('B',16),[3000]=string.rep('C',16),[4000]=string.rep('D',16)}
 local saved={};local plans={}
 for i,base in ipairs({1000,2000,3000,4000}) do
  saved[base]=blobs[base]
  plans[i]={address=base,size=16,source=blobs[base],writes={{offset=0,bytes='1234',write='normal'}}}
 end
 plans[1].writes={{offset=0,bytes='1111',write='normal'},{offset=4,bytes='2222',write='normal'},{offset=8,bytes='3333',write='normal'}}
 local count=0;local failed=false
 local api={candidates=function()return{}end,record_candidates=function()return{{},{},{}}end,
 read=function(address,n)return blobs[address]end}
 local function write(address,bytes)
  count=count+1
  for base,blob in pairs(blobs) do
   if address>=base and address+#bytes<=base+16 then
    local o=address-base
    if count==fail and not failed then
      failed=true;blobs[base]=blob:sub(1,o)..bytes:sub(1,2)..blob:sub(o+3);return false
    end
    blobs[base]=blob:sub(1,o)..bytes..blob:sub(o+#bytes+1);return true
   end
  end
  return false
 end
 api.write=write;api.write_protected=write
 patch._set_plans(plans)
 local ok,reason=patch.apply(api,0)
 if fail then
  assert(not ok and reason:find('restored=true',1,true),reason)
  for base,blob in pairs(saved)do assert(blobs[base]==blob,'Rollback failed')end
 else assert(ok,reason);assert(blobs[1000]=='111122223333AAAA')end
end
check(nil);for i=1,6 do check(i)end
'''
lua.run(tx.encode(),'@dog-breath-transaction-fixture')
(HERE/'transaction-fixture.lua').write_text(tx,encoding='utf-8')

notes='''TEST CANDIDATE: Gas Overhaul v0.12.
Adds Acid Storm status 55 / strength 1 to empty third status slots on Dog Breath and mapped player gas damage records 65,66,67,391,447,448,449. Covers Re-Educator, Speargun, gas grenade, gas mines, gas sentry and gas strikes.
Preserves direct damage, armor penetration, forces and existing Gas/Confusion strengths for every added record. Existing shared gas damage boost 25 -> 45 normal/durable DPS retained, including its existing hazard sharing.
Existing Sterilizer tuning and shared Acid Storm duration15 seconds are unchanged.
Temporary armor effectiveness reduction; does not permanently destroy armor plates.
Offline validator/checksum/companion, transaction and partial-write rollback checks passed.
Startup and gameplay NOT TESTED. User handles deployment and gameplay.
Use modpack candidate OR individual candidate, never both; replace the older package and restart.
For the modpack: keep all Punisher donor, startup and uninstall warnings. Change away from Punisher WHILE installed before closing and replacing the pack. Start with another primary and wait for initialization.
No deployment, publication, game inputs or running-game writes performed.
'''
report={'offline':'PASS','startup':'NOTRUN','gameplay':'NOTRUN','deployment':False,'publication':False,'change':{'damage_types':records,'status_type':55,'strength':1,'duration_seconds':15},'packages':[]}
for base,name in [(individual,'Gas-Overhaul-Test-v0.12.zip'),(pack,'Super-Earth-Arsenal-Modpack-Gas-Overhaul-Test-v1.0.11.zip')]:
 fs=load(base);prior=dict(fs);rs=envelopes(fs['Addon/'+b.ARCHIVE_NAME],base.name);before=dict(rs)
 assert rs[(KEY,b.LUA_TYPE)]==old
 rs[(KEY,b.LUA_TYPE)]=struct.pack('<II',len(source.encode()),2)+source.encode()
 fs['Addon/'+b.ARCHIVE_NAME]=patch_archive(fs['Addon/'+b.ARCHIVE_NAME],rs[(KEY,b.LUA_TYPE)])
 for n,payload in list(fs.items()):
  if n.startswith('Source/') and payload==old[8:]:fs[n]=source.encode()
 fs['Source/sterilizer-dog-breath-test.lua']=source.encode()
 fs['DOG-BREATH-TEST-README.txt']=notes.encode()
 for n in ('README.md','README.txt'):
  if n in fs:fs[n]=notes.encode()+b'\nBaseline documentation follows:\n'+fs[n]
 m=json.loads(fs['manifest.json']);identity=m['Guid'],m['Options']
 m['Name']='Gas Overhaul TEST' if base==individual else m['Name']+' - Gas Overhaul TEST'
 m['Description']='TEST Gas Overhaul: extends Acid Storm armor reduction to player gas weapons; existing tuning retained. '+m.get('Description','')
 fs['manifest.json']=(json.dumps(m,indent=2)+'\n').encode()
 assert (m['Guid'],m['Options'])==identity
 assert {k for k in rs if rs[k]!=before[k]}=={(KEY,b.LUA_TYPE)}
 for n,payload in prior.items():
  if n.startswith('Addon/') and n!='Addon/'+b.ARCHIVE_NAME:assert fs[n]==payload
 dest=OUT/name
 if dest.exists():
  existing=load(dest)
  assert envelopes(existing['Addon/'+b.ARCHIVE_NAME],name)==rs
  fs=existing
 else:
  with zipfile.ZipFile(dest,'x',zipfile.ZIP_DEFLATED) as z:
   for n,payload in fs.items():z.writestr(n,payload)
 assert load(dest)==fs
 assert envelopes(fs['Addon/'+b.ARCHIVE_NAME],name)==rs
 report['packages'].append({'path':str(dest),'sha256':sha(dest.read_bytes()),'baseline_sha256':sha(base.read_bytes()),'changed_runtime_resources':[f'{KEY:016x}'],'unchanged_runtime_resources':len(rs)-1})
(HERE/'validation.json').write_text(json.dumps(report,indent=2)+'\n')
(HERE/'README.md').write_text(notes)
print(json.dumps(report,indent=2))
