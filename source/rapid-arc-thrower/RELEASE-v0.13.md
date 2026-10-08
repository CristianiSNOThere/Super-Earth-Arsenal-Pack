# ARC-3 Rapid/Supercharge v0.13

Adds the native Auto/Rapid and Semi/Supercharge fire-mode selector. Rapid charges in 0.307692/0.338462/0.369231 seconds and uses 0.85x of the shared 226/90 normal/durable pulse damage (about 192.1/76.5 before armor and hit location). Supercharge charges in 4.9/5.0/5.25 seconds, uses dedicated 1550/1550 damage, targets one enemy (chain 1, split 0), and cannot explode from overcharge. Both modes keep stock ARC audio and 45 m reach.

## Fire modes

Hold R to open Weapon Functions and select **Auto** for Rapid or **Semi** for Supercharge. Mode switching uses the native selector and applies the selected profile to newly created ARC instances after they become idle. Rapid keeps the shared DamageInfo197 row at 226/90 for compatibility, then uses a 0.85 charge multiplier. Supercharge uses its own DamageInfo547 at 1550 normal / 1550 durable, 1.0 charge multiplier, Stun Medium 12 and Stun Massive 25. Rapid keeps Stun Medium 1.2 and the existing handling changes (demolition 4, force 25, impulse 2, camera climb 0.4/0.4). Armor penetration stays at 7.

Supercharge's 5-second charge is intentional. The stock charge sound can finish before the shot is ready; earlier audio experiments were removed. Both modes use the original ARC sounds.

## Optional companion mods

Enable **Arc Thrower Revamped** in CowboyBingus's Vanilla Plus Megapack for hold-to-fire. This package preserves its supported auto-fire flag. [Bingus Shared Loader](https://www.nexusmods.com/helldivers2/mods/16292) v18 or newer is required.

Optional: [WeakPoint Lock-On All-In-One 3.0](https://ayakamods.com/mods/weakpoint-lock-on-v2.3981/) by potatoman7676 has a selectable **Titan Head** lock-on option. ARC attacks use the game's lock-on points; selecting that option can help Supercharge hit a Bile Titan's head. Install it separately and select the options you want. Head hits and one-shot kills still depend on target, range, and actual hit routing. Avoid the package's Disable Lock-On options for ARC weapons.

## Install and validation

Requires the supported Helldivers 2 Steam build 25480438. Replace the prior ARC-3 ZIP in Arsenal, Purge/Deploy, and restart the game. Use individual packages **or** the full modpack, never both. Keep deployment and settings under your control.

The v0.22l gameplay payload was user-confirmed working on 8 October 2026 with Bingus Shared Loader v19. The v0.13 release packages use that exact ARC payload. Offline Lua, archive, identity, and resource-composition checks passed. The new release ZIPs themselves have not been separately started in game. A clean Bile Titan head shot is a possible damage breakpoint, not a guaranteed one-shot.
