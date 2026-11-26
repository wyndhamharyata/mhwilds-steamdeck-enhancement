# Monster Hunter Wilds — Steam Deck Enhancement

A turnkey SteamOS package for Monster Hunter Wilds. One REFramework script replaces the separate performance mods tuned on a Steam Deck OLED. The installer also installs REFramework, OptiScaler (upscaler only), and MAKO FG (frame generation on the finished frame).

`VerRShape` and `WaistPhysics` are intentionally **not** part of this package.

## What you control in game

Open `Steam Deck Performance` in the REFramework menu:

| Setting | Default | Meaning |
|---|---:|---|
| Small monsters kept (%) | 25 | Share of small monsters left alive. Quest targets are never removed. EmID 38 is always kept. |
| Wildlife kept (%) | 25 | Share of ambient animals left alive. Useful animals (EmID 57–77) are always kept. |

Changes save immediately and apply to newly spawned enemies. Area changes reset the spawn sequence.

## Fixed performance profile

All values below are fixed in the mod. They are the measured setup from this Deck; no menu options were added for them.

- Static meshes beyond 150 m hidden; meshes attached to `MasterPlayer` are never hidden.
- Windward Plains yellow-grass cells beyond 100 m hidden; surrounding tall grass remains.
- Nearby foliage shadows on, far-cascade shadows off, foliage SDF within 60 m, voxel and envmap passes off.
- Fog starts at 30 m with density 0.65; volumetric fog stays enabled.
- Cloud raymarch steps drop from 128 to 32 only while the camera turns.
- Distant non-quest bosses update every 8 frames beyond 100 m.
- Zero-intensity time-of-day lights disabled; fill-light shadows off. Monster and effect lights untouched.

## Packaged in-game configuration

`config/config.ini` is the exact tested file. Key graphics values:

| Setting | Value |
|---|---|
| Upscaler selection | `Algorithm=DLSS` (OptiScaler override) |
| Upscaler quality | `Quality=Quality`, `UpscalingQuality=NativeAA` |
| Frame generation in game | `AlgorithmFG=NONE`, `EnableFrameGeneration=False` |
| Render resolution | unchanged |
| Texture quality | `TextureQuality=STANDARD`, `TextureLoadLevelBias=1` |
| Streaming texture quality | `StreamingTextureQuality=LOWEST` |
| Volumetric fog | enabled, `W54xH30xD32` |
| Shadow quality | `LOWEST` |
| Ground / mesh | `LOWEST` / `STANDARD` |
| Ambient / GI | `LOW`, DPGI `LOW` |
| Wind simulation | `OFF` |
| Foliage density | `0.5`, culling near 10 m / far 90 m |
| Grass culling | `NEAREST` |
| SpeedTree LOD | 3, small-object culling 32, shadow LOD bias 2 |

The packager copies the supporting `reframework/data/*.json` files verbatim, including the current object-culling level **7**, mesh LOD bias **1**, SpeedTree LOD bias **3**, fog tweak and post-processing settings.

## Frame generation

Frame generation uses **MAKO FG 5.0.0**, a free-for-non-commercial-use Vulkan layer that works on the finished presented image. It requires neither game motion vectors nor paid Lossless Scaling.

- MAKO profile: `MonsterHunterWilds.exe`, 2x, Balanced, flow scale 0.8.
- OptiScaler is forced to `FGInput=nofg`, `FGOutput=nofg`, so FG never stacks.
- An existing LSFG installation is detected and reported, but is never used or downloaded.

See [FRAME_GENERATION.md](FRAME_GENERATION.md).

## Install

On the Steam Deck, in Desktop Mode:

```sh
git clone https://github.com/wyndhamharyata/mhwilds-steamdeck-enhancement.git
cd mhwilds-steamdeck-enhancement
chmod +x install.sh
./install.sh
```

The script downloads pinned REFramework, MAKO Renderer and OptiScaler releases from GitHub, installs the consolidated Lua mod, writes the measured configuration, and prints the Steam launch option:

```text
WINEDLLOVERRIDES="amdxc64=n,b;dinput8=n,b;dxgi=n,b" ~/.local/bin/mako-launch %command%
```

Paste that into **Steam → Properties → General → Launch Options**. Then start the game once and press **Reset Scripts** in REFramework.

### Third-party Nexus mods

The following scripts are dependencies of the measured setup and are **not redistributed** here. On a fresh install, pass their Nexus zips to the installer; existing installations are left alone.

```sh
./install.sh \
  --more-graphics ~/Downloads/More_Graphics_Options.zip \
  --dithering ~/Downloads/FuckYourDithering.zip \
  --post-fx ~/Downloads/Disable_Post_Processing_Effects.zip \
  --fog ~/Downloads/Volumetric_Fog_Tweak.zip
```

Sources:

- [More graphics options](https://www.nexusmods.com/monsterhunterwilds/mods/816)
- [FuckYourDithering](https://www.nexusmods.com/monsterhunterwilds/mods/3650)
- [Disable Post Processing Effects](https://www.nexusmods.com/monsterhunterwilds/mods/221)
- [Tweak volumetric fog(s)](https://www.nexusmods.com/monsterhunterwilds/mods/455)

Use `--game-dir` if Steam is installed elsewhere and `--offline` to reuse cached downloads.

## What the installer touches

- `dinput8.dll`, OptiScaler `dxgi.dll` and its supporting DLLs in the game folder.
- `config.ini` and `OptiScaler.ini` in the game folder.
- `reframework/autorun/SteamDeckEnhancement.lua`.
- Retires the old `TurnTrim.lua`, `GrassTrim.lua`, `FarThrottle.lua`, `LightTrim.lua` and `ReduceZako.lua` into the installer backup folder.
- `reframework/data/*.json` for the graphics, fog and post-processing mods.
- `~/.local/bin` and `~/.local/share/mako-render` through MAKO's own installer.
- `~/.config/mako-render/conf.toml`.

Original files are copied to `~/.local/share/mhwilds-enhancement/backups/<timestamp>/` before replacement.

To restore the previous state, close the game, copy that backup folder's files back, and remove `SteamDeckEnhancement.lua`. Run MAKO's **Uninstall MAKO Renderer** if you no longer want its Vulkan layer.

## Checks

```sh
tests/validate.sh
```

## License

The consolidated Lua mod, installer and documentation in this repository are MIT licensed. Upstream projects keep their own licenses; see [THIRD_PARTY.md](THIRD_PARTY.md).
