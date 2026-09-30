-- HD2-Addon: mods/codex/preset01_agm17_gas_mortar_sentry
local runtime = require('mods/codex/arsenal_preset01_runtime')
local ok, why = runtime.register_profile({
    id = 'preset01_agm17_gas_mortar_sentry',
    name = 'A/GM-17 Gas Mortar Sentry',
    hash = '299C0D3DFD2F0994',
    values = {
        { hash = '299C0D3DFD2F0994', id = 'unit_health', value = 600 }
    },
})
if not ok then error(why) end
return runtime
