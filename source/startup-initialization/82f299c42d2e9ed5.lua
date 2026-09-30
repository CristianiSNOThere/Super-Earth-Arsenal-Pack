-- HD2-Addon: mods/codex/preset01_cqc20_breaching_hammer
local runtime = require('mods/codex/arsenal_preset01_runtime')
local ok, why = runtime.register_profile({
    id = 'preset01_cqc20_breaching_hammer',
    name = 'CQC-20 Breaching Hammer',
    hash = '5F3EC9BDA2BD8553',
    values = {
        { hash = '5F3EC9BDA2BD8553', id = 'blast_ap_direct', value = 7 },
        { hash = '5F3EC9BDA2BD8553', id = 'blast_ap_slight', value = 7 },
        { hash = '5F3EC9BDA2BD8553', id = 'blast_ap_large', value = 7 },
        { hash = '5F3EC9BDA2BD8553', id = 'mags_start', value = 21 },
        { hash = '5F3EC9BDA2BD8553', id = 'mags_supply', value = 21 },
        { hash = '5F3EC9BDA2BD8553', id = 'mags_max', value = 21 }
    },
})
if not ok then error(why) end
return runtime
