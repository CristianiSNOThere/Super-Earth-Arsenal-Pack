-- Exact stock records -> pre-creation profiles. No native state edits.
local ffi=require('ffi')
local function word(v)local b=ffi.new('uint32_t[1]',v);return ffi.string(b,4)end
local function float(v)local b=ffi.new('float[1]',v);return ffi.string(b,4)end
local function change(s,o,v)return s:sub(1,o)..v..s:sub(o+#v+1)end
return function(rows,modes,stock,reload_template)
 local baseline=modes.build(stock,2,171,'tuning-v014',0.5,true,120)
 local pellet=modes.build(stock,3,171,'tuning-v014',0.5,true,120)
 local out={}
 for _,r in ipairs(rows)do
  local s=r.before
  if r.role=='parent_weapon' then
   s=baseline.weapon
   -- First three entries belong to the fire-mode menu. Native underbarrel
   -- selection is the separate fourth enum through function11.
   s=change(s,144,word(2)..word(0)..word(0)..word(8))
   -- Native function11 reads these parent-owned display fields for its two LEFT choices.
   s=change(s,160,string.char(0xa7,0x0d,0x93,0x91,0xc0,0xe4,0xd9,0x07,0xbb,0x6b,0x89,0x2f,0x96,0xb0,0x7b,0x06))
   s=change(s,176,word(0xf3222616)..word(0xff4b018d)) -- stock localized NORMAL / SHOTGUN
   s=change(s,184,word(11)..word(0)) -- preserve LEFT underbarrel dispatch; remove redundant right Semi
  elseif r.role=='parent_projectile' then s=change(baseline.projectile,8,float(60)) -- final normal cadence only
  elseif r.role=='parent_magazine' then s=change(s,136,word(17)..word(1)..word(1)..word(1)) -- capacity/start/refill/max:17 loaded + one spare17 magazine
  elseif r.role=='parent_customization' then
   assert(s:sub(17,24)==string.rep('\0',8),'Default customization slot occupied')
   s=change(s,16,word(1)..word(0xa051bf6b))
   s=change(s,192,string.char(0xf5,0x45,0x84,0xcd,0x21,0x73,0xcd,0x02))
   s=change(s,4852,word(2))
  elseif r.role=='child_weapon' then
   s=change(s,0,pellet.weapon:sub(1,60))
   s=change(s,84,float(100)..float(90));s=change(s,140,word(1))
   local b=ffi.new('float[1]');ffi.copy(b,s:sub(105,108),4)
   assert(b[0]>=0 and b[0]<=100,'Unexpected child sway');s=change(s,104,pellet.weapon:sub(105,108))
   s=change(s,132,pellet.weapon:sub(133,133))
  elseif r.role=='child_projectile' then
   -- Whole accepted pellet firing profile; donor unit/reload stay native.
   s=pellet.projectile
  elseif r.role=='child_rounds' then
   s=change(s,64,word(171));s=change(s,72,float(20))
   s=change(s,80,word(60)..word(60)..word(60));s=change(s,104,string.char(0))
  elseif r.role=='child_reload' then
   assert(type(reload_template)=='string' and #reload_template==80,'Missing exact reload template')
   -- Copy only known working multi-round underbarrel ability + normal/fast animation-event sequence.
   -- Preserve One-Two flags, duration, shared-deposit and VO.
   s=change(s,4,reload_template:sub(5,56))
   s=change(s,56,float(121/60)) -- coupled native animation/timeline speed2x
  else error('Unknown source target')end
  assert(#s==#r.before and #s%4==0,'Source record size changed')
  out[#out+1]={role=r.role,before=r.before,after=s,owner=r.owner,offset=r.offset,
   count=r.count,index=r.index,stride=r.stride}
 end
 assert(#out==8,'Incomplete source profile')
 return out
end
