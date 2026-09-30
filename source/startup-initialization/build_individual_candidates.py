from pathlib import Path
import sys,zipfile,json,hashlib
sys.path.insert(0,'work/expanded-stat-editor');import build_complete_pack as b
root=Path.cwd();repo=root/'work/rapid-arc-thrower/release-repo/mods';out=root/'outputs/releases/individual-startup-fixes';out.mkdir(exist_ok=True);a=b.load_archive_builder()
with zipfile.ZipFile(root/'outputs/releases/Super-Earth-Arsenal-Modpack-v1.0.3.zip') as z:updated=b.resource_envelopes(z.read('Addon/'+b.ARCHIVE_NAME),'candidate')
report=[]
for path in repo.glob('*.zip'):
 if path.name=='Preset-01-03-plas39_accelerator_rifle-v1.0.0.zip':continue
 with zipfile.ZipFile(path) as z:files={n:z.read(n) for n in z.namelist()}
 resources=b.resource_envelopes(files['Addon/'+b.ARCHIVE_NAME],path.name)
 changed=[k for k,v in resources.items() if k in updated and updated[k]!=v]
 if not changed:continue
 for key in changed:resources[key]=updated[key]
 files['Addon/'+b.ARCHIVE_NAME]=a.make_archive(resources)
 manifest=json.loads(files['manifest.json']);manifest['Name']=manifest['Name'].replace('Preset 1 - ','')+' (Startup fix candidate)';files['manifest.json']=(json.dumps(manifest,indent=2)+'\n').encode()
 product=manifest['Name'].replace(' (Startup fix candidate)','')
 product=''.join(ch if ch.isalnum() or ch in '.-' else '-' for ch in product)
 target=out/(product+'-Startup-Fix.zip');b.write_zip(target,files)
 with zipfile.ZipFile(target) as z:
  assert z.testzip() is None
  assert b.resource_envelopes(z.read('Addon/'+b.ARCHIVE_NAME),target.name)==resources
 report.append({'file':target.name,'changed_resources':len(changed),'sha256':hashlib.sha256(target.read_bytes()).hexdigest().upper()})
(root/'work/modpack-startup-fix/individual-candidates.json').write_text(json.dumps(report,indent=2)+'\n');print(json.dumps({'candidates':len(report),'files':[x['file'] for x in report]}))
