#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"

bash -n "$ROOT/install.sh"
python3 - "$ROOT" <<'PY'
import json, pathlib
root = pathlib.Path(__import__('sys').argv[1])
for path in sorted((root / 'config').glob('*.json')):
    with path.open() as f:
        json.load(f)
    print(f"json ok: {path.name}")
cfg = (root / 'config/SteamDeckEnhancement.json').read_text()
assert '"KeepPercent": 25' in cfg
assert '"AnimalKeepPercent": 25' in cfg
opti = (root / 'config/OptiScaler.ini').read_text(errors='surrogateescape')
assert 'FGInput = nofg' in opti
assert 'FGOutput = nofg' in opti
PY

python3 - "$ROOT" <<'PY'
import pathlib, subprocess, tempfile
helper = pathlib.Path(__import__('sys').argv[1]) / 'steam-launch-options.py'
sample = '"Apps"\n{\n\t"2246340"\n\t{\n\t\t"LaunchOptions"\t\t"old"\n\t}\n\t"123"\n\t{\n\t\t"LaunchOptions"\t\t"keep"\n\t}\n}\n'
path = pathlib.Path(tempfile.mkdtemp()) / 'localconfig.vdf'
path.write_text(sample)
result = subprocess.run(['python3', str(helper), str(path), 'MAKO=1 %command%'], capture_output=True, text=True)
assert result.returncode == 0, result.stderr
written = path.read_text()
assert 'MAKO=1 %command%' in written
assert '"keep"' in written
print('steam launch options ok')
PY

if command -v luac >/dev/null 2>&1; then
  luac -p "$ROOT/autorun/SteamDeckEnhancement.lua"
  echo "lua ok"
else
  echo "luac unavailable; skipped Lua syntax check"
fi
echo "validation passed"
