-- HD2-Addon: mods/codex/preset01_p34_breacher
local runtime = require('mods/codex/arsenal_preset01_runtime')
local ok, why = runtime.register_profile({
    id = 'preset01_p34_breacher',
    name = 'P-34 Breacher',
    hash = 'E91F569C2AD8AF01',
    values = {
        { hash = 'E91F569C2AD8AF01', id = 'mags_supply', value = 2 }
    },
})
if not ok then error(why) end
return runtime
