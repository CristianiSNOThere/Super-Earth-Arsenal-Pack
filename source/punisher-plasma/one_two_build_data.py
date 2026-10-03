"""Immutable source targets and exact saved-build guards for automatic child test."""
from pathlib import Path
import struct,json,hashlib
import build_test as baseline
base=Path(__file__).resolve().parent;root=base.parents[1]
def data():
 p=root/'work/sai-mod/inspect.py';ns={'__file__':str(p)}
 exec(compile(p.read_text().split("report={'weapon':")[0],str(p),'exec'),ns)
 e=ns['entities'];assert hashlib.sha256(e).hexdigest().upper()==json.loads((base/'source-audit.json').read_text())['entity_sha256']
 parent=0x05d8d8c073b9d502;child=0x02cd7321cd8445f5
 specs=[('parent_weapon',parent,'WeaponDataComponent',236),('parent_projectile',parent,'ProjectileWeaponComponent',321),('parent_magazine',parent,'WeaponMagazineComponent',5),('parent_customization',parent,'WeaponCustomizationComponent',271),('child_weapon',child,'WeaponDataComponent',236),('child_projectile',child,'ProjectileWeaponComponent',321),('child_rounds',child,'WeaponRoundsComponent',117)]
 specs.append(('child_reload',child,'WeaponReloadComponent',113))
 rows=[]
 for role,owner,component,index in specs:
  hits,meta=ns['component_for'](owner,component);assert len(hits)==1
  rid,pos=hits[0];count=meta['map_count'];assert meta['record_offset']==count*16
  owners=[struct.unpack_from('<Q',e,meta['group']+28+i*16)[0] for i in range(count) if struct.unpack_from('<I',e,meta['group']+28+i*16+8)[0]==rid and struct.unpack_from('<Q',e,meta['group']+28+i*16)[0]]
  assert owners==[owner],('Shared target',role,owners)
  assert struct.unpack_from('<I',e,meta['group']-4)[0]==index
  rows.append(dict(role=role,owner=struct.pack('<Q',owner),offset=0xf12478+index*8,count=count,index=rid,stride=meta['stride'],before=e[pos:pos+meta['stride']]))
 hits,meta=ns['component_for'](0xdcd1c835407ef7ba,'WeaponReloadComponent');assert len(hits)==1
 rid,pos=hits[0];assert rid==126 and meta['stride']==80
 reload=e[pos:pos+80];assert struct.unpack_from('<I',reload,4)[0]==2773
 assert hashlib.sha256(reload).hexdigest()=='ebe47e4bf45b29d9d9c39af40b2a48cfcf7d61bb3d4286adc3a0bdbe8de792eb'
 d=baseline.data(tuning=True,mode_index_sync=True,blast_burning=True)
 d['child_reload_template']=bytes.fromhex('00010000d60a00000100000015fe9ff1e5c589c8030000004b1ac367cd1f7a72000000000000000000000000000000000000000000000000000000000000000045bf1295b397435ce86f77b500000000')
 d.update(next_tuning=True,magazine_tuning=False,normal_flight=True,sway_factor=0.5,pellet_split='direct25-9-blast25-9',normal_two_shot=True,pellet_angle_ap=3,normal_single_fast=120,version='0.1.65-one-two-test',child_owner=struct.pack('<Q',child),one_two_owner=struct.pack('<Q',0xa955c4ea6f6d4203),source_rows=rows)
 report=json.loads((base/'one-two-attachment-swap-verification.json').read_text());assert report['status']=='PASS'
 d['attachment_code']=[dict(rva=int(g['rva'],16),bytes=bytes.fromhex(g['bytes'])) for g in report['native_instruction_guards']]
 return d
if __name__=='__main__':
 d=data();print([(r['role'],r['index'],r['stride']) for r in d['source_rows']])
