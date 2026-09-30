-- HD2-Addon: mods/codex/plas1_scorcher_ar
local runtime = require('mods/codex/scorcher_ar_runtime')
local ok, why = runtime.register_profile({
    id = 'plas1_scorcher_ar',
    name = 'PLAS-1 Scorcher AR',
    hash = 'EEA5E3CEF1E12C14',
    values = {
        { hash = 'EEA5E3CEF1E12C14', id = 'capacity', value = 50 },
        { hash = 'EEA5E3CEF1E12C14', id = 'rpm', value = 540 },
        { hash = 'EEA5E3CEF1E12C14', id = 'damage', value = 75 },
        { hash = 'EEA5E3CEF1E12C14', id = 'durable', value = 38 },
        { hash = 'EEA5E3CEF1E12C14', id = 'blast_damage', value = 75 },
        { hash = 'EEA5E3CEF1E12C14', id = 'blast_durable', value = 75 },
        { hash = 'EEA5E3CEF1E12C14', id = 'blast_inner', value = 1.25 },
        { hash = 'EEA5E3CEF1E12C14', id = 'blast_outer', value = 2.5 },
        { hash = 'EEA5E3CEF1E12C14', id = 'mags_start', value = 4 },
        { hash = 'EEA5E3CEF1E12C14', id = 'mags_max', value = 6 },
        { hash = 'EEA5E3CEF1E12C14', id = 'recoil_dh', value = 15 },
        { hash = 'EEA5E3CEF1E12C14', id = 'recoil_dv', value = 15 },
        { hash = 'EEA5E3CEF1E12C14', id = 'recoil_ch', value = 1.5 },
        { hash = 'EEA5E3CEF1E12C14', id = 'recoil_cv', value = 15 }
    },
})
if not ok then error(why) end
return runtime
