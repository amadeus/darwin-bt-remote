#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
companion_dotnet="${BTREMOTE_DOTNET:-dotnet}"
companion_rid="${1:-win-x64}"
case "$companion_rid" in win-x64|win-arm64) ;; *) echo 'Use win-x64 or win-arm64' >&2; exit 1 ;; esac
companion_output=".build/windows/$companion_rid"
"$companion_dotnet" publish windows/BTRemote.Companion/BTRemote.Companion.csproj \
  -c Release -r "$companion_rid" --self-contained true -p:PublishSingleFile=true \
  -p:EnableCompressionInSingleFile=true -p:DebugType=None -o "$companion_output"
cp windows/packaging/* "$companion_output/"
cp windows/README.md "$companion_output/README.md"
python3 - "$companion_output" <<'PY'
from pathlib import Path
import sys,zipfile
root=Path(sys.argv[1])
archive=root.parent / ('BTRemote-Companion-' + root.name + '.zip')
with zipfile.ZipFile(archive, 'w', zipfile.ZIP_DEFLATED) as z:
    for p in sorted(root.iterdir()):
        if p.is_file() and p.suffix in {'.exe','.ps1','.cmd','.md'}:
            z.write(p,p.name)
print(archive.resolve())
PY
