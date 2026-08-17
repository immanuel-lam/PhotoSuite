#!/bin/bash
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at https://mozilla.org/MPL/2.0/.

set -euo pipefail

output_directory="${1:?usage: generate-sbom.sh OUTPUT_DIRECTORY}"
repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source_version="${SBOM_SOURCE_VERSION:-$(git -C "$repository_root" rev-parse HEAD)}"
source_timestamp_epoch="$(git -C "$repository_root" show -s --format=%ct "$source_version")"
source_timestamp="$(TZ=UTC date -r "$source_timestamp_epoch" '+%Y-%m-%dT%H:%M:%SZ')"
cyclonedx_output="$output_directory/PhotoSuite.cdx.json"
spdx_output="$output_directory/PhotoSuite.spdx.json"
checksums_output="$output_directory/SHA256SUMS"

for required_command in syft shasum ruby; do
  if ! command -v "$required_command" >/dev/null 2>&1; then
    echo "error: $required_command is required to generate an SBOM." >&2
    exit 127
  fi
done

mkdir -p "$output_directory"
output_directory="$(cd "$output_directory" && pwd)"
cyclonedx_output="$output_directory/PhotoSuite.cdx.json"
spdx_output="$output_directory/PhotoSuite.spdx.json"
checksums_output="$output_directory/SHA256SUMS"
for output in "$cyclonedx_output" "$spdx_output" "$checksums_output"; do
  if [[ -e "$output" ]]; then
    echo "error: SBOM output already exists: $output" >&2
    exit 1
  fi
done

SYFT_CHECK_FOR_APP_UPDATE=false \
  syft "dir:$repository_root" \
    --config "$repository_root/.syft.yaml" \
    --source-name PhotoSuite \
    --source-version "$source_version" \
    --output "cyclonedx-json=$cyclonedx_output" \
    --output "spdx-json=$spdx_output"

for output in "$cyclonedx_output" "$spdx_output"; do
  if [[ ! -s "$output" ]]; then
    echo "error: Syft did not create a non-empty SBOM: $output" >&2
    exit 1
  fi
done

ruby - "$cyclonedx_output" "$spdx_output" "$repository_root" "$source_version" "$source_timestamp" <<'RUBY'
require "json"
require "digest"

cyclonedx = JSON.parse(File.read(ARGV.fetch(0)))
spdx = JSON.parse(File.read(ARGV.fetch(1)))
repository_root = ARGV.fetch(2)
source_version = ARGV.fetch(3)
source_timestamp = ARGV.fetch(4)

abort("error: invalid CycloneDX bomFormat") unless cyclonedx["bomFormat"] == "CycloneDX"
abort("error: missing CycloneDX specVersion") unless cyclonedx["specVersion"].is_a?(String)
abort("error: missing CycloneDX metadata") unless cyclonedx["metadata"].is_a?(Hash)
abort("error: missing CycloneDX components") unless cyclonedx["components"].is_a?(Array)
abort("error: invalid SPDX version") unless spdx["spdxVersion"].match?(/\ASPDX-2\./)
abort("error: missing SPDX creationInfo") unless spdx["creationInfo"].is_a?(Hash)
abort("error: missing SPDX packages") unless spdx["packages"].is_a?(Array)

uuid_bytes = Digest::SHA1.digest("PhotoSuite@#{source_version}").bytes.first(16)
uuid_bytes[6] = (uuid_bytes[6] & 0x0f) | 0x50
uuid_bytes[8] = (uuid_bytes[8] & 0x3f) | 0x80
uuid_hex = uuid_bytes.pack("C*").unpack1("H*")
uuid = [uuid_hex[0, 8], uuid_hex[8, 4], uuid_hex[12, 4], uuid_hex[16, 4], uuid_hex[20, 12]].join("-")

cyclonedx.fetch("metadata")["timestamp"] = source_timestamp
cyclonedx["serialNumber"] = "urn:uuid:#{uuid}"
spdx.fetch("creationInfo")["created"] = source_timestamp
spdx["documentNamespace"] = "https://spdx.org/spdxdocs/PhotoSuite-#{source_version}"

File.write(ARGV.fetch(0), JSON.pretty_generate(cyclonedx) + "\n")
File.write(ARGV.fetch(1), JSON.pretty_generate(spdx) + "\n")

if JSON.generate(cyclonedx).include?(repository_root) || JSON.generate(spdx).include?(repository_root)
  abort("error: SBOM contains the local repository path")
end
RUBY

temporary_checksums="$output_directory/.SHA256SUMS.$$.tmp"
trap 'rm -f "$temporary_checksums"' EXIT
(
  cd "$output_directory"
  LC_ALL=C shasum -a 256 PhotoSuite.cdx.json PhotoSuite.spdx.json > "$temporary_checksums"
)
mv "$temporary_checksums" "$checksums_output"
trap - EXIT

echo "Generated and validated SBOM files in $output_directory."
