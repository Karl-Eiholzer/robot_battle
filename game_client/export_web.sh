#!/usr/bin/env bash
# Local web export for testing: ./export_web.sh && python3 -m http.server -d build/web 8000
set -euo pipefail
cd "$(dirname "$0")"
GODOT="${GODOT:-godot}"
if ! command -v "$GODOT" >/dev/null && [ -x /Applications/Godot.app/Contents/MacOS/Godot ]; then
	GODOT=/Applications/Godot.app/Contents/MacOS/Godot
fi
mkdir -p build/web
"$GODOT" --headless --export-release "Web" build/web/index.html
cp player_guide.html build/web/
echo "Exported to $(pwd)/build/web"
