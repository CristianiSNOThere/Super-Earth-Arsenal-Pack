/* Private delta source-pointer transaction; no imports, allocation or Lua calls.
 * Conservative active-stack scan can defer installation on false positives.
 */
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <stdint.h>
#include <stddef.h>
#define MAX_THREADS 512
typedef struct {
 LONG (WINAPI *next_thread)(HANDLE,HANDLE,DWORD,DWORD,DWORD,HANDLE*);
 DWORD (WINAPI *thread_id)(HANDLE);
 DWORD (WINAPI *suspend)(HANDLE);
 DWORD (WINAPI *resume)(HANDLE);
 BOOL (WINAPI *context)(HANDLE,LPCONTEXT);
 VOID (WINAPI *capture)(PCONTEXT);
 SIZE_T (WINAPI *query)(LPCVOID,PMEMORY_BASIC_INFORMATION,SIZE_T);
 BOOL (WINAPI *read)(HANDLE,LPCVOID,LPVOID,SIZE_T,SIZE_T*);
 BOOL (WINAPI *protect)(LPVOID,SIZE_T,DWORD,PDWORD);
 BOOL (WINAPI *flush)(HANDLE,LPCVOID,SIZE_T);
 BOOL (WINAPI *close)(HANDLE);
 DWORD (WINAPI *last_error)(void);
 DWORD (WINAPI *wait)(HANDLE,DWORD);
 BOOL (WINAPI *same_object)(HANDLE,HANDLE);
} Api;
typedef struct {const uint8_t *address,*expected;uint32_t size;} Guard;
typedef struct {uint32_t *address;uint32_t before,after,size,reserved;} Patch;
_Static_assert(sizeof(Patch)==24,"Source patch ABI");
typedef struct {uintptr_t begin,end;} Range;
typedef struct {uintptr_t base,allocation,region_size;DWORD allocation_protect,state,protect,type,query_size,error;} PageSnapshot;
typedef struct {DWORD stage,status,thread_id,count,paused,error,wait_result,wait_error,terminated,last_terminated_id;
 DWORD patch_index,size,requested,restore_error,restore_index,resume_error;uintptr_t address,protect_api;
 PageSnapshot before_page,after_page;} Diagnostic;
typedef struct {uintptr_t address,allocation;DWORD old,attempted;} SourcePage;
typedef struct {HANDLE handles[MAX_THREADS];DWORD ids[MAX_THREADS];CONTEXT context;Diagnostic diagnostic;BYTE states[MAX_THREADS];SourcePage pages[32];} Workspace;
_Static_assert(sizeof(SourcePage)==24&&offsetof(Workspace,pages)==8064,"Source page workspace ABI");
_Static_assert(offsetof(Workspace,diagnostic)==7376,"Diagnostic ABI");
_Static_assert(sizeof(PageSnapshot)==48&&sizeof(Diagnostic)==176,"Page diagnostic ABI");
_Static_assert(offsetof(Workspace,states)==7552,"Thread state ABI");
_Static_assert(sizeof(Workspace)+15<=9216,"Workspace capacity");
typedef struct {
 Api api;HANDLE process;DWORD process_id,thread_id;
 uintptr_t *slot;uintptr_t before,after;
 const Guard *guards;uint32_t guard_count;
 Range busy[3];Workspace *workspace;
} Spec;
_Static_assert(sizeof(Spec)==224,"Private delta publication ABI");
_Static_assert(sizeof(Guard)==24,"Private delta guard ABI");
#define INLINE static __attribute__((always_inline)) inline
INLINE void snapshot(const Spec*s,const void*address,volatile PageSnapshot*out){
 MEMORY_BASIC_INFORMATION info;
 out->base=out->allocation=out->region_size=0;
 out->allocation_protect=out->state=out->protect=out->type=out->error=0;
 SIZE_T size=s->api.query(address,&info,sizeof(info));out->query_size=(DWORD)size;
 if(size!=sizeof(info)){out->error=s->api.last_error();return;}
 out->base=(uintptr_t)info.BaseAddress;out->allocation=(uintptr_t)info.AllocationBase;out->region_size=info.RegionSize;
 out->allocation_protect=info.AllocationProtect;out->state=info.State;out->protect=info.Protect;out->type=info.Type;
}
INLINE int busy_pc(uintptr_t p,const Spec*s){
 for(unsigned i=0;i<3;i++)if(p>=s->busy[i].begin&&p<s->busy[i].end)return 1;
 return 0;
}
INLINE int busy_stack(const Spec*s,const CONTEXT*c){
 if(busy_pc(c->Rip,s))return 1;
 MEMORY_BASIC_INFORMATION info;
 if(s->api.query((void*)c->Rsp,&info,sizeof(info))!=sizeof(info))return 1;
 if(info.State!=MEM_COMMIT||info.Type!=MEM_PRIVATE||info.Protect!=PAGE_READWRITE)return 1;
 uintptr_t p=c->Rsp,end=(uintptr_t)info.BaseAddress+info.RegionSize;
 if(end<p||end-p>0x200000)return 1;
 uintptr_t words[64];
 while(p<end){
  SIZE_T got=0,take=end-p;if(take>sizeof(words))take=sizeof(words);
  if(!s->api.read(s->process,(void*)p,words,take,&got)||got!=take)return 1;
  for(SIZE_T i=0;i<take/8;i++)if(busy_pc(words[i],s))return 1;
  p+=take;
 }
 return 0;
}
/* Return1 published;2 busy/retry; negative permanent failure.
 * All thread handles and suspension counts are unwound before returning.
 */
