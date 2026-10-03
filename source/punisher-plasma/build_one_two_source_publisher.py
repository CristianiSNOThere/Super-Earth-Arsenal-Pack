"""Derive a bounded all-before-write source-word transaction from tested barrier."""
from pathlib import Path
import hashlib,json,importlib.util
from one_two_protection_codegen import extend
base=Path(__file__).resolve().parent
def build():
 stock=(base/'private_delta_publish.c').read_text(encoding='utf-8-sig')
 s=stock.replace('typedef struct {const uint8_t *address,*expected;uint32_t size;} Guard;',
 '''typedef struct {const uint8_t *address,*expected;uint32_t size;} Guard;
typedef struct {uint32_t *address;uint32_t before,after,size,reserved;} Patch;
_Static_assert(sizeof(Patch)==24,"Source patch ABI");''')
 a=s.index(' if(!s->slot||');b=s.index(' uint8_t bytes[256];',a)
 s=s[:a]+''' d->stage=20;
 if(!s->slot||((uintptr_t)s->slot&7)||s->before<1||s->before>1024||
    s->after!=0x39334f5754505055ULL||s->guard_count<2||s->guard_count>1024||!s->guards)goto done;
 const Patch *patches=(const Patch*)s->slot;
 snapshot(s,patches,&d->before_page);
 if(d->before_page.query_size!=sizeof(MEMORY_BASIC_INFORMATION)||
    d->before_page.state!=MEM_COMMIT||d->before_page.type!=MEM_PRIVATE||
    d->before_page.protect!=PAGE_READWRITE||
    (uintptr_t)patches+s->before*sizeof(Patch)<(uintptr_t)patches||
    (uintptr_t)patches+s->before*sizeof(Patch)>d->before_page.base+d->before_page.region_size)goto done;
 /* Validate every descriptor/target before the first data store. */
 for(unsigned i=0;i<s->before;i++){
  const Patch *p=&patches[i];d->stage=21;d->patch_index=i;d->address=(uintptr_t)p->address;d->size=4;
  /* Source-only aliases in the unchanged diagnostic ABI: requested=reason,
   * restore_error=expected word, restore_index=observed word. No rollback. */
  d->restore_error=p->before;d->restore_index=0;
  if(!p->address||((uintptr_t)p->address&3)||p->size!=4||p->reserved||p->before==p->after){d->requested=1;goto done;}
  for(unsigned j=0;j<i;j++)if(patches[j].address==p->address){d->requested=2;goto done;}
  snapshot(s,p->address,&d->before_page);
  if(d->before_page.query_size!=sizeof(MEMORY_BASIC_INFORMATION)){d->requested=3;goto done;}
  if(d->before_page.state!=MEM_COMMIT){d->requested=4;goto done;}
  if(d->before_page.type!=MEM_PRIVATE){d->requested=5;goto done;}
  if(d->before_page.protect!=PAGE_READWRITE){d->requested=6;goto done;}
  if((uintptr_t)p->address+4< (uintptr_t)p->address||
     (uintptr_t)p->address+4>d->before_page.base+d->before_page.region_size){d->requested=7;goto done;}
  SIZE_T got=0;uint32_t now=0;
  BOOL read_ok=s->api.read(s->process,p->address,&now,4,&got);
  d->restore_index=now;d->status=(DWORD)got;
  if(!read_ok){d->requested=8;d->error=s->api.last_error();goto done;}
  if(got!=4){d->requested=9;goto done;}
  if(now!=p->before){d->requested=10;goto done;}
 }
''' +s[b:]
 s=s.replace('  const Guard*g=&s->guards[i];','  const Guard*g=&s->guards[i];d->stage=22;d->patch_index=i;d->address=(uintptr_t)g->address;d->size=g->size;')
 a=s.index(' SIZE_T got=0;uintptr_t now=0;');b=s.index(' result=1;',a)
 s=s[:a]+''' /* All exact guards and ALL old words passed while worker objects are
  * paused. No fallible API, game call, Lua callback, allocation or protection
  * transition occurs between the first and last aligned data store. */
 d->stage=23;
 __asm__ __volatile__("" ::: "memory");
 for(unsigned i=0;i<s->before;i++)*(volatile uint32_t*)patches[i].address=patches[i].after;
 __asm__ __volatile__("" ::: "memory");
 d->stage=24;
'''+s[b:]
 s=extend(s)
 (base/'one_two_source_publish.c').write_text(s,encoding='utf-8')
 builder=(base/'build_private_delta_publisher.py').read_text().replace('private_delta_publish','one_two_source_publish').replace('private-delta-publisher-build','one-two-source-publisher-build').replace("'-O2'","'-Os'")
 path=base/'_one_two_source_extract.py';path.write_text(builder,encoding='utf-8')
 spec=importlib.util.spec_from_file_location('one_two_source_extract',path);m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)
 result=m.build();result['derived_barrier_sha256']=hashlib.sha256((base/'private_delta_publish.c').read_bytes()).hexdigest()
 result['protection_codegen_sha256']=hashlib.sha256((base/'one_two_protection_codegen.py').read_bytes()).hexdigest()
 result.update(workspace_size=9216,maximum_source_pages=32,maximum_native_text=8192)
 assert len(bytes.fromhex(result['text_hex']))<=8192,'Native helper two-page bound'
 (base/'one-two-source-publisher-build.json').write_text(json.dumps(result,indent=2)+'\n')
 return result
if __name__=='__main__':
 r=build();print('PASS native extraction:',len(bytes.fromhex(r['text_hex'])),'bytes; no relocations/externals')
