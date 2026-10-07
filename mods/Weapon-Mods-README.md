# Weapon and Sentry Mods

Nine Arsenal mods, each with settings for exactly one weapon or sentry. Enable any combination of these packages.

For one package containing all 17 mods, see the [Super-Earth Arsenal Modpack](https://github.com/CristianiSNOThere/Super-Earth-Arsenal-Modpack). Choose the complete pack or individual packages, not both.

## Packages

| Package | Settings | SHA-256 |
|---|---|---|
| [ARC-12 Blitzer](ARC-12-Blitzer-v1.0.2.zip) | `durable=45`, `damage=100`, `arc_range=30`, `arc_rpm=80` | `1C976146F1A2CC943ECA1FBB2670B5742F0183E107EF7DF959FA32FA0F070245` |
| [CQC-20 Breaching Hammer](CQC-20-Breaching-Hammer-v1.0.2.zip) | `blast_ap_direct=7`, `blast_ap_slight=7`, `blast_ap_large=7`, `mags_start=21`, `mags_supply=21`, `mags_max=21` | `7D353744ABA3EE9FEA485E79D38241AB8C8EDB8F848B48E092989F19D9C65864` |
| [PLAS-39 Accelerator Rifle](PLAS-39-Accelerator-Rifle-v1.1.9.zip) | Semi at 200 RPM or charged three-round Burst via the left-side selector; `capacity=21`, `recoil_dh=2`, `recoil_ch=2`, `recoil_dv=2`, `recoil_cv=2`, `spread_h=0.3`, `spread_v=0.3`, `sway=0.4`, `stagger=25`, `ap_direct=4`, `ap_slight=4`, `ap_large=4`, `blast_outer=2.5`, `blast_shockwave=2.5` | `B6E948CE4BF19CC8233C35B0DBD9BBD5DB9AFAC96F745E71A61AE505C8624A41` |
| [P-34 Breacher](P-34-Breacher-v1.0.2.zip) | `mags_supply=2` | `AE082F88BF9D88C06566CCE00AD44A11F1FF72F7409DDDEED039BD2D578D9F3A` |
| [S-11 Speargun](S-11-Speargun-v1.0.2.zip) | `mags_supply=10`, `mags_start=16`, `mags_max=20`, `ergonomics=40` | `269A096F6DDD9CA4C08C59B5C8CA2B60D2BD569763DA72A6072F615DBFED18F7` |
| [APW-1 Anti-Materiel Rifle](APW-1-Anti-Materiel-Rifle-v1.0.2.zip) | `ergonomics=40` | `03625AA29494CE31C44298EFB9EEC569E79F29EE9633B6F8FBD89BD657FA7AEF` |
| [40-K Meltagun](40-K-Meltagun-v1.0.2.zip) | `ergonomics=40` | `170CD390F8CF9F2FE0962D610F9C7DE5A97F2739E2750F62D1AE471FEF90ABD2` |
| [A/GM-17 Gas Mortar Sentry](A-GM-17-Gas-Mortar-Sentry-v1.0.2.zip) | `unit_health=600` | `72C016DB151FEAB3D48DD8298F6852D93AA24C41B7C3BAFBEB7691EB62B252C9` |
| [RS-422 Railgun](RS-422-Railgun-v1.0.2.zip) | `durable=240` | `92390F10B9C4E67AAC70013AD6B2C42B56794B1EAB782608B7BD6A2D5AB78FE0` |

## Held back

- **MLS-4X Commando `cooldown=100`** is not packaged. The current extracted build data has no exact StratagemSettings source/stock record for its cooldown, so there is no safe stock-value conflict check.

## Shared runtime and conflicts

Every package contains the same namespaced runtime libraries. When multiple packages are enabled, the loader reuses one scanner, and each weapon's settings are applied in a separate atomic transaction. At launch the runtime waits 30 seconds for installed package modules, then continues waiting for detected Flag, SAI, AR-11, Sterilizer, and ARC-3 modules to report Applied. A detected companion that never reports Applied causes a named failure after 120 seconds; no profile values are written. Existing editor config values that overlap these fields must be disabled by the user; the fixed packages fail closed when they find a changed source value.

PLAS-39 also synchronizes its firing mode with the native Weapon Functions selection. See [PLAS-39 details](PLAS-39-Accelerator-Rifle-README.md) for controls and installation.