__attribute__((used)) int install(const Spec*s){
 HANDLE *handles=s->workspace->handles;DWORD *ids=s->workspace->ids;CONTEXT *context=&s->workspace->context;
 BYTE *states=s->workspace->states; /* 0 untouched,1 paused,2 confirmed terminated. */
 unsigned count=0,paused=0,page_count=0;SourcePage *pages=s->workspace->pages;
 /* Scalar volatile diagnostic stores avoid compiler-generated constant-pool
  * references; the extracted helper must remain relocation-free. */
 volatile Diagnostic *d=&s->workspace->diagnostic;
 d->stage=d->status=d->thread_id=d->count=d->paused=d->error=0;
 d->wait_result=WAIT_FAILED;d->wait_error=0;
 d->terminated=d->last_terminated_id=0;
 d->patch_index=d->size=d->requested=d->restore_error=d->restore_index=d->resume_error=0;d->address=0;
 d->protect_api=(uintptr_t)s->api.protect;
 volatile DWORD *page_words=(volatile DWORD*)&d->before_page;
 for(unsigned i=0;i<24;i++)page_words[i]=0;
 HANDLE cursor=NULL,previous=NULL,own=NULL;LONG status;
 int result=-1;
 for(;;){
  HANDLE h=NULL;status=s->api.next_thread(s->process,previous,THREAD_SUSPEND_RESUME|THREAD_GET_CONTEXT|THREAD_QUERY_INFORMATION|SYNCHRONIZE,0,0,&h);
  if(own){s->api.close(own);own=NULL;}
  if(status!=(LONG)0){if((uint32_t)status!=0x8000001a){d->stage=1;d->status=(DWORD)status;result=-11;goto done;}break;}
  previous=h;DWORD id=s->api.thread_id(h);if(!id){d->stage=2;d->error=s->api.last_error();result=-12;s->api.close(h);goto done;}
  if(id==s->thread_id){own=h;continue;}
  if(count==MAX_THREADS){d->stage=3;d->thread_id=id;result=-13;s->api.close(h);goto done;}
  handles[count]=h;ids[count]=id;states[count]=0;count++;
 }
 for(unsigned i=0;i<count;i++){
  if(s->api.suspend(handles[i])!=(DWORD)-1){states[i]=1;paused++;continue;}
  d->stage=4;d->thread_id=ids[i];d->error=s->api.last_error();result=-14;
  d->wait_result=s->api.wait(handles[i],0);
  if(d->wait_result==WAIT_FAILED)d->wait_error=s->api.last_error();
  if(d->wait_result!=WAIT_OBJECT_0)goto done;
  /* A held signaled thread object cannot execute again. Retain its handle
   * until cleanup, but never query its context or decrement its suspend count.
   * Every live/unknown failure still refuses, regardless of error or ID. */
  states[i]=2;d->terminated++;d->last_terminated_id=ids[i];
  d->stage=d->error=d->thread_id=0;d->wait_result=WAIT_FAILED;
 }
 result=2;
 /* Refuse threads created during the enumeration/suspension interval. */
 cursor=NULL;
 for(;;){
  HANDLE h=NULL;status=s->api.next_thread(s->process,cursor,THREAD_QUERY_INFORMATION|SYNCHRONIZE,0,0,&h);
  if(cursor)s->api.close(cursor);cursor=NULL;
  if(status!=(LONG)0){if((uint32_t)status!=0x8000001a)goto done;break;}
  cursor=h;DWORD id=s->api.thread_id(h);if(!id)goto done;
  if(id==s->thread_id)continue;
  DWORD wait=s->api.wait(h,0);
  if(wait==WAIT_OBJECT_0)continue; /* Independently proves THIS object ended. */
  if(wait!=WAIT_TIMEOUT){d->stage=5;d->thread_id=id;d->wait_result=wait;
   if(wait==WAIT_FAILED)d->wait_error=s->api.last_error();result=-15;goto done;}
  unsigned i=0;while(i<count&&ids[i]!=id)i++;
  /* IDs are only a lookup accelerator. An active thread must be the very
   * kernel object actually suspended, not a new object with a matching ID. */
  if(i==count||states[i]!=1||!s->api.same_object(handles[i],h))goto done;
 }
 for(unsigned i=0;i<count;i++){
  if(states[i]!=1)continue;
  context->ContextFlags=CONTEXT_CONTROL;
  if(!s->api.context(handles[i],context)||busy_stack(s,context))goto done;
 }
 s->api.capture(context);if(busy_stack(s,context))goto done;
 /* All live objects are held suspended and loader/teardown ranges are clear.
  * Caller must include root/source epoch, native code, owned projectile and
  * complete original/replacement image guards. Snapshot equality alone never
  * authorizes calling this helper. This helper does not own/free allocations.
  */
 result=-20;
 d->stage=20;
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
  if((d->before_page.protect!=PAGE_READWRITE&&d->before_page.protect!=PAGE_READONLY)||
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
  }
  if((uintptr_t)p->address+4< (uintptr_t)p->address||
     (uintptr_t)p->address+4>d->before_page.base+d->before_page.region_size){d->requested=7;goto done;}
  SIZE_T got=0;uint32_t now=0;
  BOOL read_ok=s->api.read(s->process,p->address,&now,4,&got);
  d->restore_index=now;d->status=(DWORD)got;
  if(!read_ok){d->requested=8;d->error=s->api.last_error();goto done;}
  if(got!=4){d->requested=9;goto done;}
  if(now!=p->before){d->requested=10;goto done;}
 }
 uint8_t bytes[256];SIZE_T total=0;
 for(unsigned i=0;i<s->guard_count;i++){
  const Guard*g=&s->guards[i];d->stage=22;d->patch_index=i;d->address=(uintptr_t)g->address;d->size=g->size;
  if(!g->address||!g->expected||!g->size||g->size>4096)goto done;
  total+=g->size;if(total>1048576)goto done;
  for(unsigned o=0;o<g->size;o+=sizeof(bytes)){
   SIZE_T got=0,take=g->size-o;if(take>sizeof(bytes))take=sizeof(bytes);
   if(!s->api.read(s->process,g->address+o,bytes,take,&got)||got!=take)goto done;
   for(unsigned j=0;j<take;j++)if(bytes[j]!=g->expected[o+j])goto done;
  }
 }
 /* All original words/full images passed BEFORE any permission change.
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
 /* All exact guards and ALL old words passed while worker objects are
  * paused. No fallible API, game call, Lua callback, allocation or protection
  * transition occurs between the first and last aligned data store. */
 d->stage=23;
 __asm__ __volatile__("" ::: "memory");
 for(unsigned i=0;i<s->before;i++)*(volatile uint32_t*)patches[i].address=patches[i].after;
 __asm__ __volatile__("" ::: "memory");
 d->stage=24;
 result=1;
done:
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
 d->count=count;d->paused=paused;
 for(unsigned i=count;i;i--)if(states[i-1]==1){if(s->api.resume(handles[i-1])==(DWORD)-1){d->resume_error=s->api.last_error();result=-6;}}
 while(count)s->api.close(handles[--count]);
 if(cursor)s->api.close(cursor);
 if(own)s->api.close(own);
 return result;
}
