-- HD2-Addon: mods/codex/preset01_rs422_railgun
local runtime = require('mods/codex/arsenal_preset01_runtime')
local ok, why = runtime.register_profile({
    id = 'preset01_rs422_railgun',
    name = 'RS-422 Railgun',
    hash = '2E9D0BDC48B09E60',
    values = {
        { hash = '2E9D0BDC48B09E60', id = 'durable', value = 240 }
    },
})
if not ok then error(why) end
return runtime
