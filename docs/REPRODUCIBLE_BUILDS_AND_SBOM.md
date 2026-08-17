# Reproducible builds and SBOMs

## Status

The public pre-alpha CI builds an unsigned debug application and tests the
native catalog and render cores. A successful public CI run exists for commit
[`126ee851bf9370837c1f783afa1e8daa65dfa27b`](https://github.com/immanuel-lam/PhotoSuite/actions/runs/32036892454)
on 17 August 2026. It proves that the earlier CI configuration completed on a
macOS 15 Arm64 runner. It does not prove release reproducibility, signing, or
notarization.

CI now also validates the checked-in SBOM generator contract and runs a pinned
Syft generator. It creates CycloneDX JSON, SPDX JSON, and `SHA256SUMS` in the
job workspace, but does not upload or publish them. No public CI result has yet
recorded this SBOM step. No independent clean-build comparison has been
recorded. Therefore, PhotoSuite does not claim that builds are reproducible and
does not publish an SBOM artifact.

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

The current CI is verification only. A separate release job must perform the
following steps before a release claim:

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
8. Update NOTICE, attach hashes and SBOMs to the release evidence.
9. Sign and notarize in a separate, documented phase.

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

## Checked-in generation and validation

`scripts/ci/install-syft.sh` installs Syft 1.50.0 for Darwin arm64 after it
checks the release archive SHA-256. `scripts/ci/generate-sbom.sh` then creates
these files from the repository directory:

```text
artifacts/sbom/PhotoSuite.cdx.json
artifacts/sbom/PhotoSuite.spdx.json
artifacts/sbom/SHA256SUMS
```

The generator requires a new output directory. It rejects stale output, checks
that both files are non-empty JSON with the expected top-level CycloneDX and
SPDX values, then creates `SHA256SUMS` in fixed filename order. It runs Syft
without update checks. It sets the source name to `PhotoSuite` and the source
version to the checked-out Git commit. It rejects output that contains the
local repository path. The reproducible invocation is:

```sh
scripts/ci/generate-sbom.sh artifacts/sbom
```

The script makes the command sequence and checksum-file order deterministic.
It does not prove that Syft output is byte-for-byte reproducible across
machines. A release job must record the Syft version, retain the generated
files, and compare independent clean generation results before such a claim.

## Signing and notarization gates

The verification workflow cannot sign or notarize. It has read-only repository
permissions, uses no secrets, and produces no release artifacts. A release is
blocked until all of these gates have evidence:

1. An approved Apple Developer signing identity and private key are available
   only to the release environment. The verification workflow must not receive
   them.
2. The release job builds the final archive with the reviewed hardened-runtime
   entitlements, verifies the signing identity and nested-code signatures, and
   records the signed archive SHA-256.
3. The release job submits the signed archive with authorized notarization
   credentials that are restricted to that environment, records the accepted
   notarization result, staples the ticket, and verifies the stapled archive.
4. A clean Apple silicon macOS acceptance check verifies the stapled artifact
   before publication.

## Current release blockers

- There is no independent, clean, byte-for-byte unsigned-build comparison.
- The new SBOM generation CI step has no recorded public run and no retained
  release SBOM artifact.
- No release signing identity, notarization environment, accepted ticket, or
  stapled artifact is configured or evidenced.
- No release-candidate acceptance evidence exists for an installed artifact.
- The application remains pre-alpha and does not claim Lightroom parity.

## Verification checklist

- SBOM files parse and use their declared schema versions.
- Components match lock files, checked-in binaries, and NOTICE.
- License expressions use SPDX identifiers and are reviewed.
- SBOM files contain no image paths, catalog paths, credentials, or
  personal metadata.
- Release documentation states the build reproducibility result, rather
  than assuming a successful compile proves it.
