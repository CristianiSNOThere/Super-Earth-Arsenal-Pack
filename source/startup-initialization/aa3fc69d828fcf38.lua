-- HD2-Addon: mods/codex/preset01_arc12_blitzer
local runtime = require('mods/codex/arsenal_preset01_runtime')
local ok, why = runtime.register_profile({
    id = 'preset01_arc12_blitzer',
    name = 'ARC-12 Blitzer',
    hash = '076DD5D4F4360204',
    values = {
        { hash = '076DD5D4F4360204', id = 'durable', value = 45 },
        { hash = '076DD5D4F4360204', id = 'damage', value = 100 },
        { hash = '076DD5D4F4360204', id = 'arc_range', value = 30 },
        { hash = '076DD5D4F4360204', id = 'arc_rpm', value = 80 }
    },
})
if not ok then error(why) end
return runtime
