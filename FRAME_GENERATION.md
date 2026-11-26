# Frame generation

This package uses **MAKO FG**, not OptiScaler frame generation and not paid Lossless Scaling.

MAKO is a Vulkan layer that generates frames from the finished presented picture, including the HUD. It does not need game engine motion vectors and does not require Lossless Scaling for its own FG model.

- Upstream: https://github.com/eugeniosegala/MAKO
- License: GPL-3.0-or-later
- Pinned renderer: `render-v5.0.0`
- Profile: `MonsterHunterWilds.exe`, MAKO FG, 2x, Balanced, flow scale 0.8, scaling off

OptiScaler remains installed as the **upscaler only**. Its packaged `OptiScaler.ini` sets `FGInput = nofg` and `FGOutput = nofg`, so the two frame generators cannot stack.

The installer checks for an existing paid LSFG setup and prints a warning, but never downloads, requires or enables it.
