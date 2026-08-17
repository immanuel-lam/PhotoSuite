# Parity, hardware, legal, and support matrices

## Reading this document

The comparison baseline is Adobe Lightroom Classic 15.4.1. This is a
planning comparison only. It is not a claim of compatibility,
interoperability, equivalent output, performance parity, file-format
support, or Adobe affiliation.

Status values are precise:

- **Unimplemented**: no relevant pre-alpha implementation or verification
  exists.
- **Implemented in pre-alpha core**: focused source or policy work exists
  where a user workflow is not applicable; no release claim exists.
- **Implemented in pre-alpha core, workflow not yet integrated**: focused
  source implementation and tests exist, but no usable user workflow,
  release support, or Lightroom comparison claim exists.
- **Partially implemented in pre-alpha core, workflow not yet integrated**:
  only the stated subset exists; all other parts of the comparison
  capability remain unimplemented.
- **Not supported**: excluded from the planned product scope.
- **Not assessed**: no compatibility, legal, or support assessment has
  been completed.

No row below claims Lightroom parity, user-workflow support, file-format
compatibility, performance, or release readiness. A core implementation
does not make a broad feature supported. A row moves only after focused
implementation and documented verification.

## Lightroom 15.4.1 parity matrix

| Area | Lightroom comparison capability | PhotoSuite status | Evidence required before a claim |
| --- | --- | --- | --- |
| Import | Photo import and source management | Partially implemented in pre-alpha core and workflow | Native multi-file import, source fingerprints, bookmarks, preview creation, and missing-file reporting; camera-card and Copy as DNG workflows are not complete |
| Library | Catalog, folders, collections, search, metadata | Partially implemented in pre-alpha core and workflow | SQLite migrations, asset search, jobs, bookmarks, backup, reopen, thumbnail grid, ratings and selection; folders, collections, smart collections, and full metadata tools are not complete |
| Develop | Non-destructive adjustment workflow | Partially implemented in pre-alpha core and workflow | Durable recipes, exposure/tone, crop/rotation, histogram, three-way colour grading, preview recovery, and native inspector; curves, masks, local AI, and many baseline controls remain incomplete |
| RAW | Camera RAW decoding and processing | Partially implemented in pre-alpha core and workflow | `CIRAWFilter` authority and common-image fallback are tested; no supported-camera list or licensed real RAW fixture test |
| Local edits | Masks, healing, red-eye, geometry | Partially implemented in pre-alpha core, workflow not yet integrated | Exposure, tone, crop, rotation, and typed mask contracts exist; mask authoring, healing, red-eye, and local AI are not complete |
| AI features | Denoise, selections, generative functions | Unimplemented | Model, privacy, offline, and output evaluation |
| Metadata | IPTC, EXIF, XMP, keywords, face data | Unimplemented | Read/write and round-trip tests |
| Catalog interchange | Lightroom catalog import or export | Not supported | Explicit scope decision and legal review |
| Presets | Lightroom preset import or export | Not supported | Explicit scope decision and legal review |
| Plug-ins | Lightroom plug-in compatibility | Not supported | Public extension contract and compatibility tests |
| Tethering | Camera tethered capture | Unimplemented | Camera and recovery verification |
| Cloud | Adobe cloud sync and sharing | Not supported | No Adobe service integration is planned |
| Mobile and web | Lightroom mobile or web workflow | Not supported | Native macOS scope only |
| Export | JPEG and other export workflows | Partially implemented in pre-alpha core and workflow | Atomic sRGB JPEG export, native save panel, quality control, and source-integrity tests; batch presets, resize, metadata, watermark, HDR, print, books, slideshows, and web galleries are not complete |
| Print and proof | Print templates, soft proofing, book, web | Unimplemented | Colour-managed output verification |
| Performance | Lightroom-class import, preview, and export speed | Not assessed | Defined workloads and benchmark results |

## Hardware and platform matrix

