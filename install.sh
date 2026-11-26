#!/usr/bin/env bash
# Turnkey installer for Monster Hunter Wilds on SteamOS/Steam Deck.
set -euo pipefail

SOURCE="${BASH_SOURCE[0]:-$0}"
ROOT="$(cd -- "$(dirname -- "$SOURCE")" && pwd -P)"
STATE="${HOME}/.local/share/mhwilds-enhancement"
GAME_DIR="${MHWILDS_DIR:-${HOME}/.steam/steam/steamapps/common/MonsterHunterWilds}"
FSR_DIR="${HOME}/.local/share/fsr-switch/cyboman"
LAUNCH='WINEDLLOVERRIDES="amdxc64=n,b;dinput8=n,b;dxgi=n,b" ~/.local/bin/mako-launch %command%'

IS_DOWNLOAD_ENABLED=1
MORE_GRAPHICS_ZIP=""

print_usage() {
  cat <<'EOF'
Usage: install.sh [options]

  --game-dir DIR       MonsterHunterWilds directory
  --more-graphics ZIP  Strongly recommended More graphics options Nexus ZIP
  --offline            Skip GitHub downloads; use cached files in ~/.local/share/mhwilds-enhancement/cache
  --help               Show this help

No paid frame generator is downloaded or enabled.
EOF
}

log() { printf '[mhwilds-enhancement] %s\n' "$*"; }
die() { printf '[mhwilds-enhancement] ERROR: %s\n' "$*" >&2; exit 1; }

parse_arguments() {
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --game-dir)
        GAME_DIR="$2"
        shift 2
        ;;
      --more-graphics)
        MORE_GRAPHICS_ZIP="$2"
        shift 2
        ;;
      --offline)
        IS_DOWNLOAD_ENABLED=0
        shift
        ;;
      --help)
        print_usage
        exit 0
        ;;
      *)
        die "Unknown option: $1"
        ;;
    esac
  done
}

# A piped curl install has no local checkout. Fetch the packaged files once.
fetch_packaged_files() {
  if [ -f "$ROOT/autorun/SteamDeckEnhancement.lua" ] && [ -f "$ROOT/config/config.ini" ]; then

    return
  fi

  mkdir -p "$STATE/repo"
  curl -fsSL -o "$STATE/repo/main.tar.gz" \
    https://github.com/wyndhamharyata/mhwilds-steamdeck-enhancement/archive/refs/heads/main.tar.gz
  tar -xzf "$STATE/repo/main.tar.gz" -C "$STATE/repo"
  ROOT="$STATE/repo/mhwilds-steamdeck-enhancement-main"
}

check_requirements() {
  for tool in curl tar unzip 7z python3; do
    command -v "$tool" >/dev/null 2>&1 || die "Missing required tool: $tool"
  done

  [ -d "$GAME_DIR" ] || die "Game directory not found: $GAME_DIR"
  [ -f "$GAME_DIR/MonsterHunterWilds.exe" ] || die "Not a Monster Hunter Wilds directory: $GAME_DIR"

  if ps -eo comm 2>/dev/null | grep -qi '^MonsterHunter'; then
    die "Close Monster Hunter Wilds before installing"
  fi
}

setup_directories() {
  AUTORUN="$GAME_DIR/reframework/autorun"
  DATA="$GAME_DIR/reframework/data"
  PLUGINS="$GAME_DIR/reframework/plugins"
  CACHE="$STATE/cache"
  BACKUP="$STATE/backups/$(date +%Y%m%d-%H%M%S)"

  mkdir -p "$AUTORUN" "$DATA" "$PLUGINS" "$CACHE" "$BACKUP" "$HOME/.config/mako-render"
  log "Game: $GAME_DIR"
  log "Backup: $BACKUP"
}

find_release_asset_url() {
  local repository="$1"
  local asset_name="$2"
  local release_tag="$3"
  local release_json download_url

  if [ "$release_tag" = latest ]; then
    release_json="$(curl -fsSL "https://api.github.com/repos/${repository}/releases/latest")"
  else
    release_json="$(curl -fsSL "https://api.github.com/repos/${repository}/releases/tags/${release_tag}")"
  fi

  download_url="$(printf '%s' "$release_json" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(next((a["browser_download_url"] for a in d["assets"] if a["name"]==sys.argv[1]), ""))' "$asset_name")"
  [ -n "$download_url" ] || die "Could not find release asset $asset_name in $repository"

  printf '%s' "$download_url"
}

download_file() {
  local download_url="$1"
  local file_name="$2"

  if [ -s "$CACHE/$file_name" ]; then
    log "Cached: $file_name"

    return
  fi

  log "Downloading $file_name"
  curl -fL --retry 3 -o "$CACHE/$file_name.part" "$download_url"
  mv "$CACHE/$file_name.part" "$CACHE/$file_name"
}

backup_if_present() {
  local file_path="$1"

  if [ -e "$file_path" ]; then
    cp -a "$file_path" "$BACKUP/$(basename "$file_path")"
  fi
}

