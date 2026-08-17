# PhotoSuite

PhotoSuite is a planned native macOS photograph workflow application.
It will use Swift, SwiftUI, AppKit, Core Image, Metal, ColorSync, and
SQLite. It is not an Electron or Mac Catalyst application.

## Current status

This revision establishes project governance and specification documents.
It contains no application target, package manifest, import workflow,
catalog, renderer, export function, or user interface. It is not ready
to build, test, distribute, or use for photographs.

The comparison baseline is Adobe Lightroom Classic 15.4.1. PhotoSuite
does not claim feature, file-format, performance, workflow, plug-in, or
service compatibility with Lightroom. See
[the parity and support matrices](docs/PARITY_AND_SUPPORT.md).

## Product constraints

- macOS 15.0 or later.
- Apple silicon only. Intel Macs are out of scope.
- Native AppKit and SwiftUI application. No Electron. No Mac Catalyst.
- Offline core. Import, catalog, edit, preview, and export must not
  require a network connection when they are implemented.
- Original image bytes are immutable. Edits are durable recipe data and
  derived output, not changes to the original file.
- The main source code is licensed under MPL-2.0 (SPDX: MPL-2.0).

## Scope of the first implementation slice

The planned first slice is intentionally small: import common image and
Apple-supported RAW files; retain a local catalog; apply exposure and
crop previews; reopen the catalog; and export a tagged JPEG. A plan is
not an implementation or a support promise.

## Build and release status

There is no build command in this revision. The project scaffold will
define the exact Xcode and Swift toolchain requirements. Before any
release, follow the reproducible-build and SBOM process in
[docs/REPRODUCIBLE_BUILDS_AND_SBOM.md](docs/REPRODUCIBLE_BUILDS_AND_SBOM.md).

## Contributing and security

Contributions require DCO sign-off. Read [CONTRIBUTING.md](CONTRIBUTING.md),
[SECURITY.md](SECURITY.md), and [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md).
New dependencies require the review rules in
[docs/DEPENDENCY_POLICY.md](docs/DEPENDENCY_POLICY.md).

## Legal and trademark notice

This project is independent from Adobe. Adobe and Lightroom are used
only for accurate comparison. They do not grant PhotoSuite any Adobe
code, file format rights, branding rights, compatibility claim, or
support relationship. See [NOTICE](NOTICE) and the legal matrix.
