# Weapon and Sentry Mods

Nine Arsenal mods, each with settings for exactly one weapon or sentry. Enable any combination of these packages.

For one package containing all 15 mods, see the [Super-Earth Arsenal Modpack](https://github.com/CristianiSNOThere/Super-Earth-Arsenal-Modpack). Choose the complete pack or individual packages, not both.

## Packages

| Package | Settings | SHA-256 |
|---|---|---|
| [ARC-12 Blitzer](Preset-01-01-arc12_blitzer-v1.0.0.zip) | `durable=45`, `damage=100`, `arc_range=30`, `arc_rpm=80` | `AE77B1BD4667086DF3D06B057F5F2B1FC18C270255536042E91732DDDC489491` |
| [CQC-20 Breaching Hammer](Preset-01-02-cqc20_breaching_hammer-v1.0.0.zip) | `blast_ap_direct=7`, `blast_ap_slight=7`, `blast_ap_large=7`, `mags_start=21`, `mags_supply=21`, `mags_max=21` | `3C7B2BD0CED7A0F7B9414B6EE2242A0D12AFAB042E22B8D525C59793FEC397CD` |
| [PLAS-39 Accelerator Rifle](PLAS-39-Accelerator-Rifle-v1.1.5.zip) | Semi at 200 RPM or charged three-round Burst via the left-side selector; `capacity=21`, `recoil_dh=2`, `recoil_ch=2`, `recoil_dv=2`, `recoil_cv=2`, `spread_h=0.3`, `spread_v=0.3`, `sway=0.4`, `stagger=25`, `ap_direct=4`, `ap_slight=4`, `ap_large=4`, `blast_outer=2.5`, `blast_shockwave=2.5` | `20EB78D66D382835C9FA1DEB03EE8486FE9DDD94AB3003E07462AA91C93DFB97` |
| [P-34 Breacher](Preset-01-04-p34_breacher-v1.0.0.zip) | `mags_supply=2` | `AB04A955D1C0A1CD45FCBB5F52DDD4371322A8E6A48E54B42FEE6A97FC841ADE` |
| [S-11 Speargun](Preset-01-05-s11_speargun-v1.0.0.zip) | `mags_supply=10`, `mags_start=16`, `mags_max=20`, `ergonomics=40` | `2F3DA21D288570D532277168D5640081E9FEB6ED19D4C83DC1D811F171F25F90` |
| [APW-1 Anti-Materiel Rifle](Preset-01-06-apw1_anti_materiel_rifle-v1.0.0.zip) | `ergonomics=40` | `0016F420B167FB0C6E47D1F45DCBFAC70D17FA7D748D8FFBB8143118A936F8DE` |
| [40-K Meltagun](Preset-01-07-40k_meltagun-v1.0.0.zip) | `ergonomics=40` | `546CE76F424435FFB07DFD8517AD865D55FB1DBFAD569C6E12673EDF5A183420` |
| [A/GM-17 Gas Mortar Sentry](Preset-01-08-agm17_gas_mortar_sentry-v1.0.0.zip) | `unit_health=600` | `D436B27FEAF4E987E2C7CD5A8D5FB3CFEA5E19A0313081832EEC1CD77CAE5738` |
| [RS-422 Railgun](Preset-01-09-rs422_railgun-v1.0.0.zip) | `durable=240` | `6B4F52FEBEDBBFD567E2CFEFDDE4012334DDCAE4E5A0379E1E36D96572B1F08A` |

## Held back

- **MLS-4X Commando `cooldown=100`** is not packaged. The current extracted build data has no exact StratagemSettings source/stock record for its cooldown, so there is no safe stock-value conflict check.

## Shared runtime and conflicts

Every package contains the same namespaced runtime libraries. When multiple packages are enabled, the loader reuses one scanner, and each weapon's settings are applied in a separate atomic transaction. At launch the runtime waits 30 seconds for installed package modules, then waits up to two minutes for detected Flag, SAI, AR-11, Sterilizer, and ARC-3 modules to report Applied. A failed companion causes the weapon and sentry mods to write nothing. Existing editor config values that overlap these fields must be disabled by the user; the fixed packages fail closed when they find a changed source value.

PLAS-39 also synchronizes its firing mode with the native Weapon Functions selection. See [PLAS-39 details](PLAS-39-Accelerator-Rifle-README.md) for controls and installation.