download_assets() {
  if [ "$IS_DOWNLOAD_ENABLED" -ne 1 ]; then

    return
  fi

  local reframework_url optiscaler_url cyboman_url
  reframework_url="$(find_release_asset_url praydog/REFramework-nightly REFramework.zip latest)"
  optiscaler_url="$(find_release_asset_url optiscaler/OptiScaler Optiscaler_0.9.5-final.20261116.7z v0.9.5)"
  cyboman_url="$(find_release_asset_url zgauthier2000/fsr4-shader-performance-overrides fsr4.1.2-igpu-cyboman-rdna2-2026-11-22.7z dll-2026-11-22)"

  download_file "$reframework_url" REFramework.zip
  download_file "https://github.com/eugeniosegala/MAKO/releases/download/render-v5.0.0/MAKO-Renderer-v5.0.0-linux.tar.xz" MAKO-Renderer-v5.0.0-linux.tar.xz
  download_file "$optiscaler_url" OptiScaler.7z
  download_file "$cyboman_url" CybomanFSR.7z
}

install_nexus_culler() {
  if [ -z "$MORE_GRAPHICS_ZIP" ] && [ -t 1 ]; then
    printf 'Strongly recommended More graphics options Nexus ZIP (blank to use built-in fallback): ' > /dev/tty
    read -r MORE_GRAPHICS_ZIP < /dev/tty || true
  fi

  if [ -z "$MORE_GRAPHICS_ZIP" ]; then

    return
  fi

  [ -f "$MORE_GRAPHICS_ZIP" ] || die "ZIP not found: $MORE_GRAPHICS_ZIP"
  log "Installing strongly recommended More graphics options culler"
  rm -rf "$STATE/more-graphics"
  mkdir -p "$STATE/more-graphics"
  unzip -q -o "$MORE_GRAPHICS_ZIP" -d "$STATE/more-graphics"

  local culling_dll graphics_lua
  culling_dll="$(find "$STATE/more-graphics" -path '*/reframework/plugins/object_culling.dll' -print -quit)"
  graphics_lua="$(find "$STATE/more-graphics" -path '*/reframework/autorun/More graphics options.lua' -print -quit)"

  [ -n "$culling_dll" ] && [ -n "$graphics_lua" ] || die "ZIP must contain reframework/plugins/object_culling.dll and reframework/autorun/More graphics options.lua"

  cp -f "$culling_dll" "$PLUGINS/object_culling.dll"
  cp -f "$graphics_lua" "$AUTORUN/More graphics options.lua"
  python3 - "$DATA/detail_config.json" "$DATA/culling_plugin_config.txt" <<'PY'
import json, pathlib, sys
path = pathlib.Path(sys.argv[1])
settings = json.loads(path.read_text()) if path.exists() else {}
settings.update({
    "culling_amount": 7,
    "mesh_lod_bias": 1,
    "speedtree_lod_bias": 3,
    "speedtree_min_lod": 5,
    "texture_sampler_bias": 1.016,
    "object_culling_ratio": 24,
    "disable_shadows": False,
    "shadow_quality": 218,
    "shadow_filter": True,
    "ambient_lighting_quality": 7,
    "effect_density": 0.465,
    "weapon_effects": True,
    "disable_footprints": True,
    "disable_all_particles": False,
})
path.write_text(json.dumps(settings, indent=4) + "\n")
pathlib.Path(sys.argv[2]).write_text("7\n")
PY
}

install_reframework() {
  log "Installing REFramework"
  unzip -p "$CACHE/REFramework.zip" dinput8.dll > "$GAME_DIR/dinput8.dll.tmp"
  mv "$GAME_DIR/dinput8.dll.tmp" "$GAME_DIR/dinput8.dll"
}

install_optiscaler() {
  if ! command -v 7z >/dev/null 2>&1; then
    log "7z not found; keeping existing OptiScaler files. Install 7z to update them."

    return
  fi

  log "Installing OptiScaler as upscaler only"
  rm -rf "$STATE/optiscaler"
  mkdir -p "$STATE/optiscaler"
  7z x -y -o"$STATE/optiscaler" "$CACHE/OptiScaler.7z" >/dev/null

  local optiscaler_dll optiscaler_root
  optiscaler_dll="$(find "$STATE/optiscaler" -name OptiScaler.dll -print -quit)"
  optiscaler_root="$(dirname "$optiscaler_dll")"

  [ -n "$optiscaler_dll" ] || die "OptiScaler.dll missing from downloaded archive"

  cp -f "$optiscaler_root/OptiScaler.dll" "$GAME_DIR/dxgi.dll"
  for dll in amd_fidelityfx_dx12.dll amd_fidelityfx_upscaler_dx12.dll amd_fidelityfx_framegeneration_dx12.dll amd_fidelityfx_vk.dll libxess.dll libxess_dx11.dll nvngx.dll nvapi64.dll d3dcompiler_47.dll; do
    if [ -f "$optiscaler_root/$dll" ]; then
      cp -f "$optiscaler_root/$dll" "$GAME_DIR/$dll"
    fi
  done
}

