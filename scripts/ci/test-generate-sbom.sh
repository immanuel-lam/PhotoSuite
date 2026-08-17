#!/bin/bash
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at https://mozilla.org/MPL/2.0/.

set -euo pipefail

repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
fixture_root="$(mktemp -d)"
trap 'rm -rf "$fixture_root"' EXIT

fake_bin="$fixture_root/bin"
output_directory="$fixture_root/sbom"
mkdir -p "$fake_bin"

cat > "$fake_bin/syft" <<'SCRIPT'
#!/bin/bash
set -euo pipefail

if [[ -n "${FAKE_SYFT_ARGUMENT_LOG:-}" ]]; then
  printf '%s\n' "$@" > "$FAKE_SYFT_ARGUMENT_LOG"
fi

for argument in "$@"; do
  case "$argument" in
    cyclonedx-json=*)
      destination="${argument#*=}"
      if [[ "${FAKE_SYFT_INVALID:-false}" == "true" ]]; then
        printf '%s\n' '{"bomFormat":"not-cyclonedx"}' > "$destination"
      else
        printf '%s\n' "{\"bomFormat\":\"CycloneDX\",\"specVersion\":\"1.5\",\"serialNumber\":\"urn:uuid:volatile\",\"metadata\":{\"timestamp\":\"volatile\"},\"components\":[{\"name\":\"${FAKE_SYFT_PATH_LEAK:-safe}\"}]}" > "$destination"
      fi
      ;;
    spdx-json=*)
      destination="${argument#*=}"
      printf '%s\n' '{"spdxVersion":"SPDX-2.3","documentNamespace":"https://example.invalid/volatile","creationInfo":{"created":"volatile"},"packages":[]}' > "$destination"
      ;;
  esac
done
SCRIPT
chmod +x "$fake_bin/syft"

PATH="$fake_bin:/usr/bin:/bin" \
  FAKE_SYFT_ARGUMENT_LOG="$fixture_root/syft-arguments" \
  "$repository_root/scripts/ci/generate-sbom.sh" "$output_directory"

if ! grep -Fx -- "--source-name" "$fixture_root/syft-arguments" >/dev/null ||
  ! grep -Fx -- "PhotoSuite" "$fixture_root/syft-arguments" >/dev/null ||
  ! grep -Fx -- "--source-version" "$fixture_root/syft-arguments" >/dev/null; then
  echo "SBOM generator does not set a stable source identity." >&2
  exit 1
fi

source_timestamp="$(TZ=UTC date -r "$(git -C "$repository_root" show -s --format=%ct HEAD)" '+%Y-%m-%dT%H:%M:%SZ')"
ruby -rjson -rdigest - "$output_directory/PhotoSuite.cdx.json" "$output_directory/PhotoSuite.spdx.json" "$(git -C "$repository_root" rev-parse HEAD)" "$source_timestamp" <<'RUBY'
cyclonedx = JSON.parse(File.read(ARGV.fetch(0)))
spdx = JSON.parse(File.read(ARGV.fetch(1)))
source_version = ARGV.fetch(2)
source_timestamp = ARGV.fetch(3)
uuid_bytes = Digest::SHA1.digest("PhotoSuite@#{source_version}").bytes.first(16)
uuid_bytes[6] = (uuid_bytes[6] & 0x0f) | 0x50
uuid_bytes[8] = (uuid_bytes[8] & 0x3f) | 0x80
uuid = uuid_bytes.pack("C*").unpack1("H*").then { |hex| [hex[0, 8], hex[8, 4], hex[12, 4], hex[16, 4], hex[20, 12]].join("-") }

abort("CycloneDX timestamp was not normalized") unless cyclonedx.dig("metadata", "timestamp") == source_timestamp
abort("CycloneDX serial was not normalized") unless cyclonedx["serialNumber"] == "urn:uuid:#{uuid}"
abort("SPDX timestamp was not normalized") unless spdx.dig("creationInfo", "created") == source_timestamp
abort("SPDX namespace was not normalized") unless spdx["documentNamespace"] == "https://spdx.org/spdxdocs/PhotoSuite-#{source_version}"
RUBY

expected_checksums="$(
  cd "$output_directory"
  shasum -a 256 PhotoSuite.cdx.json PhotoSuite.spdx.json
)"
actual_checksums="$(cat "$output_directory/SHA256SUMS")"
if [[ "$actual_checksums" != "$expected_checksums" ]]; then
  echo "SBOM checksum output is not deterministic." >&2
  exit 1
fi

if FAKE_SYFT_INVALID=true \
  PATH="$fake_bin:/usr/bin:/bin" \
  "$repository_root/scripts/ci/generate-sbom.sh" "$fixture_root/invalid"; then
  echo "SBOM generator accepted invalid CycloneDX JSON." >&2
  exit 1
fi

if FAKE_SYFT_PATH_LEAK="$repository_root" \
  PATH="$fake_bin:/usr/bin:/bin" \
  "$repository_root/scripts/ci/generate-sbom.sh" "$fixture_root/path-leak"; then
  echo "SBOM generator accepted the local repository path." >&2
  exit 1
fi

echo "SBOM generation script tests passed."
