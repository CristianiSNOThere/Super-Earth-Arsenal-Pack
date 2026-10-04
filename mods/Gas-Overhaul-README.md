# Gas Overhaul v0.12

Gas weapons now apply the Acid Storm effect, temporarily reducing enemy armor effectiveness for 15 seconds. Extends the Sterilizer's existing effect to AX/TX-13 Guard Dog Dog Breath, P-35 Re-Educator, S-11 Speargun, G-4 Gas grenades, MD-8 Gas Mines, A/GM-17 Gas Mortar Sentry, Eagle Gas Airstrike and Orbital Gas Strike. Armor plates are not permanently destroyed.

## Stock → modded values

| Setting | Stock | Gas Overhaul |
|---|---|---|
| Acid Storm armor-reduction effect on supported gas hits | Not applied | Applied for 15 seconds |
| Shared Acid Storm duration | 1 second | 15 seconds |
| Shared gas damage over time, normal / durable | 25 / 25 DPS | 45 / 45 DPS |
| TX-41 Sterilizer magazine capacity | 125 rounds | 175 rounds |
| Sterilizer Gas MKII buildup per hit | 0.5 | 0.75 |
| Sterilizer gas confusion buildup per hit | 0.5 | 0.75 |
| Helldiver incoming gas damage multiplier | 1.3 | 0.7333 |

The 45 DPS gas damage is shared by ordinary gas and Sterilizer/Dog Breath gas, including gas grenades and shared gas hazards. It is not limited to those two weapons. The incoming gas multiplier applies to all gas sources, including grenades and hazards; 0.7333 is about 43.6% less incoming gas damage than the stock 1.3 multiplier. The shared Acid Storm duration also affects the weather status after the storm ends.

Compared with Sterilizer v0.11, this release adds armor reduction to the other supported gas weapons. Existing damage, magazine size, incoming gas protection and Sterilizer buildup are retained. Dog Breath and the newly covered weapons retain their existing direct damage, armor penetration, force and gas/confusion buildup values. Gas Mortar sentry health changes belong to the separate sentry mod.

## Install and compatibility

Replaces TX-41 Sterilizer Armor Control. Import this ZIP into Arsenal, enable its option, keep Bingus Shared Loader at its documented priority, Purge and Deploy, then restart Helldivers 2. Use either individual packages or the combined modpack. Do not enable Gas Overhaul alongside an older Sterilizer package or a modpack that already contains it.

Requires Helldivers 2 Steam build 25480438 and Bingus Shared Loader v18 or newer. Supports the existing ARC-3 Rapid Arc Thrower v0.9, v0.10 and v0.11 balances during initialization. Companion checks, exact data validation and rollback remain in place. Allow up to two minutes after reaching the ship for initialization.

## Validation

The user confirmed the test candidate works in gameplay on 4 October 2026. Offline packaged Lua, exact data/companion checks, refusal and rollback fixtures, ZIP integrity and modpack composition checks passed. Release gameplay code and all Addon files are byte-for-byte identical to that accepted candidate. This confirmation does not establish exhaustive testing of every gas source or compatibility with every third-party mod.
