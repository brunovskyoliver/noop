#!/bin/zsh
# Builds or tests the iPhone app alone, from project.ios.yml: no macOS app, Watch app or widgets.
#   Tools/ios.sh build     simulator build; prints the .app path for agent-device install
#   Tools/ios.sh test      unit tests hosted by the iPhone app on a local simulator
set -euo pipefail
cd "${0:A:h}/.."
xcodegen generate --spec project.ios.yml --quiet
dd=build/ios
common=(-project BroopiOS.xcodeproj -scheme NOOPiOS -derivedDataPath "$dd"
        CODE_SIGNING_ALLOWED=NO COMPILER_INDEX_STORE_ENABLE=NO)
case "${1:-build}" in
  build)
    xcodebuild "${common[@]}" -quiet -destination 'generic/platform=iOS Simulator' \
      ARCHS=arm64 ONLY_ACTIVE_ARCH=NO build
    echo "$dd/Build/Products/Debug-iphonesimulator/NOOP.app"
    ;;
  test)
    xcodebuild "${common[@]}" -quiet \
      -destination "platform=iOS Simulator,name=${IOS_SIMULATOR:-iPhone 18 Pro}" test
    ;;
  *) echo "usage: $0 [build|test]" >&2; exit 2 ;;
esac
