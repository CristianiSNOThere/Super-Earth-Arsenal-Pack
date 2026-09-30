-- HD2-Addon: mods/codex/preset01_40k_meltagun
local runtime = require('mods/codex/arsenal_preset01_runtime')
local ok, why = runtime.register_profile({
    id = 'preset01_40k_meltagun',
    name = '40-K Meltagun',
    hash = '6CFCC7F8801A0266',
    values = {
        { hash = '6CFCC7F8801A0266', id = 'ergonomics', value = 40 }
    },
})
if not ok then error(why) end
return runtime
