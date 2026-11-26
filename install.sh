#!/usr/bin/env bash
# Turnkey installer for Monster Hunter Wilds on SteamOS/Steam Deck.
set -euo pipefail

SOURCE="${BASH_SOURCE[0]:-$0}"
ROOT="$(cd -- "$(dirname -- "$SOURCE")" && pwd -P)"
STATE="${HOME}/.local/share/mhwilds-enhancement"
GAME_DIR="${MHWILDS_DIR:-${HOME}/.steam/steam/steamapps/common/MonsterHunterWilds}"

DOWNLOADS=1

usage() {
  cat <<'EOF'
Usage: install.sh [options]

  --game-dir DIR       MonsterHunterWilds directory
  --offline            Skip GitHub downloads; use cached files in ~/.local/share/mhwilds-enhancement/cache
  --help               Show this help

No paid frame generator is downloaded or enabled.
EOF
}

log() { printf '[mhwilds-enhancement] %s\n' "$*"; }
die() { printf '[mhwilds-enhancement] ERROR: %s\n' "$*" >&2; exit 1; }

while [ "$#" -gt 0 ]; do
  case "$1" in
    --game-dir) GAME_DIR="$2"; shift 2 ;;
    --offline) DOWNLOADS=0; shift ;;
    --help) usage; exit 0 ;;
    *) die "Unknown option: $1" ;;
  esac
done

# A piped curl install has no local checkout. Fetch the packaged files once.
if [ ! -f "$ROOT/autorun/SteamDeckEnhancement.lua" ] || [ ! -f "$ROOT/config/config.ini" ]; then
  mkdir -p "$STATE/repo"
  curl -fsSL -o "$STATE/repo/main.tar.gz" \
    https://github.com/wyndhamharyata/mhwilds-steamdeck-enhancement/archive/refs/heads/main.tar.gz
  tar -xzf "$STATE/repo/main.tar.gz" -C "$STATE/repo"
  ROOT="$STATE/repo/mhwilds-steamdeck-enhancement-main"
fi

for tool in curl tar unzip 7z python3; do command -v "$tool" >/dev/null 2>&1 || die "Missing required tool: $tool"; done
[ -d "$GAME_DIR" ] || die "Game directory not found: $GAME_DIR"
[ -f "$GAME_DIR/MonsterHunterWilds.exe" ] || die "Not a Monster Hunter Wilds directory: $GAME_DIR"
if ps -eo comm 2>/dev/null | grep -qi '^MonsterHunter'; then die "Close Monster Hunter Wilds before installing"; fi

AUTORUN="$GAME_DIR/reframework/autorun"
DATA="$GAME_DIR/reframework/data"
PLUGINS="$GAME_DIR/reframework/plugins"
CACHE="$STATE/cache"
BACKUP="$STATE/backups/$(date +%Y%m%d-%H%M%S)"
mkdir -p "$AUTORUN" "$DATA" "$PLUGINS" "$CACHE" "$BACKUP" "$HOME/.config/mako-render"
log "Game: $GAME_DIR"
log "Backup: $BACKUP"

github_asset() {
  local repo="$1" name="$2" tag="${3:-latest}" json url
  if [ "$tag" = latest ]; then
    json="$(curl -fsSL "https://api.github.com/repos/${repo}/releases/latest")"
  else
    json="$(curl -fsSL "https://api.github.com/repos/${repo}/releases/tags/${tag}")"
  fi
  url="$(printf '%s' "$json" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(next((a["browser_download_url"] for a in d["assets"] if a["name"]==sys.argv[1]), ""))' "$name")"
  [ -n "$url" ] || die "Could not find release asset $name in $repo"
  printf '%s' "$url"
}

fetch() {
  local url="$1" file="$2"
  if [ -s "$CACHE/$file" ]; then log "Cached: $file"; return; fi
  log "Downloading $file"
  curl -fL --retry 3 -o "$CACHE/$file.part" "$url"
  mv "$CACHE/$file.part" "$CACHE/$file"
}

backup_if_present() {
  local path="$1"
  if [ -e "$path" ]; then cp -a "$path" "$BACKUP/$(basename "$path")"; fi
}

if [ "$DOWNLOADS" -eq 1 ]; then
  reframework_url="$(github_asset praydog/REFramework-nightly REFramework.zip)"
  fetch "$reframework_url" REFramework.zip
  fetch "https://github.com/eugeniosegala/MAKO/releases/download/render-v5.0.0/MAKO-Renderer-v5.0.0-linux.tar.xz" MAKO-Renderer-v5.0.0-linux.tar.xz
  opti_url="$(github_asset optiscaler/OptiScaler Optiscaler_0.9.5-final.20261116.7z v0.9.5)"
  fetch "$opti_url" OptiScaler.7z
fi

log "Installing REFramework"
unzip -p "$CACHE/REFramework.zip" dinput8.dll > "$GAME_DIR/dinput8.dll.tmp"
mv "$GAME_DIR/dinput8.dll.tmp" "$GAME_DIR/dinput8.dll"

