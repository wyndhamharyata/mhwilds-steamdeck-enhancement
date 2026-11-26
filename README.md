# Monster Hunter Wilds — Steam Deck Enhancement

One installer and one REFramework mod for SteamOS. It sets up the game's graphics preset, installs free frame generation, and gives you two in-game sliders for enemy and wildlife density.

## Install

In Desktop Mode:

```sh
curl -fsSL https://github.com/wyndhamharyata/mhwilds-steamdeck-enhancement/raw/refs/heads/main/install.sh | bash
```

The installer fetches its own files, so no checkout is needed.

The installer downloads and installs REFramework, OptiScaler and MAKO FG. It prints the launch option when it finishes. Paste that into:

**Steam → Properties → General → Launch Options**

Then launch the game once and press **Reset Scripts** in REFramework.

## In-game controls

Open `Steam Deck Performance` in the REFramework menu.

| Setting | Default |
|---|---:|
| Small monsters kept (%) | 25 |
| Wildlife kept (%) | 25 |

Quest targets and useful animals are never removed. Changes save immediately.

## What the preset does

- Keeps the render resolution, texture quality and volumetric fog.
- Reduces distant foliage, grass, mesh, light and shadow work.
- Keeps nearby savannah grass visible.
- Uses MAKO FG for smooth displayed motion. It does not raise the game's real FPS.
- OptiScaler is used only for upscaling. Paid Lossless Scaling is not required.

## Options

- `--game-dir PATH` — use a non-default game install path.
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
