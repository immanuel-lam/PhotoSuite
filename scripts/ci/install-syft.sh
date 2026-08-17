#!/bin/bash
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at https://mozilla.org/MPL/2.0/.

set -euo pipefail

syft_version="1.50.0"
syft_sha256="e32fdb9d47823fa633748a1efca2528fd77c37469ea93c9e40ab835da44e4cce"
syft_url="https://github.com/anchore/syft/releases/download/v${syft_version}/syft_${syft_version}_darwin_arm64.tar.gz"
install_directory="${1:?usage: install-syft.sh INSTALL_DIRECTORY}"
temporary_directory="$(mktemp -d)"
trap 'rm -rf "$temporary_directory"' EXIT

archive="$temporary_directory/syft.tar.gz"
curl --fail --location --retry 3 --output "$archive" "$syft_url"

actual_sha256="$(shasum -a 256 "$archive" | awk '{print $1}')"
if [[ "$actual_sha256" != "$syft_sha256" ]]; then
  echo "error: Syft ${syft_version} checksum mismatch." >&2
  echo "expected: $syft_sha256" >&2
  echo "actual:   $actual_sha256" >&2
  exit 1
fi

tar -xzf "$archive" -C "$temporary_directory"
binary_path="$(find "$temporary_directory" -type f -name syft -perm +111 -print -quit)"
if [[ -z "$binary_path" ]]; then
  echo "error: the Syft archive does not contain an executable syft binary." >&2
  exit 1
fi

mkdir -p "$install_directory"
install -m 0755 "$binary_path" "$install_directory/syft"
"$install_directory/syft" version