install_cyboman_fsr() {
  log "Installing cyboman FSR 4.1.2 Lite Lossy upscaler"
  rm -rf "$STATE/cyboman"
  mkdir -p "$STATE/cyboman" "$FSR_DIR"
  7z x -y -o"$STATE/cyboman" "$CACHE/CybomanFSR.7z" >/dev/null

  local lossy_dll="$STATE/cyboman/4.1.2l-lossy/amd_fidelityfx_upscaler_dx12.dll"

  [ -f "$lossy_dll" ] || die "4.1.2l-lossy upscaler DLL missing from cyboman archive"

  backup_if_present "$FSR_DIR/amd_fidelityfx_upscaler_dx12.dll"
  cp -f "$lossy_dll" "$FSR_DIR/amd_fidelityfx_upscaler_dx12.dll"
  for dll in amd_fidelityfx_dx12.dll amd_fidelityfx_framegeneration_dx12.dll; do
    if [ ! -e "$FSR_DIR/$dll" ] && [ -f "$GAME_DIR/$dll" ]; then
      cp -f "$GAME_DIR/$dll" "$FSR_DIR/$dll"
    fi
  done
}

install_mako() {
  log "Installing MAKO Renderer 5.0.0"
  rm -rf "$STATE/mako"
  mkdir -p "$STATE/mako"
  tar -xJf "$CACHE/MAKO-Renderer-v5.0.0-linux.tar.xz" -C "$STATE/mako"
  MAKO_INSTALLER_ASSUME_YES=1 MAKO_INSTALLER_NO_LAUNCH=1 "$STATE/mako/Install MAKO Renderer"
}

write_mako_config() {
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
mako_fg_mode = "performance"
multiplier = 2
flow_scale = 0.5
scaling_enabled = false
adaptive = false
base_fps_cap = 0
EOF
}

install_consolidated_mod() {
  log "Installing consolidated REFramework mod"
  for retired_script in TurnTrim.lua GrassTrim.lua FarThrottle.lua LightTrim.lua ReduceZako.lua; do
    if [ -e "$AUTORUN/$retired_script" ]; then
      mv -f "$AUTORUN/$retired_script" "$BACKUP/$retired_script"
      log "Retired merged script: $retired_script"
    fi
  done

  cp -f "$ROOT/autorun/SteamDeckEnhancement.lua" "$AUTORUN/SteamDeckEnhancement.lua"
}

install_measured_config() {
  log "Installing measured configuration"
  backup_if_present "$GAME_DIR/config.ini"
  backup_if_present "$GAME_DIR/OptiScaler.ini"
  cp -f "$ROOT/config/config.ini" "$GAME_DIR/config.ini"
  cp -f "$ROOT/config/OptiScaler.ini" "$GAME_DIR/OptiScaler.ini"

  backup_if_present "$DATA/SteamDeckEnhancement.json"
  cp -f "$ROOT/config/SteamDeckEnhancement.json" "$DATA/SteamDeckEnhancement.json"
}

link_cyboman_paths() {
  if [ ! -f "$FSR_DIR/amd_fidelityfx_upscaler_dx12.dll" ]; then
    log "cyboman FSR files not found; OptiScaler will use its bundled FFX files"

    return
  fi

  python3 - "$FSR_DIR" "$GAME_DIR/OptiScaler.ini" <<'PY'
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
  log "Linked cyboman FSR 4.1.2 Lite Lossy files"
}

report_lsfg() {
  if [ -e "$HOME/lsfg" ] || [ -d "$HOME/homebrew/plugins/decky-lsfg-vk" ]; then
    log "LSFG detected but intentionally unused; MAKO FG is the frame generator"
  else
    log "No LSFG detected; no paid software is required"
  fi
}

patch_launch_options() {
  printf '%s\n' "$LAUNCH" > "$STATE/launch-options.txt"

  local was_launch_option_patched=0 vdf_file

  for vdf_file in "$HOME"/.local/share/Steam/userdata/*/config/localconfig.vdf; do
    [ -f "$vdf_file" ] || continue
    backup_if_present "$vdf_file"
    if python3 "$ROOT/steam-launch-options.py" "$vdf_file" "$LAUNCH"; then
      was_launch_option_patched=1
    fi
  done

  if [ "$was_launch_option_patched" -eq 0 ]; then
    log "Could not edit Steam launch options automatically. Set them manually to: $LAUNCH"
  fi
}

main() {
  parse_arguments "$@"
  fetch_packaged_files
  check_requirements
  setup_directories

  install_nexus_culler
  download_assets

  install_reframework
  install_optiscaler
  install_cyboman_fsr
  install_mako
  write_mako_config

  install_consolidated_mod
  install_measured_config
  link_cyboman_paths
  report_lsfg
  patch_launch_options

  log "Done. Restart Steam once so it reads the launch options."
  log "Start the game, then press Reset Scripts in REFramework."
}

main "$@"
