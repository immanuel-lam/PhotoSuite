#!/bin/bash
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at https://mozilla.org/MPL/2.0/.

set -euo pipefail

repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
fixture_root="$(mktemp -d)"
trap 'rm -rf "$fixture_root"' EXIT

fake_bin="$fixture_root/bin"
fake_developer_dir="$fixture_root/Xcode.app/Contents/Developer"
command_log="$fixture_root/commands.log"
mkdir -p "$fake_bin" "$fake_developer_dir"

make_fake_command() {
  local name="$1"
  cat > "$fake_bin/$name" <<'SCRIPT'
#!/bin/bash
set -euo pipefail
printf '%s\n' "$(basename "$0") $*" >> "$CI_COMMAND_LOG"
SCRIPT
  chmod +x "$fake_bin/$name"
}

for command in swift xcodegen xcodebuild; do
  make_fake_command "$command"
done

cat > "$fake_bin/uname" <<'SCRIPT'
#!/bin/bash
set -euo pipefail
printf '%s\n' "${CI_TEST_ARCH:-arm64}"
SCRIPT
chmod +x "$fake_bin/uname"

CI_COMMAND_LOG="$command_log" \
DEVELOPER_DIR="$fake_developer_dir" \
PATH="$fake_bin:/usr/bin:/bin" \
  "$repository_root/scripts/ci/verify.sh"

expected_commands=$(cat <<'COMMANDS'
xcodebuild -version
swift --version
xcodegen --version
swift format lint --recursive Sources Tests PhotoSuiteApp
swift test
xcodegen generate
xcodebuild -project PhotoSuite.xcodeproj -scheme PhotoSuite -configuration Debug -destination platform=macOS,arch=arm64 -derivedDataPath .build/XcodeDerivedData CODE_SIGNING_ALLOWED=NO ARCHS=arm64 ONLY_ACTIVE_ARCH=YES build
COMMANDS
)
actual_commands="$(cat "$command_log")"
if [[ "$actual_commands" != "$expected_commands" ]]; then
  printf 'Unexpected CI commands.\nExpected:\n%s\nActual:\n%s\n' "$expected_commands" "$actual_commands" >&2
  exit 1
fi

: > "$command_log"
if CI_TEST_ARCH="x86_64" \
  CI_COMMAND_LOG="$command_log" \
  DEVELOPER_DIR="$fake_developer_dir" \
  PATH="$fake_bin:/usr/bin:/bin" \
    "$repository_root/scripts/ci/verify.sh"; then
  echo "verify.sh accepted a non-Arm64 host." >&2
  exit 1
fi
if [[ -s "$command_log" ]]; then
  echo "verify.sh ran build commands after it rejected the host architecture." >&2
  exit 1
fi

echo "CI verification script tests passed."
