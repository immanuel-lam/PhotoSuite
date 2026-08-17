# Parity, hardware, legal, and support matrices

## Reading this document

The comparison baseline is Adobe Lightroom Classic 15.4.1. This is a
planning comparison only. It is not a claim of compatibility,
interoperability, equivalent output, performance parity, file-format
support, or Adobe affiliation.

Status values are precise:

- **Unimplemented**: no shipped implementation or verification exists.
- **Not supported**: excluded from the planned product scope.
- **Not assessed**: no compatibility, legal, or support assessment has
  been completed.

Every row below is unimplemented, unsupported, or not assessed at this
revision. A planned task must not change a row to supported. A row moves
only after implementation and documented verification.

## Lightroom 15.4.1 parity matrix

| Area | Lightroom comparison capability | PhotoSuite status | Evidence required before a claim |
| --- | --- | --- | --- |
| Import | Photo import and source management | Unimplemented | Imported-file tests and user workflow evidence |
| Library | Catalog, folders, collections, search, metadata | Unimplemented | Durable catalog, migration, and reopen tests |
| Develop | Non-destructive adjustment workflow | Unimplemented | Render recipe, persistence, and image-result tests |
| RAW | Camera RAW decoding and processing | Unimplemented | Supported-camera list and decoder verification |
| Local edits | Masks, healing, red-eye, geometry | Unimplemented | Per-tool render and interaction verification |
| AI features | Denoise, selections, generative functions | Unimplemented | Model, privacy, offline, and output evaluation |
| Metadata | IPTC, EXIF, XMP, keywords, face data | Unimplemented | Read/write and round-trip tests |
| Catalog interchange | Lightroom catalog import or export | Not supported | Explicit scope decision and legal review |
| Presets | Lightroom preset import or export | Not supported | Explicit scope decision and legal review |
| Plug-ins | Lightroom plug-in compatibility | Not supported | Public extension contract and compatibility tests |
| Tethering | Camera tethered capture | Unimplemented | Camera and recovery verification |
| Cloud | Adobe cloud sync and sharing | Not supported | No Adobe service integration is planned |
| Mobile and web | Lightroom mobile or web workflow | Not supported | Native macOS scope only |
| Export | JPEG and other export workflows | Unimplemented | Export fidelity and metadata tests |
| Print and proof | Print templates, soft proofing, book, web | Unimplemented | Colour-managed output verification |
| Performance | Lightroom-class import, preview, and export speed | Not assessed | Defined workloads and benchmark results |

## Hardware and platform matrix

| Target | Status | Requirement before support claim |
| --- | --- | --- |
| macOS 15 on Apple silicon | Unimplemented | Build, tests, and manual workflow verification |
| macOS 16 through macOS 25 on Apple silicon | Unimplemented | Per-release compatibility verification |
| macOS 26 or later Liquid Glass controls | Unimplemented | Native control integration and accessibility verification |
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
| PhotoSuite source licensing | Unimplemented | MPL-2.0 applies when source is added; LICENSE is present |
| Third-party dependency licensing | Unimplemented | No dependencies exist; future additions need policy review and NOTICE/SBOM update |
| Adobe code, SDK contents, presets, assets, and catalog formats | Not supported | Do not copy, decompile, or redistribute without a valid right and review |
| Adobe Lightroom catalog import or export | Not supported | No compatibility claim or implementation is planned |
| Adobe trademarks | Not assessed | Use only as accurate nominative comparison with legal review for releases |
| User image copyright and privacy | Unimplemented | Local-data behaviour, consent, and retention rules require implementation review |
| Location, face, and other sensitive metadata | Unimplemented | Default handling and export controls require tests and documentation |
| Network services and telemetry | Not supported | The core must work offline; no network service is implemented |

## Support matrix

| Topic | Status | Current statement |
| --- | --- | --- |
| Application releases | Unimplemented | No release exists |
| Installation | Unimplemented | No application artifact exists |
| Image import | Unimplemented | No importer exists |
| RAW files and cameras | Unimplemented | No supported-camera list exists |
| Catalog migration and recovery | Unimplemented | No catalog exists |
| Editing, preview, and export | Unimplemented | No renderer or exporter exists |
| Accessibility | Unimplemented | No user interface exists to evaluate |
| Security response | Unimplemented | No supported release; see SECURITY.md |
| Commercial support | Not supported | No commercial support service is offered |
| Adobe product support | Not supported | PhotoSuite is independent from Adobe |

## Update rule

When a feature is implemented, change only its exact row, add links to
tests and release evidence, document known limits, and update README,
NOTICE, dependency records, and SBOMs when applicable. Do not replace
an unsupported or unimplemented row with a broad parity statement.
