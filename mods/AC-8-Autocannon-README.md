# AC-8 Autocannon Backpackless Rework v1.0.0

The AC-8 is now a self-contained support weapon. Its call-in pod delivers the Autocannon without the Automatic Cannon Backpack, leaving the backpack slot free. You can reload the gun yourself without carrying that backpack.

## Ammunition and reload

- The gun keeps its familiar 10-round internal feed and five-round top-clip reload. It carries 60 reserve rounds for **70 rounds total** when full.
- You can walk while reloading. The reload retains the Autocannon's top-loading animation, with walking motion instead of the sliding pose from the first test.
- Self-reload is about **20% faster** than the original three-second reload setting.
- A resupply is set to restore up to **60 reserve rounds**, capped by the weapon's reserve capacity. Ordinary ammo pickups follow the game's own refill rules.

## APHET and FLAK

Use the Autocannon's normal Weapon Functions selector to switch between APHET and FLAK.

| Mode | Change |
| --- | --- |
| APHET | Direct damage increases from 325 normal / 260 durable to **375 normal / 340 durable**. Direct armor penetration rises from AP4 to **AP5**. Impact explosion normal damage rises from 150 to **180**. |
| FLAK | Explosion normal damage rises from 190 to **210**, and its outer blast radius grows from 7 to **8 metres**. The parent round remains 150 normal / 150 durable, and shrapnel remains unchanged. |

**Shared effect:** JAR-5 Dominator **High Explosive ammunition** uses the same explosion as AC-8 FLAK. Its explosion also receives the **210 normal damage and 8 m outer radius**. The JAR-5's other ammunition is not part of this change.

## Install and validation

Requires the supported Helldivers 2 Steam build 25480438 and Bingus Shared Loader v19. Import this ZIP into Arsenal, enable its option, Purge and Deploy, then restart the game. Use either this individual package or the complete Super Earth Arsenal Mod Pack; do not enable both.

The user confirmed the backpackless weapon, mobile self-reload, and corrected walking animation in an individual-package mission. The 18-mod test pack passed a fresh startup with the AC-8 and key companions applied. The v1.0.0 release ZIP contains the same gameplay resources as the tested v0.1e package. APHET/FLAK damage outcomes, every reload stage, external-backpack team reload, and multiplayer behavior have not been separately measured in gameplay.
