# PLAS-39 Accelerator Rifle v1.1.9

## Current gameplay changes

Sets magazine capacity to 21, horizontal/vertical drift and camera recoil to 2, horizontal/vertical spread to 0.3, sway to 0.4, stagger to 25, direct-hit and blast armor penetration to 4, and outer blast/shockwave values to 2.5. Offers near-instant Semi fire at 200 RPM and charged three-round Burst with normal firing audio.

## Controls and compatibility

Hold R and use Weapon Wheel Left (default: left-click) in the left side of Weapon Functions. Semi fires one round with a 0.01-second minimum charge and 0.30-second spacing. Burst uses a 0.45-second minimum charge and three rounds spaced 0.12 seconds apart. Changes apply as you select and follow the game's remembered mode. Custom bindings use the native selector.

## Install

Import the ZIP into Arsenal and enable its option. Keep Bingus Shared Loader at its documented priority, Purge and Deploy, and restart Helldivers 2. Choose the individual packages or the modpack to avoid duplicate addon resources.

Requires Helldivers 2 Steam build 25480438 and Bingus Shared Loader v15 or newer.

## Initialization

Startup discovery limits work per frame and searches game data libraries. Weapon and sentry tuning waits for installed companion mods to finish initializing.


Semi and Burst now apply independently to each active rifle, including after switching weapons. Semi synchronizes its firing interval to 0.30 seconds. Burst fires three rounds and consumes three rounds.
