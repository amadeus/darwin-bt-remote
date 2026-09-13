#!/usr/bin/env bash
set -euo pipefail
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
export PATH="/opt/homebrew/bin:$PATH"
cd "$(dirname "$0")"
ci_scripts/ci_post_clone.sh
swiftformat --lint .
swiftlint lint --strict --no-cache
xcodebuild -project BTRemote.xcodeproj -scheme BTRemote -configuration Debug \
    -destination "platform=macOS" -derivedDataPath .build/DerivedData build | xcbeautify
