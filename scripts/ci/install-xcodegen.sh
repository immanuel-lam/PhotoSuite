#!/bin/bash
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at https://mozilla.org/MPL/2.0/.

set -euo pipefail

xcodegen_version="2.45.3"
xcodegen_sha256="0c90f4d28ca57335f9fa78cf5bf6dabfe20a232036dabe36de2eef79cb7c0878"
xcodegen_url="https://github.com/yonaskolb/XcodeGen/releases/download/${xcodegen_version}/xcodegen.zip"
install_directory="${1:?usage: install-xcodegen.sh INSTALL_DIRECTORY}"
temporary_directory="$(mktemp -d)"
trap 'rm -rf "$temporary_directory"' EXIT

archive="$temporary_directory/xcodegen.zip"
curl --fail --location --retry 3 --output "$archive" "$xcodegen_url"

actual_sha256="$(shasum -a 256 "$archive" | awk '{print $1}')"
if [[ "$actual_sha256" != "$xcodegen_sha256" ]]; then
  echo "error: XcodeGen ${xcodegen_version} checksum mismatch." >&2
  echo "expected: $xcodegen_sha256" >&2
  echo "actual:   $actual_sha256" >&2
  exit 1
fi

unzip -q "$archive" -d "$temporary_directory/unpacked"
binary_path="$(find "$temporary_directory/unpacked" -type f -name xcodegen -perm +111 -print -quit)"
if [[ -z "$binary_path" ]]; then
  echo "error: the XcodeGen archive does not contain an executable xcodegen binary." >&2
  exit 1
fi

mkdir -p "$install_directory"
install -m 0755 "$binary_path" "$install_directory/xcodegen"
"$install_directory/xcodegen" --version
