# Dependency and license policy

## Purpose

This policy controls source, package, binary, model, font, test-fixture,
and build-tool dependencies. It applies before a dependency is merged,
not only before a release.

The application source is MPL-2.0 (SPDX: MPL-2.0). This policy does not
replace legal advice. A maintainer must obtain legal review when a
license, distribution term, patent term, export restriction, privacy
term, or trademark term is unclear.

## Current inventory

At this revision, PhotoSuite has no third-party source or binary
dependencies. Planned Apple system frameworks are supplied by macOS and
are not redistributed by this repository. Future inventory is recorded
in NOTICE and release SBOMs.

## Allowed only after review

The following SPDX license identifiers are normally acceptable for a
dependency, subject to its complete text, notices, source availability,
patent clauses, and distribution obligations:

- `MPL-2.0`
- `Apache-2.0`
- `MIT`
- `ISC`
- `BSD-2-Clause`
- `BSD-3-Clause`
- `BSL-1.0`
- `Zlib`
- `0BSD`
- `Unicode-DFS-2016`
- `CC0-1.0` for data, examples, and test fixtures only

`LGPL-2.1-or-later`, `LGPL-3.0-or-later`, `GPL-2.0-only`,
`GPL-3.0-only`, `AGPL-3.0-only`, `SSPL-1.0`, and source-available or
custom licenses require explicit legal and maintainer approval. Do not
add an incompatible dependency on the assumption that MPL-2.0 secondary
licensing will solve the distribution obligation.

## Prohibited without an approved exception

- A dependency with no identifiable license or SPDX expression.
- Copied code, Adobe code or assets, decompiled material, leaked SDK
  material, or material with unclear redistribution rights.
- A package that needs network use for import, catalog, edit, preview,
  or export in the offline core.
- A binary-only dependency without provenance, checksum, architecture,
  macOS compatibility, and license evidence.
- A dependency that sends image content, catalog content, credentials,
  or telemetry to a network service by default.
- A dependency that requires Electron, Mac Catalyst, Intel-only code, or
  a minimum macOS version newer than 15.0.

## Required dependency record

For every addition, the pull request must state:

1. name, upstream URL, version, immutable source revision, and SHA-256
   checksum for an archive or binary;
2. exact SPDX license identifier or a reviewed SPDX expression;
3. copyright, NOTICE, source-offer, patent, attribution, and
   redistribution obligations;
4. purpose, alternatives considered, macOS and arm64 effect, and
   offline-core effect;
5. how it is pinned in the dependency lock file;
6. how it appears in the CycloneDX and SPDX SBOM outputs; and
7. test, vulnerability, update, and removal plan.

Keep the checked-in dependency resolver state. Do not use an unpinned
branch, a mutable tag as the only identity, or a live URL as a release
input. Update NOTICE, the SBOM, and this inventory in the same pull
request.

## Apple frameworks and toolchains

Apple framework use must follow Apple's applicable SDK and Xcode terms.
Do not copy Apple headers, frameworks, or documentation into this
repository unless those terms permit it. The future project must list
its minimum Xcode version and SDK version in release metadata.

## Review and removal

Maintainers review additions for license compatibility, provenance,
vulnerabilities, runtime privacy, offline operation, platform scope,
and supply-chain risk. A dependency can be rejected or removed when its
license, support, security, or maintenance state becomes unsuitable.
