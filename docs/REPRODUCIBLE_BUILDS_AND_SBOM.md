# Reproducible builds and SBOMs

## Status

No application build exists in this revision. Therefore PhotoSuite does
not claim that builds are reproducible and does not publish an SBOM
artifact. This document defines the required process before the first
release candidate.

## Reproducible-build objective

A release candidate must be buildable from a clean checkout on a
supported Apple silicon Mac, using documented pinned inputs, without
fetching undeclared source. The unsigned application payload must be
byte-for-byte identical, or any permitted difference must be explained
and recorded. Apple code-signing, notarization, and stapling can change
the final bundle and are reported separately.

The project must record all of these release inputs:

- source commit ID and clean-worktree status;
- macOS version, Xcode version and build number, SDK version, Swift
  version, and target triple `arm64-apple-macos15.0`;
- package resolver lock files, package revisions, binary checksums, and
  generated project tool versions;
- build configuration, compiler flags, asset-generation inputs, and
  environment values that affect output; and
- SHA-256 hashes for unsigned archive, signed archive, and SBOM files.

Use a clean build directory. Pin dependencies and generator versions.
Set `SOURCE_DATE_EPOCH` to the commit timestamp when supported by the
toolchain. Do not include user paths, current dates, random values, or
network results in the unsigned payload. Do not assert reproducibility
until two independent clean builds have been compared and differences
have been resolved or documented.

## Required release procedure

After the project scaffold provides the exact commands, a release job
must perform the following steps:

1. Check out the signed release commit and verify a clean worktree.
2. Verify pinned dependency checksums and generate the project without
   network access after dependencies are present locally.
3. Build and test the arm64 release configuration on macOS 15 or later.
4. Archive the unsigned payload twice in independent clean locations.
5. Compare the payload hashes and retain a difference report if they do
   not match.
6. Generate CycloneDX JSON and SPDX JSON SBOMs from the release inputs.
7. Validate both SBOMs, compare their component list to the resolver
   state, and scan the source and artifacts for known vulnerabilities.
8. Update NOTICE, attach hashes and SBOMs to the release evidence, then
   sign and notarize as a separate, documented phase.

## SBOM format and minimum fields

Release SBOMs use both CycloneDX JSON 1.5 or later and SPDX JSON 2.3 or
later. Every component needs a name, version, supplier when known,
license expression using SPDX identifiers, package URL or upstream URL,
hash when available, and relationship to PhotoSuite. The application
component uses `MPL-2.0`.

The SBOM must include direct and transitive Swift packages, binary
frameworks, bundled resources, generators that ship in the artifact,
and source copied into the distribution. It must not claim that an
Apple system framework is redistributed when it is only linked from the
user's installed macOS.

## Proposed generation configuration

The checked-in `.syft.yaml` configuration selects these stable output
files. The scaffold must create `artifacts/sbom/` during CI and populate
them from the release commit:

```text
artifacts/sbom/PhotoSuite.cdx.json
artifacts/sbom/PhotoSuite.spdx.json
artifacts/sbom/SHA256SUMS
```

The CI configuration must use a pinned SBOM generator release and save
its version in the release metadata. It must execute the following after
all resolver state is present:

```sh
mkdir -p artifacts/sbom
syft dir:. --config .syft.yaml
shasum -a 256 artifacts/sbom/PhotoSuite.cdx.json \
  artifacts/sbom/PhotoSuite.spdx.json > artifacts/sbom/SHA256SUMS
```

This configuration is not evidence that `syft` is installed or that the
commands have run in this repository. Syft creates the two SBOM files;
the separate `shasum` command creates `SHA256SUMS`. The future CI job
must validate the exact generator syntax for its pinned version and fail
if any required output is missing.

## Verification checklist

- SBOM files parse and use their declared schema versions.
- Components match lock files, checked-in binaries, and NOTICE.
- License expressions use SPDX identifiers and are reviewed.
- SBOM files contain no image paths, catalog paths, credentials, or
  personal metadata.
- Release documentation states the build reproducibility result, rather
  than assuming a successful compile proves it.
