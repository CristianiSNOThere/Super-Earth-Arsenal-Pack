-- Native adapter for the independently verified source-pointer transaction.
-- Caller supplies current, exact-build discovery and all factory/ownership
-- guards. This does not discover a game, create a child or change ammo state.
local ffi=require('ffi')
ffi.cdef[[
typedef struct {void *next_thread,*thread_id,*suspend,*resume,*context,*capture,*query,*read,*protect,*flush,*close,*last_error,*wait,*same_object;} PunisherDeltaApi037;
typedef struct {const void *address,*expected;uint32_t size;} PunisherDeltaGuard037;
typedef struct {uint64_t begin,end;} PunisherDeltaRange037;
typedef struct {PunisherDeltaApi037 api;void *process;uint32_t process_id,thread_id;
 void *slot;uint64_t before,after;const PunisherDeltaGuard037 *guards;uint32_t guard_count;
 PunisherDeltaRange037 busy[3];void *workspace;} PunisherDeltaSpec037;
void *VirtualAlloc(void *,size_t,uint32_t,uint32_t);
int VirtualProtect(void *,size_t,uint32_t,uint32_t *);
int FlushInstructionCache(void *,const void *,size_t);
void *GetCurrentProcess(void);uint32_t GetCurrentProcessId(void);
uint32_t GetCurrentThreadId(void);uint32_t GetThreadId(void *);
uint32_t GetLastError(void);uint32_t WaitForSingleObject(void *,uint32_t);
uint32_t SuspendThread(void *);uint32_t ResumeThread(void *);
int GetThreadContext(void *,void *);void RtlCaptureContext(void *);
size_t VirtualQuery(const void *,void *,size_t);
int ReadProcessMemory(void *,const void *,void *,size_t,size_t *);
int CloseHandle(void *);int CompareObjectHandles(void *,void *);
int32_t NtGetNextThread(void *,void *,uint32_t,uint32_t,uint32_t,void **);
uint8_t RtlAddFunctionTable(void *,uint32_t,uint64_t);
]]
assert(ffi.sizeof('PunisherDeltaSpec037')==224,'Delta publisher ABI mismatch')
local function pointer(p)local b=ffi.new('uintptr_t[1]',ffi.cast('uintptr_t',p));return ffi.string(b,8)end
local function word(v)local b=ffi.new('uint32_t[1]',v);return ffi.string(b,4)end