| Target | Status | Requirement before support claim |
| --- | --- | --- |
| macOS 15 on Apple silicon | Implemented in pre-alpha core, workflow not yet integrated | Native scaffold and core build and test evidence; manual workflow verification is still required |
| macOS 16 through macOS 25 on Apple silicon | Unimplemented | Per-release compatibility verification |
| macOS 26 or later Liquid Glass controls | Implemented in pre-alpha core and workflow | Availability-gated native glass controls, neutral precision surfaces, accessibility contracts, and Xcode 27 beta UI tests; final release accessibility and hardware verification remain open |
| Apple M1 family | Unimplemented | Build and workflow verification on an M1 Mac |
| Apple M2 family | Unimplemented | Build and workflow verification on an M2 Mac |
| Apple M3 family | Unimplemented | Build and workflow verification on an M3 Mac |
| Apple M4 family and later | Unimplemented | Build and workflow verification on each family |
| Intel Macs | Not supported | Apple silicon only is a product constraint |
| External GPU | Not supported | Apple silicon native scope; no support claim |
| Electron runtime | Not supported | Electron is prohibited by product scope |
| Mac Catalyst runtime | Not supported | Mac Catalyst is prohibited by product scope |

## Legal and data matrix

| Subject | Status | Rule |
| --- | --- | --- |
| PhotoSuite source licensing | Implemented in pre-alpha core | MPL-2.0 applies to source files; LICENSE and source notices are present |
| Third-party dependency licensing | Not assessed | No third-party source or binary dependency is present; future additions need policy review and NOTICE/SBOM update |
| Adobe code, SDK contents, presets, assets, and catalog formats | Not supported | Do not copy, decompile, or redistribute without a valid right and review |
| Adobe Lightroom catalog import or export | Not supported | No compatibility claim or implementation is planned |
| Adobe trademarks | Not assessed | Use only as accurate nominative comparison with legal review for releases |
| User image copyright and privacy | Unimplemented | Local-data behaviour, consent, and retention rules require implementation review |
| Location, face, and other sensitive metadata | Unimplemented | Default handling and export controls require tests and documentation |
| Network services and telemetry | Not supported | The core must work offline; no network service is implemented |

## Support matrix

| Topic | Status | Current statement |
| --- | --- | --- |
| Application releases | Unimplemented | No signed, notarized, reproducible, or published release exists |
| Installation | Unimplemented | No signed, notarized, or published application artifact exists |
| Image import | Partially implemented in pre-alpha core and workflow | Native multi-file import and missing-file state exist; card, camera, Copy as DNG, metadata presets, and complete recovery UI are not complete |
| RAW files and cameras | Partially implemented in pre-alpha core and workflow | Apple-supported RAW decoding uses `CIRAWFilter` authority and empty-pin recovery; no supported-camera list or licensed real RAW fixture test exists |
| Catalog migration and recovery | Partially implemented in pre-alpha core and workflow | SQLite migrations, integrity checks, bookmarks, backups, jobs, reopen, relink, and typed preview recovery exist; the full user recovery workflow is not complete |
| Editing, preview, and export | Partially implemented in pre-alpha core and workflow | Core Image and Metal render graph, bounded preview, histogram, three-way colour grade, native inspector, and atomic sRGB JPEG export exist; many Develop and Deliver modules remain incomplete |
| Accessibility | Partially implemented in pre-alpha core and workflow | Stable identifiers, keyboard commands, native controls, Reduce Transparency paths, and UI contract tests exist; VoiceOver and hardware acceptance remain open |
| Security response | Unimplemented | No supported release; see SECURITY.md |
| Commercial support | Not supported | No commercial support service is offered |
| Adobe product support | Not supported | PhotoSuite is independent from Adobe |

## Update rule

When a feature is implemented, change only its exact row, add links to
tests and release evidence, document known limits, and update README,
NOTICE, dependency records, and SBOMs when applicable. Do not replace
an unsupported or unimplemented row with a broad parity statement. A
pre-alpha core row must retain its workflow and release limits until they
are independently verified.
