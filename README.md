# Monster Hunter Wilds — Steam Deck Enhancement

One installer and one REFramework mod for SteamOS. It sets up the game's graphics preset, installs free frame generation, and gives you two in-game sliders for enemy and wildlife density.

## Install

In Desktop Mode:

```sh
curl -fsSL https://github.com/wyndhamharyata/mhwilds-steamdeck-enhancement/raw/refs/heads/main/install.sh | bash
```

The installer fetches its own files, so no checkout is needed.

The installer downloads and installs REFramework, OptiScaler and MAKO FG, then writes the Steam launch option automatically. Restart Steam once so it reads the change.

Launch the game and press **Reset Scripts** in REFramework.

## Strongly recommended: Nexus object culling

The Nexus DLL culler is strongly recommended for more selective culling and better visual coverage. The built-in culler remains available as a fallback. The installer asks for the **More graphics options** ZIP; leave it blank only if you want the built-in fallback. For a non-interactive install, pass `--more-graphics /path/to/mod.zip`.

To install it manually instead:

1. Download **More graphics options** manually from [Nexus Mods](https://www.nexusmods.com/monsterhunterwilds/mods/816).
2. From the ZIP, copy `reframework/plugins/object_culling.dll` and `reframework/autorun/More graphics options.lua` into the matching folders in the game directory. Create `plugins` if needed.
3. Launch the game. In the **More graphics options** REFramework menu, set environmental object culling to **7**. Leave its other graphics overrides disabled so they do not fight this preset.
4. Press **Reset Scripts**.

When `object_culling.dll` is present, the built-in mesh culler turns itself off. Delete the DLL to return to the built-in culler. The installer never downloads Nexus files.

## In-game controls

Open `Steam Deck Performance` in the REFramework menu.

| Setting | Default |
|---|---:|
| Small monsters kept (%) | 25 |
| Wildlife kept (%) | 25 |

Quest targets and useful animals are never removed. Changes save immediately.

## What the preset does

- Keeps the render resolution, texture quality and volumetric fog.
- Applies the tested sharpness, vignette, shadow resolution and mesh/SpeedTree LOD values.
- Reduces distant foliage, grass, mesh, light and shadow work.
- Keeps nearby savannah grass visible.
- Uses MAKO FG for smooth displayed motion. It does not raise the game's real FPS.
- OptiScaler is used only for upscaling. Paid Lossless Scaling is not required.

## Options

- `--game-dir PATH` — use a non-default game install path.
- `--more-graphics ZIP` — install the strongly recommended Nexus object culler without prompting.
- `--offline` — reuse files already cached by a previous install.

## Uninstall

1. Close the game.
2. Delete `SteamDeckEnhancement.lua` from `reframework/autorun`.
3. Copy files back from `~/.local/share/mhwilds-enhancement/backups/<timestamp>/` if you want the previous settings.
4. Remove MAKO Renderer from its application menu if you no longer want frame generation.
5. Remove the launch option from Steam.

## Support

Run `tests/validate.sh` to check the package files.

Third-party licenses and credits are in [THIRD_PARTY.md](THIRD_PARTY.md).
