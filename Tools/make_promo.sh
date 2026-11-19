#!/bin/zsh
# Renders Docs/screenshot(-de).png and Docs/demo(-de).gif with demo data.
set -e
cd "$(dirname "$0")/.."
WORK=$(mktemp -d)
# The widget file has its own @main; drop it for this tool.
sed 's/^@main//' Sources/Widget/BatteryWidget.swift > "$WORK/BatteryWidget.swift"
swiftc -O -parse-as-library -target "$(uname -m)-apple-macos14" \
  Sources/Shared/Snapshot.swift "$WORK/BatteryWidget.swift" Tools/Promo/Promo.swift -o "$WORK/promo"
"$WORK/promo"
rm -rf "$WORK"
