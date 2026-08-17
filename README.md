# PhotoSuite

PhotoSuite is a native macOS photograph workflow application in pre-alpha.
It uses Swift, SwiftUI, AppKit, Core Image, Metal, ColorSync, MapKit,
AVFoundation, PDFKit, and SQLite. It is not an Electron or Mac Catalyst
application.

## Current status

This pre-alpha revision contains a native SwiftUI and AppKit application
with Library, Develop, Deliver, and Professional Workspace screens. It also
contains these tested components:

- PhotoDomain contracts, including versioned mask data and AI-service
  request and result contracts;
- a SQLite catalog with migrations, search, jobs, security-scoped
  bookmarks, backups, reopen tests, and local source-state recovery;
- a Core Image and Metal render core with common-image decoding and
  Apple-supported RAW decoding when `CIRAWFilter` accepts the source;
- a bounded DNG 1.7.1 metadata reader and atomic writer for existing fixed-size
  camera and software tags, with raw-payload preservation;
- bounded previews, a 256-bin RGB and luminance histogram, and recovery
  for legacy empty RAW decoder pins;
- durable ordered recipes for basic Develop controls, baseline tone,
  white-balance, transform, detail, optics, effects, calibration,
  black-and-white, HDR-intent, and deterministic manual red-eye operations
  for user-specified regions; and
- atomic JPEG, PNG, HEIF, and TIFF delivery with tested resize, metadata,
  text-watermark, output-sharpening, filtered Library selection, and sequential
  batch-export options; and
- PDF book, silent H.264 slideshow, and self-contained static HTML gallery
  output with atomic publication and cancellation cleanup; and
- Apple Vision foreground, subject, and person masks with durable grayscale
  coverage and stale-result protection; and
- durable face annotations with validated regions, optional labels, search,
  delete, and schema-v7 catalog migration; and
- ImageCaptureCore camera discovery/status/events, tethered capture request
  plumbing, and watched-folder import with settling and duplicate detection;
  and
- a catalog metadata inspector, MapKit GPS markers, AVFoundation device
  discovery, and native print routing.

The interface can import local sources, browse a catalog, apply basic and
baseline Develop groups, crop and rotate, compare before and after, inspect
the histogram and three-way colour grade, author versioned masks, edit
catalog metadata, and write JPEG, PNG, HEIF, or TIFF output through Deliver.
Durable regular and smart collections plus photo stacks load from the catalog and
can be created from the Library sidebar. Durable hierarchical keyword nodes and
asset assignments, folder hierarchy and asset assignments, durable Develop presets,
plus independent virtual-copy recipe history, are stored in the catalog and covered
by migration and reopen tests. Session collections remain temporary.
The baseline controls and mask contracts are pre-alpha workflow evidence;
they are not a Lightroom-equivalent implementation.

Mask data, authoring, duplicate/synchronise requests, stale-result validation,
deterministic rasterisation, graph composition, masked exposure, and masked
colour grading exist. Bounded deterministic clone, healing, and manual red-eye
recipes are also available in the render core, but they are not texture-aware
or automatically detected Lightroom equivalents. Apple Vision foreground,
subject, and person selection is available offline; sky, object, background,
landscape, real depth, denoise, super-resolution, automatic eye detection, and
generative functions remain incomplete. No proprietary or network-only model
pack is bundled.
A common-image preview fallback is available when a source is not accepted
as RAW; this is not a supported-camera list. A licensed real RAW fixture is
absent, so the real RAW fixture test is skipped.

The project has no Lightroom parity claim. Bayer/X-Trans raw-pixel decoding,
LibRaw fallback, and complete DNG encoding remain incomplete. Physical tethered transfer,
vendor camera SDK adapters, print templates and soft proofing, hosted
publishing, plug-in hosting, Adobe migration, AI features beyond the
verified Vision subset, texture-aware retouching, and production support for
the full range of Lightroom formats remain incomplete. Embedded XMP writing, full
metadata batch editing, complete keyword-taxonomy authoring, face detection and
people UI, and full virtual-copy batch/export workflow support are also incomplete.
Durable face regions and labels are available without identity recognition. An atomic XMP
sidecar writer/reader and a bounded standards-based Adobe XMP Develop-preset
importer exist as tested interoperability cores, but proprietary Lightroom
catalog parsing is not implemented. Cloud services, mobile clients, and web editing are out
of scope. There is no signed, notarized,
reproducible, or published application release. Do not use this pre-alpha
revision for production photographs.

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

The implemented slice is intentionally limited. It provides an early local
workflow for import, catalog browsing, basic edits, bounded previews, and
JPEG delivery. The tested core covers a wider set of durable adjustment and
contract types than the current controls expose. It is implementation evidence
only, not a support promise or Lightroom comparison claim.

## Build and release status

Use `make check` to run the Swift package tests, generate the Xcode
project with XcodeGen, and build the unsigned arm64 macOS application.
The current scaffold requires Swift 6, Xcode 26.3 or later, and XcodeGen
2.45.3 or later on `PATH`. Public CI run
[`32047974543`](https://github.com/immanuel-lam/PhotoSuite/actions/runs/32047974543)
passed the package tests, unsigned arm64 build, and checked-in SBOM step for
commit `2a073619f0a35f1ce362f66f1683a1ccb1735fd0`. This does not prove a
release artifact, reproducibility,
signing, or notarization. Before any release, follow the reproducible-build
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
