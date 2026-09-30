-- HD2-Addon: mods/codex/preset01_s11_speargun
local runtime = require('mods/codex/arsenal_preset01_runtime')
local ok, why = runtime.register_profile({
    id = 'preset01_s11_speargun',
    name = 'S-11 Speargun',
    hash = '3828E2051AA9E897',
    values = {
        { hash = '3828E2051AA9E897', id = 'mags_supply', value = 10 },
        { hash = '3828E2051AA9E897', id = 'mags_start', value = 16 },
        { hash = '3828E2051AA9E897', id = 'mags_max', value = 20 },
        { hash = '3828E2051AA9E897', id = 'ergonomics', value = 40 }
    },
})
if not ok then error(why) end
return runtime
