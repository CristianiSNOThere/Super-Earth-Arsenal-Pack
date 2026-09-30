# Startup initialization source

These Lua sources contain the initialization code shipped in the current packages. Hexadecimal filenames identify addon resource hashes; runtime.lua is compiled with the game LuaJIT compiler. Stable resource identifiers are retained for loader compatibility.

The Python scripts preserve the local workspace patch workflow and depend on its expanded-stat-editor archive and runtime builders. They are not a self-contained repository build system. Earlier source builders may still generate the old initialization code; use these published resource sources when maintaining future builds.
