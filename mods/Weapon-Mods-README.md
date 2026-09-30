# Weapon and Sentry Mods

Nine Arsenal mods, each with settings for exactly one weapon or sentry. Enable any combination of these packages.

For one package containing all 16 mods, see the [Super-Earth Arsenal Modpack](https://github.com/CristianiSNOThere/Super-Earth-Arsenal-Modpack). Choose the complete pack or individual packages, not both.

## Packages

| Package | Settings | SHA-256 |
|---|---|---|
| [ARC-12 Blitzer](ARC-12-Blitzer-v1.0.1.zip) | `durable=45`, `damage=100`, `arc_range=30`, `arc_rpm=80` | `1024081BED4ED1F94FE29604E23B8EEBE69558053BA938CEF87FA454390D7BA6` |
| [CQC-20 Breaching Hammer](CQC-20-Breaching-Hammer-v1.0.1.zip) | `blast_ap_direct=7`, `blast_ap_slight=7`, `blast_ap_large=7`, `mags_start=21`, `mags_supply=21`, `mags_max=21` | `28ACAC11AE061DDA2443C92F39B6309E7FC9BE224DAC5279F5E91FBCBEFD24BC` |
| [PLAS-39 Accelerator Rifle](PLAS-39-Accelerator-Rifle-v1.1.8.zip) | Semi at 200 RPM or charged three-round Burst via the left-side selector; `capacity=21`, `recoil_dh=2`, `recoil_ch=2`, `recoil_dv=2`, `recoil_cv=2`, `spread_h=0.3`, `spread_v=0.3`, `sway=0.4`, `stagger=25`, `ap_direct=4`, `ap_slight=4`, `ap_large=4`, `blast_outer=2.5`, `blast_shockwave=2.5` | `8B7ACDBFA76428B81CBFE7FA9F9BF97D6955836EED2C03E4E28FEEEAB7B83CEA` |
| [P-34 Breacher](P-34-Breacher-v1.0.1.zip) | `mags_supply=2` | `6045EA853FD1783B38F85A2C233148A7E4FD685BFD2A49F138A03AE3B14987BF` |
| [S-11 Speargun](S-11-Speargun-v1.0.1.zip) | `mags_supply=10`, `mags_start=16`, `mags_max=20`, `ergonomics=40` | `4DA01071A445B3834D573C9583E9267FB8FB121B523D60E34B281AD3972A2723` |
| [APW-1 Anti-Materiel Rifle](APW-1-Anti-Materiel-Rifle-v1.0.1.zip) | `ergonomics=40` | `F8CBE132852D3FD41300F251E9BBF47C5215F159A2CFAC8FBCB09E18B86285D7` |
| [40-K Meltagun](40-K-Meltagun-v1.0.1.zip) | `ergonomics=40` | `9A39CC58CABB1DEB15AA211B3AD347FB271E0E5BF09DB2DB2FC12E67DACBFA7D` |
| [A/GM-17 Gas Mortar Sentry](A-GM-17-Gas-Mortar-Sentry-v1.0.1.zip) | `unit_health=600` | `C8E16CBB1F8849796DA8B1A6841EE8C63C3BF2467F1EC2D2195B0BF11309D56E` |
| [RS-422 Railgun](RS-422-Railgun-v1.0.1.zip) | `durable=240` | `37AD387D2B1E4B96285DDF7AFB58142D75DCDD02EE281334DA75A085D8D2873C` |

## Held back

- **MLS-4X Commando `cooldown=100`** is not packaged. The current extracted build data has no exact StratagemSettings source/stock record for its cooldown, so there is no safe stock-value conflict check.

## Shared runtime and conflicts

Every package contains the same namespaced runtime libraries. When multiple packages are enabled, the loader reuses one scanner, and each weapon's settings are applied in a separate atomic transaction. At launch the runtime waits 30 seconds for installed package modules, then continues waiting for detected Flag, SAI, AR-11, Sterilizer, and ARC-3 modules to report Applied. A failed companion causes the weapon and sentry mods to write nothing. Existing editor config values that overlap these fields must be disabled by the user; the fixed packages fail closed when they find a changed source value.

PLAS-39 also synchronizes its firing mode with the native Weapon Functions selection. See [PLAS-39 details](PLAS-39-Accelerator-Rifle-README.md) for controls and installation.
