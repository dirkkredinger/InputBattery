#!/bin/zsh
# Baut InputBattery.app (Menüleisten-App + Desktop-Widget) nach build/InputBattery.app
set -e
cd "$(dirname "$0")"
if [ ! -f Sources/App/AppIcon.icns ]; then
  swift Tools/make_icon.swift Resources
  iconutil -c icns Resources/AppIcon.iconset -o Sources/App/AppIcon.icns
fi
xcodebuild -project InputBattery.xcodeproj -target InputBattery -configuration Release \
  SYMROOT="$PWD/build/xcode" OBJROOT="$PWD/build/xcode/obj" \
  ${VERSION:+MARKETING_VERSION=$VERSION} -quiet
rm -rf build/InputBattery.app
ditto build/xcode/Release/InputBattery.app build/InputBattery.app
echo "Fertig: $PWD/build/InputBattery.app"
