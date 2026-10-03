"""Separate inherited historical sources/docs from authoritative shipped sources."""
from pathlib import Path
import hashlib,json,sys,zipfile
H=Path(__file__).resolve().parent;R=H.parents[1];O=R/'outputs/arc-sterilizer-20261003'
sys.path.insert(0,str(R/'work/expanded-stat-editor'));import build_complete_pack as b
report=json.loads((H/'validation.json').read_text());report['intermediate_packages']=report.pop('packages');report['packages']=[]
for item in report['intermediate_packages']:
 p=Path(item['file']);dest=p.with_name(p.stem+'-Test.zip');assert not dest.exists()
 with zipfile.ZipFile(p) as z:files={n:z.read(n) for n in z.namelist()}
 rs=b.resource_envelopes(files['Addon/'+b.ARCHIVE_NAME],p.name)
 for name in list(files):
  if name.startswith('Source/') or name in ['README.txt','README.md']:
   files['HistoricalBaseline/'+name]=files.pop(name)
 for k,payload in rs.items():files[f'Source/Shipped/{k:016x}.lua']=payload[8:]
 for name in ['build.py','finalize.py']:files['Source/Preparation/'+name]=(H/name).read_bytes()
 files['README.txt']=b'''ARC/STerilizer scoped TEST update
ARC-3: Stun Medium buildup1.2 (previous0.8), not stun duration.
TX-41: Acid Storm armor-reduction effect15seconds (previous6).
The Acid Storm status is shared, so its duration changes elsewhere too.
SAI compatibility update required with ARC0.11; SAI tuning unchanged.
Complete modpack109 OR individual ARC011+Sterilizer011+SAI008, never both.
Other weapon tuning, source guards, discovery and transactions retained.
Offline packaged LuaJIT scope/conflict/rollback/peer/checksum tests PASS.
Fresh startup/gameplay NOTRUN. User handles deployment/gameplay when ready;
replace existing versions and restart. No settings or publication performed.
Source/Shipped is authoritative; HistoricalBaseline is inherited evidence only.
'''
 with zipfile.ZipFile(dest,'x',zipfile.ZIP_DEFLATED) as z:
  for name,payload in files.items():z.writestr(name,payload)
 with zipfile.ZipFile(dest) as z:
  assert z.testzip() is None and b.resource_envelopes(z.read('Addon/'+b.ARCHIVE_NAME),dest.name)==rs
  assert all(z.read(f'Source/Shipped/{k:016x}.lua')==v[8:] for k,v in rs.items())
 new=dict(item);new.update(file=str(dest),sha256=hashlib.sha256(dest.read_bytes()).hexdigest().upper());report['packages'].append(new)
(H/'final-validation.json').write_text(json.dumps(report,indent=2)+'\n')
# Preserve the supplied screenshot as user evidence, not startup/mission proof.
src=Path('C:/Users/crife/AppData/Local/Temp/codex-clipboard-22930147-cab6-4a8c-928c-7c95851d4ebf.png')
if src.exists():(R/'work/punisher-plasma/angled-v0154/user-armory-wrong-placement.png').write_bytes(src.read_bytes())
entry='''### 2026-10-03 Arc/Sterilizer scoped adjustments — offline PASS; Punisher054 placement FAIL

User authorizes ARC-3 Stun Medium buildup0.8->1.2 and Sterilizer Acid Storm status duration6->15sec; confirms BOTH individual mods and modpack. Prepared outputs/arc-sterilizer-20261003/*-Test.zip: modpack1.0.9, ARC0.11, Sterilizer0.11, SAI0.8 compatibility only. Authoritative artifacts/hashes work/arc-sterilizer-20261003/final-validation.json. Earlier unsuffixedZIPs are intermediate; deployTest artifacts only. Source/Shipped exactpackagedruntime; inherited stale docs/sources separated underHistoricalBaseline. No publication/repochanges/settings/deployment. User remains in game testingPunisher.

ARCdamage197 offset48 float1.2 only gameplay change;226/90,45m,charge/camera/forces and protected transactions retained. ARC runtime version0.11 and exactstatus updated. Sterilizer Acid55 offset40 float15 instead6 ONLY gameplay change; shared AcidStorm duration also changes elsewhere, existing sharedstatus architecture preserved. SAI+Sterilizer validators retain0.9/0.10 and recognize ONLY exact0.11status+226/90+1.2bits; unknown versions/status/value/force/identity and unrelated full-table edits refuse. No checksum relaxation. Pack changes exactly3of25resources (AE1677AF849B25E2 ARC,E54E34210BAC937E Sterilizer,8BA5FD7BC87570D8 SAI); other22envelopes andAddoncompanions/GUID/options retained. Individualresource envelopes EXACTsamepackversions. All originalZIPs retained.

Offline LuaJIT actualpackaged ARC transactions/scope/conflicts/partialwrites/readback rollback/autofire/unrelatedrowpreservation PASS; shipped SAI/Sterilizer old/newexactpeer+checksum mismatch fixtures PASS; syntheticprivate152byteAcidfieldscope15sec/protectedwriter and unexpected/alreadymodifiedrecordrefusal PASS. Compile/ZIP/resource/source roundtrip PASS. StartupNOTRUN, gameplayNOTRUN. Do not labelprivatefixturesliveevidence. UsepackORall3individualreplacements, notboth; userdeploysandrestartswhenfinishedPunisher. No schedule/publication.

Punisher054: user armory screenshot says grip renders but wrongposition. Record placementFAIL; capacity15 visibleinarmory ONLY, missionammo/spares/refillUNVERIFIED. Screenshot angled-v0154/user-armory-wrong-placement.png. FreshPID16420started19:50:10local; bounded VM_READ loaded-unit-pid16420.json 45reads26429bytes withcompleteequalityrecheck:524candidatechangedbytes match054, gripIKlocal/global andmuzzle match, LOD2mesh4. Completebytehash differsdueruntimeheader/fixups; don'tclaimentire resourceexact. No gamecalls/writes/input. Renderingpresent userconfirmed; handfit/animatedtarget/mountedpose causeUNPROVED. Animationclip edits NOTauthorized andnotprovennecessary. Need heldweaponhandview andactualanimatedrendernode/IK transform join beforeplacementcorrection; avoidblindoffsetguesses. Native/reload2x/muzzle/tuning remainpreserved, LEFTmenu unresolved, finalreleasegated.

'''
for name in ['context.md','modding-findings.md']:
 p=R/name;p.write_text(entry+p.read_text(encoding='utf-8-sig'),encoding='utf-8')
print(json.dumps(report['packages'],indent=2))
