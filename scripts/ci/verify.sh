#!/bin/bash
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at https://mozilla.org/MPL/2.0/.

set -euo pipefail

host_architecture="$(uname -m)"
if [[ "$host_architecture" != "arm64" ]]; then
  echo "error: CI requires an Arm64 macOS runner; found $host_architecture." >&2
  exit 1
fi

if [[ -z "${DEVELOPER_DIR:-}" || ! -d "$DEVELOPER_DIR" ]]; then
  echo "error: Xcode 26.3 is not installed at ${DEVELOPER_DIR:-<unset>}." >&2
  echo "Installed Xcode applications:" >&2
  find /Applications -maxdepth 1 -name 'Xcode*.app' -print >&2 2>/dev/null || true
  exit 1
fi

for required_command in swift xcodegen xcodebuild; do
  if ! command -v "$required_command" >/dev/null 2>&1; then
    echo "error: $required_command is required and must be available on PATH." >&2
    exit 127
  fi
done

xcodebuild -version
swift --version
xcodegen --version

swift format lint --recursive Sources Tests PhotoSuiteApp
swift test
xcodegen generate
xcodebuild \
  -project PhotoSuite.xcodeproj \
  -scheme PhotoSuite \
  -configuration Debug \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath .build/XcodeDerivedData \
  CODE_SIGNING_ALLOWED=NO \
  ARCHS=arm64 \
  ONLY_ACTIVE_ARCH=YES \
  build
