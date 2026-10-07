# Startup initialization source

These Lua sources contain the initialization code shipped in the current packages. Hexadecimal filenames identify addon resource hashes; runtime.lua is compiled with the game LuaJIT compiler. Stable resource identifiers are retained for loader compatibility.

The Python scripts preserve the local workspace patch workflow and depend on its expanded-stat-editor archive and runtime builders. They are not a self-contained repository build system. Earlier source builders may still generate the old initialization code; use these published resource sources when maintaining future builds.

## Rule for new mods

Every new individual mod and matching mega pack addition must use the current compatibility startup contract from these published sources, including bounded companion waits, named failures, exact supported peer-order validation, and fail-closed rollback. Give mod-specific resources distinct keys; any shared key must carry byte-identical payloads across packages. Check the new ZIP against the complete current individual set for resource collisions and startup-order cases, then verify a fresh startup. Keep Shared Loader Lua in a pure-Lua archive. Loading and startup checks do not establish gameplay behavior for every combination.
