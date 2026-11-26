# Monster Hunter Wilds — Steam Deck Enhancement

All-in-One solution for best experience with Monster Hunter Wilds on Steam Deck. It is not only for the sake of frame rate, but also the best visual while targeting stable 30 FPS. 

## Install

Switch to desktop mode, then open terminal (Konsole) and run the following script:

```sh
curl -fsSL https://github.com/wyndhamharyata/mhwilds-steamdeck-enhancement/raw/refs/heads/main/install.sh | bash
```

It will download and install all of the necessary components for the mod to work. Including:
- REFramework
- OptiScaler
- MAKO FG
- cyboman FSR 4.1.2 Lite Lossy upscaler

It will also update the Steam launch option automatically.

## Strongly recommended: Nexus object culling

One of the key features of this mod is aggressive selective culling. Using the Nexus DLL culler is strongly recommended for more selective culling and better visual coverage. The built-in culler remains available as a fallback. During installation of the script above, it asks for the **More graphics options** ZIP. You can leave it blank only if you want the built-in fallback (though not very good). 

To install it manually instead:

1. Download **More graphics options** manually from [Nexus Mods](https://www.nexusmods.com/monsterhunterwilds/mods/816).
2. From the ZIP, copy `reframework/plugins/object_culling.dll` and `reframework/autorun/More graphics options.lua` into the matching folders in the game directory. Create `plugins` if needed.
3. Launch the game. In the **More graphics options** REFramework menu, set environmental object culling to **7**. Leave its other graphics overrides disabled so they do not fight this preset.

When `object_culling.dll` is present, the built-in mesh culler turns itself off. 

## In-game controls

Open `Steam Deck Performance` in the REFramework menu.

| Setting | Default |
|---|---:|
| Small monsters kept (%) | 25 |
| Wildlife kept (%) | 25 |

Quest targets and useful endemic life are never removed. Changes save immediately.

## What the preset does

- Target certain render resolution, texture quality and volumetric fog.
- Applies the tested sharpness, vignette, shadow resolution and mesh/SpeedTree LOD values.
- Reduces distant foliage, grass, mesh, light and shadow work.
- Keeps nearby savannah grass visible.
- Uses MAKO FG for smooth displayed motion. It does not raise the game's real FPS.
- OptiScaler is used for the upscaling, with the cyboman FSR 4.1.2 Lite Lossy DLL.

## Options

-`--game-dir PATH` — use a non-default game install path.
-`--more-graphics ZIP` — install the strongly recommended Nexus object culler without prompting.
-`--offline` — reuse files already cached by a previous install.

## Uninstall

1. Close the game.
2. Delete `SteamDeckEnhancement.lua` from `reframework/autorun`.
3. Copy files back from `~/.local/share/mhwilds-enhancement/backups/<timestamp>/` if you want the previous settings.
4. Remove MAKO Renderer from its application menu if you no longer want frame generation.
5. Remove the launch option from Steam.

## Support

Run `tests/validate.sh` to check the package files.

Third-party licenses and credits are in [THIRD_PARTY.md](THIRD_PARTY.md).
