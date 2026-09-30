-- HD2-Addon: mods/codex/preset01_apw1_anti_materiel_rifle
local runtime = require('mods/codex/arsenal_preset01_runtime')
local ok, why = runtime.register_profile({
    id = 'preset01_apw1_anti_materiel_rifle',
    name = 'APW-1 Anti-Materiel Rifle',
    hash = '89C5493E08CA4207',
    values = {
        { hash = '89C5493E08CA4207', id = 'ergonomics', value = 40 }
    },
})
if not ok then error(why) end
return runtime
