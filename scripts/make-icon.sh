#!/bin/zsh
# Regenerates assets/Hatch.icns from the drawing in make-icon.swift.
set -euo pipefail
cd "$(dirname "$0")/.."
swift scripts/make-icon.swift assets
iconutil -c icns assets/Hatch.iconset -o assets/Hatch.icns
echo "Built assets/Hatch.icns"
