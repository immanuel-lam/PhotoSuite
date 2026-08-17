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
- **Implemented in pre-alpha interface and core, workflow limited**: an
  early native interface and tested core exist for the stated subset, but
  the workflow is not release-supported and does not establish parity.
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
| Import | Photo import and source management | Implemented in pre-alpha interface and core, workflow limited | Native local multi-file import, fingerprinting, bookmarks, and item-error handling exist; no import review, duplicate policy, copy or move workflow, or release support |
| Library | Catalog, folders, collections, search, metadata | Implemented in pre-alpha interface and core, workflow limited | SQLite catalog/search/jobs/bookmarks/backups and native browsing, rating, colour-label, search, smart-filter, durable regular/smart collections, photo-stack controls, hierarchical keyword nodes and asset assignments, folder hierarchy and asset assignment, native keyword/folder controls, independent virtual-copy recipe history, native virtual-copy controls, and durable face-region/label records exist ([catalog tests](../Tests/CatalogCoreTests/KeywordAndVirtualCopyTests.swift), [folder tests](../Tests/CatalogCoreTests/FolderCatalogTests.swift), [face tests](../Tests/CatalogCoreTests/FaceCatalogTests.swift), [workspace tests](../Tests/PhotoWorkflowTests/PhotoWorkspaceTests.swift)); face detection, people UI, keyword-node authoring, Lightroom migration, and broader metadata workflows remain incomplete |
| Develop | Non-destructive adjustment workflow | Implemented in pre-alpha interface and core, workflow limited | Native basic adjustment, crop, rotation, undo, redo, and before/after controls exist; durable recipes, Develop preset save/list/apply/delete, and tested baseline tone, white-balance, transform, detail, optics, effects, calibration, black-and-white, HDR-intent, three-way grade, and histogram core exist; Adobe-equivalent profiles, lens database integration, dehaze, grain, full HDR output, and complete workflow validation remain incomplete |
| RAW | Camera RAW decoding and processing | Implemented in pre-alpha interface and core, workflow limited | `CIRAWFilter` is authority for real RAW decoding; common-image fallback and empty legacy RAW-pin recovery exist; DNG 1.7.1 metadata inspection and fixed-size ASCII tag patching preserve raw payloads ([DNG container tests](../Tests/RenderCoreTests/DNGContainerReaderTests.swift)); Bayer/X-Trans decoding, LibRaw fallback, complete DNG encoding, supported-camera list, and licensed real RAW fixture test remain incomplete |
| Local edits | Masks, healing, red-eye, geometry | Partially implemented in pre-alpha core, workflow not yet integrated | Versioned mask primitives, mask graphs, authoring, duplicate/synchronise requests, stale-result gating, deterministic brush/linear/radial/colour/luminance/depth rasterisation, graph composition, masked exposure/colour grading, crop, rotation, baseline transform rendering, bounded deterministic clone/healing recipes, and user-specified manual red-eye correction are tested ([retouch tests](../Tests/RenderCoreTests/RetouchRenderTests.swift)); AI-generated masks, real depth data, automatic eye detection, texture-aware healing, and complete mask UI remain incomplete |
| AI features | Denoise, selections, generative functions | Partially implemented in pre-alpha core, workflow not yet integrated | Offline Apple Vision foreground, subject, and person masks now produce durable grayscale coverage with asset/mask/revision/request identity and stale-result rejection ([Vision mask tests](../Tests/RenderCoreTests/VisionAIMaskServiceTests.swift)); sky, object, background, landscape, and depth now have explicit typed unavailable/optional-model capability results and stale-result tests ([semantic capability tests](../Tests/RenderCoreTests/VisionSemanticMaskCapabilitiesTests.swift)), but no default models are bundled; denoise, super-resolution, generative output, packaged proprietary weights, and end-user AI controls remain incomplete |
| Metadata | IPTC, EXIF, XMP, keywords, face data | Partially implemented in pre-alpha interface and core, workflow limited | Durable IPTC/EXIF/XMP-like fields, atomic XMP sidecar write/read, bounded standards-based Adobe XMP Develop-preset import with skipped-field reporting, keyword normalisation/search, hierarchical keyword nodes and asset assignments, schema-v1-to-v7 catalog migration, preset save/list/apply/delete, durable face regions/labels/search/delete, reopen, source-immutability tests, and a Library metadata editor exist ([keyword tests](../Tests/CatalogCoreTests/KeywordAndVirtualCopyTests.swift), [face tests](../Tests/CatalogCoreTests/FaceCatalogTests.swift), [XMP tests](../Tests/PhotoWorkflowTests/XMPSidecarWriterTests.swift), [preset-import tests](../Tests/PhotoWorkflowTests/XMPDevelopPresetImporterTests.swift)); batch metadata UI, embedded XMP writing, full field coverage, complete taxonomy authoring, Vision face detection, and people UI remain incomplete |
| Catalog interchange | Lightroom catalog import or export | Partially implemented in pre-alpha core, workflow limited | Standards-based Adobe XMP Develop-preset import exists with typed skipped-field reporting; no proprietary Lightroom catalog parser or catalog round-trip claim exists |
| Presets | Lightroom preset import or export | Not supported | Explicit scope decision and legal review |
| Plug-ins | Lightroom plug-in compatibility | Partially implemented in pre-alpha interface and core, workflow not yet integrated | Versioned extension contracts and an explicit disabled native status exist; no signed host, sandbox policy, ABI compatibility, or third-party plug-in test exists |
| Tethering | Camera tethered capture | Partially implemented in pre-alpha interface and core, workflow limited | ImageCaptureCore discovery, status/events, capture-request plumbing, native status controls, and watched-folder import with settling, duplicate detection, atomic copy, cancellation, and recovery are tested ([capture tests](../Tests/PhotoWorkflowTests/CapturePipelineTests.swift)); physical camera transfer and Canon/Nikon/Sony/Fujifilm/Leica vendor adapters remain unverified or external |
| Cloud | Adobe cloud sync and sharing | Not supported | No Adobe service integration is planned |
| Mobile and web | Lightroom mobile or web workflow | Not supported | Native macOS scope only |
| Export | JPEG and other export workflows | Implemented in pre-alpha interface and core, workflow limited | Deliver provides atomic sRGB JPEG, PNG, HEIF, and TIFF export with tested resize, metadata, text-watermark, output-sharpening, cancellation, duplicate-destination checks, filtered Library batch export, and sequential batch publication; publish services, broader codec coverage, and release validation remain incomplete |
| Print and proof | Print templates, soft proofing, book, web | Partially implemented in pre-alpha interface and core, workflow limited | Native print routing, a distraction-free proof-mode view, PDF book export, silent H.264 slideshow export, and self-contained static HTML gallery export now exist with cancellation and atomic publication tests; colour-managed soft proofing, print templates, hosted publishing, book templates, and output verification remain incomplete |
| Performance | Lightroom-class import, preview, and export speed | Not assessed | Defined workloads and benchmark results |

