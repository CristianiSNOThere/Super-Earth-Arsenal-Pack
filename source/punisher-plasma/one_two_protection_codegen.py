"""Bounded source-page protection extension of the retained native barrier."""
def extend(s):
 s=s.replace('typedef struct {HANDLE handles[MAX_THREADS];',
 '''typedef struct {uintptr_t address,allocation;DWORD old,attempted;} SourcePage;
typedef struct {HANDLE handles[MAX_THREADS];''')
 s=s.replace('BYTE states[MAX_THREADS];} Workspace;', 'BYTE states[MAX_THREADS];SourcePage pages[32];} Workspace;')
 s=s.replace('_Static_assert(offsetof(Workspace,diagnostic)==7376', '_Static_assert(sizeof(SourcePage)==24&&offsetof(Workspace,pages)==8064,"Source page workspace ABI");\n_Static_assert(offsetof(Workspace,diagnostic)==7376')
 s=s.replace('sizeof(Workspace)+15<=8208', 'sizeof(Workspace)+15<=9216')
 s=s.replace(' unsigned count=0,paused=0;', ' unsigned count=0,paused=0,page_count=0;SourcePage *pages=s->workspace->pages;')
 s=s.replace('  if(d->before_page.protect!=PAGE_READWRITE){d->requested=6;goto done;}',
 '''  if((d->before_page.protect!=PAGE_READWRITE&&d->before_page.protect!=PAGE_READONLY)||
     d->before_page.allocation_protect!=PAGE_READWRITE){d->requested=6;goto done;}
  uintptr_t page=(uintptr_t)p->address&~(uintptr_t)4095;
  if(page<d->before_page.base||page+4096<page||page+4096>d->before_page.base+d->before_page.region_size){d->requested=7;goto done;}
  if(d->before_page.protect==PAGE_READONLY){
   unsigned j=0;while(j<page_count&&pages[j].address!=page)j++;
   if(j==page_count){
    if(page_count==32){d->requested=11;goto done;}
    pages[j].address=page;pages[j].allocation=d->before_page.allocation;
    pages[j].old=PAGE_READONLY;pages[j].attempted=0;page_count++;
   }
  }''')
 # Insert only after every original-word/full-image guard has passed.
 at=s.index(' /* All exact guards and ALL old words passed')
 block=''' /* All original words/full images passed BEFORE any permission change.
  * Only exact private data pages from the source targets enter this list. */
 d->stage=25;d->restore_error=0;
 for(unsigned i=0;i<page_count;i++){
  SourcePage *p=&pages[i];d->patch_index=i;d->address=p->address;
  snapshot(s,(void*)p->address,&d->after_page);
  if(d->after_page.query_size!=sizeof(MEMORY_BASIC_INFORMATION)||
     d->after_page.allocation!=p->allocation||d->after_page.state!=MEM_COMMIT||
     d->after_page.type!=MEM_PRIVATE||d->after_page.protect!=PAGE_READONLY||
     p->address<d->after_page.base||p->address+4096>d->after_page.base+d->after_page.region_size)goto done;
  DWORD previous=0;p->attempted=1;
  if(!s->api.protect((void*)p->address,4096,PAGE_READWRITE,&previous)){
   d->error=s->api.last_error();goto done;
  }
  if(previous!=PAGE_READONLY){p->old=previous;goto done;}
  snapshot(s,(void*)p->address,&d->after_page);
  if(d->after_page.query_size!=sizeof(MEMORY_BASIC_INFORMATION)||
     d->after_page.allocation!=p->allocation||d->after_page.state!=MEM_COMMIT||
     d->after_page.type!=MEM_PRIVATE||d->after_page.protect!=PAGE_READWRITE)goto done;
 }
 /* Permission API interception may execute inside this thread: repeat ALL
  * immutable images and old words after transitions, before first store. */
 d->stage=26;
 for(unsigned i=0;i<s->guard_count;i++){
  const Guard*g=&s->guards[i];d->patch_index=i;
  for(unsigned o=0;o<g->size;o+=sizeof(bytes)){
   SIZE_T got=0,take=g->size-o;if(take>sizeof(bytes))take=sizeof(bytes);
   if(!s->api.read(s->process,g->address+o,bytes,take,&got)||got!=take)goto done;
   for(unsigned j=0;j<take;j++)if(bytes[j]!=g->expected[o+j])goto done;
  }
 }
 for(unsigned i=0;i<s->before;i++){
  snapshot(s,patches[i].address,&d->after_page);
  if(d->after_page.query_size!=sizeof(MEMORY_BASIC_INFORMATION)||
     d->after_page.state!=MEM_COMMIT||d->after_page.type!=MEM_PRIVATE||
     d->after_page.protect!=PAGE_READWRITE||
     (uintptr_t)patches[i].address+4>d->after_page.base+d->after_page.region_size)goto done;
  SIZE_T got=0;uint32_t now=0;
  if(!s->api.read(s->process,patches[i].address,&now,4,&got)||got!=4||now!=patches[i].before)goto done;
 }
'''
 s=s[:at]+block+s[at:]
 s=s.replace('done:\n d->count=count;', '''done:
 /* Restore attempted pages in reverse order BEFORE resuming any worker.
  * Failure is permanent even if source words were already committed. */
 for(unsigned i=page_count;i;i--){
  SourcePage*p=&pages[i-1];if(!p->attempted)continue;
  DWORD ignored=0;
  if(!s->api.protect((void*)p->address,4096,p->old,&ignored)){
   d->restore_error=s->api.last_error();d->restore_index=i-1;result=-27;continue;
  }
  snapshot(s,(void*)p->address,&d->after_page);
  if(d->after_page.query_size!=sizeof(MEMORY_BASIC_INFORMATION)||
     d->after_page.allocation!=p->allocation||d->after_page.state!=MEM_COMMIT||
     d->after_page.type!=MEM_PRIVATE||d->after_page.protect!=p->old){
   d->restore_error=0xffffffff;d->restore_index=i-1;result=-27;
  }
 }
 d->count=count;''')
 return s
