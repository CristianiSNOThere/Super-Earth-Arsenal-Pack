# Accelerator Rifle mode isolation candidate — 30 September 2026

The released synchronizer enumerated all WeaponData instances, including dropped rifles. Opposite selections on a common source charge row caused its conflict guard to refuse the entire transaction. Live checks confirmed an equipped Burst instance still read minimum charge 0.01 seconds and repetition count zero. The native three-note audio could therefore disagree with physical firing.

The candidate enumerates the owned WeaponCharge prefix, which the exact-build native update at `0x73c948` actually advances. It joins each active charge entity to WeaponData by ID and verifies both entity references. Dropped and unowned WeaponData instances no longer select local firing settings. Enumeration is bounded by active charge instances rather than all world weapon entities.

Each active rifle receives separate charge and projectile component overrides in existing native storage. This preserves the source charge/projectile rows and allows distinct active selections. No native function is called, no executable code is modified, no allocator is introduced, and no new projectile or damage ID is added. Registration copies the existing component row, prepares reverse indexes, updates the used count, and publishes the forward indexes through the existing verified data transaction. Failed writes roll back. Existing cached index zero is supported. Capacity exhaustion or changed entities/managers/maps refuse the transaction.

## Exact-build native evidence

- Charge getter `0x5052c0`: entity-ID map at manager `+0x50`, 216-byte rows at `+0x90`; source fallback is `0x504d80`.
- Charge initialization `0x73edb8`: 32 component override rows allocated; capacity at `+4`, used count `+0x88`, reverse map `+0x70`. The live manager reported capacity 32 and used count zero.
- Charge teardown `0x73f6ca` onward removes the forward/reverse entries, decrements used count, copies the last row to fill a hole and updates both indexes. This occurs on the owned entity removal branch used by the candidate.
- Projectile getter `0x515100`: entity-ID map `+0x90`, 616-byte rows `+0xd0`. Initialization `0x6194f6` onward allocates 128 rows with capacity `+0x30`; used count is `+0xc8`, reverse map `+0xb0`.
- Projectile override creation `0x61af10` copies the source component into a temporary, registers both indexes and copies all 616 bytes into the native cache. Candidate registration uses this row/index contract without invoking its property-patch interface or allocating memory.
- Projectile teardown `0x61a099` onward removes/compacts the same cache contract.
- Generic map insertion `0x172f790` writes the index before the key and does not maintain a hidden size counter. Deletion `0x172f8a0` clears the key and shifts the subsequent probe chain. The offline cleanup fixture models this algorithm; it does not execute native gameplay cleanup.
- Firing routine `0x6128b0` calls the instance-aware projectile getter at `0x612a13` and `0x6140a4`; the charge-release routine calls the instance-aware charge getter at `0x73d97d`.

Disassembly files and `native_cache_audit.py` reside alongside this document. Input is the saved, hash-verified supported-build code snapshot. `build.py` includes additional runtime byte guards for these cache paths. Supported EXE and DLL hashes are also checked before package generation and by startup in game.

## Validation and limits

`verify_modes.py` passes the original mode-value, queued-shot cancellation, rollback, native resolver and startup callback tests. `verify_isolation.py` runs the actual resolved Lua modules in the game's LuaJIT in a separate offline process. It verifies mixed active Semi/Burst instances, ignored dropped/unowned entities, source-row preservation, zero writes on unchanged frames, failed initial cache-publication rollback, independent mode switching, both index maps, modeled native erase/compaction, pickup, capacity and stale-manager refusal.

The candidate changes only the existing PLAS-39 implementation resource in each current package. Stable Arsenal GUIDs, option names and all other addon resources are retained. Current gameplay tuning remains Semi 200 RPM/minimum charge 0.01 s/zero repetitions and Burst 550 RPM setting/minimum charge 0.45 s/two extra releases spaced 0.12 s, with the mode-specific audio flags. Burst consumes three rounds; Semi consumes one. The candidate keeps the source profile's magazine, handling, damage and blast settings.

No fixed candidate has been installed or observed in game yet. Native registration/cleanup, physical shots/ammo, audio, repeated pickup and multiplayer behavior still require gameplay validation. No hot-reload claim is made; installation requires restart. Punisher work remains paused. Its future modes should use scoped instance settings rather than changing shared projectile rows per selection; pellet count/spread and separate per-pellet explosion behavior still require their own implementation and testing.
# Cadence correction, v1.1.8

User mission test of v1.1.7: Semi emits one round, but its fire rate remains too high. Read-only PID 27296 snapshot (`live-semi-cadence-20260930.json`) finds component RPM 200 and native projectile state +12 = 0.109090909 seconds (60/550). The prior log described only component RPM and did not validate the derived interval.

Exact-build initialization 0x611bb3 resolves the entity state using manager +0x50 map, +0x78 rows, stride 168. At 0x611c4c..0x611c69 it computes 60 / (RPM * native multiplier), storing interval +12. At 0x612cf8..0x612d07 firing adds that interval to remaining cooldown +8. Charge release at 0x73ce52..0x73ce7e checks cooldown +8 before firing. This supports synchronizing the derived interval without altering the live countdown. State +100 is unrelated and is not modified.

v1.1.8 joins each owned rifle to its projectile state, verifies the state map index and matching entity reference, and stages +12 alongside component RPM. Accepted interval words are float32(60/550) or float32(60/200); other values refuse the transaction. Semi uses 0.30 seconds; Burst restores 60/550 while retaining its separate 0.12-second charge repetitions. Existing native modifiers with other intervals are conservatively refused. Native code guards cover initialization, state lookup, cooldown accumulation and charge cooldown gate. No remaining-cooldown or unrelated state writes.

Offline tests pass for both modes, distinct active instances, index zero, preserved unrelated state/countdown, no unchanged-frame writes, cadence-write rollback, unexpected interval refusal and mismatched state owner refusal, plus prior lifecycle/compaction tests. These are offline checks, not a measured gameplay cadence or a confirmed Burst result.