if command -v 7z >/dev/null 2>&1; then
  log "Installing OptiScaler as upscaler only"
  rm -rf "$STATE/optiscaler"
  mkdir -p "$STATE/optiscaler"
  7z x -y -o"$STATE/optiscaler" "$CACHE/OptiScaler.7z" >/dev/null
  opti_dll="$(find "$STATE/optiscaler" -name OptiScaler.dll -print -quit)"
  [ -n "$opti_dll" ] || die "OptiScaler.dll missing from downloaded archive"
  opti_root="$(dirname "$opti_dll")"
  cp -f "$opti_root/OptiScaler.dll" "$GAME_DIR/dxgi.dll"
  for dll in amd_fidelityfx_dx12.dll amd_fidelityfx_upscaler_dx12.dll amd_fidelityfx_framegeneration_dx12.dll amd_fidelityfx_vk.dll libxess.dll libxess_dx11.dll nvngx.dll nvapi64.dll d3dcompiler_47.dll; do
    [ -f "$opti_root/$dll" ] && cp -f "$opti_root/$dll" "$GAME_DIR/$dll"
  done
else
  log "7z not found; keeping existing OptiScaler files. Install 7z to update them."
fi

log "Installing MAKO Renderer 5.0.0"
rm -rf "$STATE/mako"
mkdir -p "$STATE/mako"
tar -xJf "$CACHE/MAKO-Renderer-v5.0.0-linux.tar.xz" -C "$STATE/mako"
MAKO_INSTALLER_ASSUME_YES=1 MAKO_INSTALLER_NO_LAUNCH=1 "$STATE/mako/Install MAKO Renderer"

cat > "$HOME/.config/mako-render/conf.toml" <<'EOF'
version = 2

[global]
allow_fp16 = true

[[profile]]
name = "Monster Hunter Wilds"
active_in = ["MonsterHunterWilds.exe"]
frame_generation_provisioned = true
frame_generation_enabled = true
frame_generation_model = "mako-fg"
mako_fg_mode = "balanced"
multiplier = 2
flow_scale = 0.8
scaling_enabled = false
adaptive = false
base_fps_cap = 0
EOF

log "Installing consolidated REFramework mod"
for old in TurnTrim.lua GrassTrim.lua FarThrottle.lua LightTrim.lua ReduceZako.lua; do
  if [ -e "$AUTORUN/$old" ]; then
    mv -f "$AUTORUN/$old" "$BACKUP/$old"
    log "Retired merged script: $old"
  fi
done
cp -f "$ROOT/autorun/SteamDeckEnhancement.lua" "$AUTORUN/SteamDeckEnhancement.lua"

log "Installing measured configuration"
backup_if_present "$GAME_DIR/config.ini"
backup_if_present "$GAME_DIR/OptiScaler.ini"
cp -f "$ROOT/config/config.ini" "$GAME_DIR/config.ini"
cp -f "$ROOT/config/OptiScaler.ini" "$GAME_DIR/OptiScaler.ini"
for json in SteamDeckEnhancement.json; do
  backup_if_present "$DATA/$json"
  cp -f "$ROOT/config/$json" "$DATA/$json"
done

if [ -d "$HOME/.local/share/fsr-switch/cyboman" ]; then
  python3 - "$HOME/.local/share/fsr-switch/cyboman" "$GAME_DIR/OptiScaler.ini" <<'PY'
import pathlib, sys
folder = pathlib.Path(sys.argv[1])
ini = pathlib.Path(sys.argv[2])
text = ini.read_text(errors="surrogateescape")
for key, name in (("FfxDx12Path", "amd_fidelityfx_dx12.dll"),
                  ("FfxDx12SRPath", "amd_fidelityfx_upscaler_dx12.dll"),
                  ("FfxDx12FGPath", "amd_fidelityfx_framegeneration_dx12.dll")):
    path = folder / name
    if path.exists():
        windows = "Z:" + str(path).replace("/", "\\")
        lines = []
        for line in text.splitlines(keepends=True):
            if line.startswith(key + " = "):
                line = f"{key} = {windows}\n"
            lines.append(line)
        text = "".join(lines)
ini.write_text(text, errors="surrogateescape")
PY
  log "Linked optional cyboman FSR 4.1.2 Lite files"
else
  log "cyboman FSR files not found; OptiScaler will use its bundled FFX files"
fi

if [ -e "$HOME/lsfg" ] || [ -d "$HOME/homebrew/plugins/decky-lsfg-vk" ]; then
  log "LSFG detected but intentionally unused; MAKO FG is the frame generator"
else
  log "No LSFG detected; no paid software is required"
fi

LAUNCH='WINEDLLOVERRIDES="amdxc64=n,b;dinput8=n,b;dxgi=n,b" ~/.local/bin/mako-launch %command%'
printf '%s\n' "$LAUNCH" > "$STATE/launch-options.txt"
patched=0
for vdf in "$HOME"/.local/share/Steam/userdata/*/config/localconfig.vdf; do
  [ -f "$vdf" ] || continue
  backup_if_present "$vdf"
  if python3 "$ROOT/steam-launch-options.py" "$vdf" "$LAUNCH"; then patched=1; fi
done
if [ "$patched" -eq 0 ]; then
  log "Could not edit Steam launch options automatically. Set them manually to: $LAUNCH"
fi
log "Done. Restart Steam once so it reads the launch options."
log "Start the game, then press Reset Scripts in REFramework."