## Hardware and platform matrix

| Target | Status | Requirement before support claim |
| --- | --- | --- |
| macOS 15 on Apple silicon | Implemented in pre-alpha interface and core, workflow limited | Native scaffold, core, and early interface build and test evidence exist; manual workflow, accessibility, and installed-artifact verification are still required |
| macOS 16 through macOS 25 on Apple silicon | Unimplemented | Per-release compatibility verification |
| macOS 26 or later Liquid Glass controls | Partially implemented in pre-alpha interface and core, workflow limited | Runtime-gated native Glass controls exist on current macOS; macOS 15 fallback materials and accessibility require hardware verification |
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
| User image copyright and privacy | Partially implemented in pre-alpha core, workflow not yet integrated | The core is local and offline by design; data retention, consent, AI model data handling, and release privacy review remain unimplemented |
| Location, face, and other sensitive metadata | Partially implemented in pre-alpha interface and core, workflow limited | Deliver has selected JPEG metadata policies; GPS extraction and durable face regions/labels exist, while EXIF, IPTC, XMP, face-detection, location round-trip, and default-disclosure rules remain incomplete |
| Network services and telemetry | Not supported | The core must work offline; no network service is implemented |

## Support matrix

| Topic | Status | Current statement |
| --- | --- | --- |
| Application releases | Unimplemented | No signed, notarized, reproducible, or published release exists |
| Installation | Unimplemented | No signed, notarized, or published application artifact exists |
| Image import | Implemented in pre-alpha interface and core, workflow limited | Local multi-file import exists; no production import review, duplicate policy, or file-management workflow exists |
| RAW files and cameras | Implemented in pre-alpha interface and core, workflow limited | `CIRAWFilter` is authority for real RAW decoding; common-image fallback and legacy pin recovery exist; bounded DNG metadata patching is source-preserving; no Bayer/X-Trans decoder, LibRaw fallback, supported-camera list, or licensed real RAW fixture test exists |
| Catalog migration and recovery | Implemented in pre-alpha core, workflow not yet integrated | SQLite migrations, integrity checks, bookmarks, backups, jobs, and reopen tests exist; no user recovery workflow exists |
| Editing, preview, and export | Implemented in pre-alpha interface and core, workflow limited | Library, Develop, Deliver, and Professional Workspace screens exist with bounded previews, histogram, baseline Develop groups, durable Develop presets, colour grade, deterministic local mask rendering, verified Vision masks, deterministic manual red-eye rendering, durable metadata editing, XMP sidecars, folder/keyword/virtual-copy catalog records, native MapKit/print/device surfaces, PDF/slideshow/static-gallery output, and atomic multi-format delivery; broader AI execution, complete metadata UI, broader codecs, and production workflow verification remain incomplete |
| Accessibility | Partially implemented in pre-alpha interface and core, workflow limited | Native labels, hints, identifiers, and reduced-motion handling exist in early screens; no completed VoiceOver, keyboard-only, contrast, or physical-hardware accessibility audit exists |
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
