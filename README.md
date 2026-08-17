# PhotoSuite

PhotoSuite is a native macOS photograph workflow application in active
pre-alpha development. It uses Swift, SwiftUI, AppKit, Core Image, Metal,
ColorSync, and SQLite. It is not an Electron or Mac Catalyst application.

## Current status

This pre-alpha revision contains the project governance documents, a
Swift package, and a native macOS application that builds. It also contains
these tested components:

- PhotoDomain contracts;
- a SQLite catalog with migrations, search, jobs, security-scoped
  bookmarks, backups, and reopen tests;
- a Core Image and Metal render core;
- common image decoding and Apple-supported RAW decoding when
  `CIRAWFilter` accepts the source;
- an ordered edit graph for exposure, tone, crop, rotation, and three-way
  colour grading, with bounded previews and render histograms;
- an import, Library, Develop, and Deliver workflow with native controls,
  macOS 26 Liquid Glass availability branches, and macOS 15 material
  fallbacks; and
- atomic sRGB JPEG export from the same edit graph.

This is not a Lightroom parity claim. Many planned capabilities remain
incomplete, including masks, local AI, full metadata, tethering, Map,
publishing, print, books, slideshows, web galleries, and camera/vendor
integrations. A licensed real RAW fixture is not present in this repository,
so the real RAW fixture test is skipped. There is no signed, notarized,
reproducible, or published release. Use test copies of photographs only.

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

## First implementation slice

The implemented first-photograph slice imports a common image or
Apple-supported RAW source, persists a local catalog, renders exposure and
crop previews, shows a histogram and three-way colour controls, reopens the
catalog, and exports a tagged JPEG. It is implementation evidence only, not
a support promise or Lightroom comparison claim.

## Build and release status

Use `make check` to run the Swift package tests, generate the Xcode
project with XcodeGen, and build the unsigned arm64 macOS application.
The current scaffold requires Swift 6, Xcode 26.3 or later, and XcodeGen
2.45.3 or later on `PATH`. Before any release, follow the reproducible-build
and SBOM process in
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
