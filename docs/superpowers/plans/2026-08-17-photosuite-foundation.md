# PhotoSuite Foundation Implementation Plan

> **For agentic workers:** Use test-driven development for production behavior. Keep originals immutable and keep preview and export on one render graph.

**Goal:** Build a compilable MPL-2.0 native macOS application that completes the first-photograph workflow and establishes stable catalog, render, and extension contracts.

**Architecture:** A Swift package supplies domain, catalog, render, and workflow libraries. An XcodeGen project supplies the signed SwiftUI/AppKit application bundle. Core Image and Metal provide the render path; SQLite provides catalog persistence.

**Tech Stack:** Swift 6.3, SwiftUI, AppKit, Core Image, MetalKit, ColorSync, Vision, Core ML, SQLite3, XCTest, XcodeGen.

## Global Constraints

- Deployment target is macOS 15.0; build only for Apple silicon.
- The application and core source use MPL-2.0.
- The main application must work without a network connection.
- Original image bytes must never change.
- Native Liquid Glass is available only on macOS 26 or later; macOS 15 through 25 use native material fallbacks.
- Liquid Glass is limited to controls and navigation, never the image or precision-content layer.
- The first slice imports common images and Apple-supported RAW files, persists edits, previews exposure and crop, reopens the catalog, and exports JPEG.
- Do not claim Lightroom 15.4.1 parity until the full matrix is complete.

---

### Task 1: FOSS foundation and project specification

Create MPL licensing, contribution and security policies, support matrices, dependency policy, SBOM configuration, README, and honest parity tracking documents.

### Task 2: Swift and Xcode project scaffold

Create Package.swift, XcodeGen project.yml, application entitlements, app target, package targets, test targets, resource layout, and baseline build commands.

### Task 3: Public domain contracts

Test-first implementation of PhotoAsset, SourceFingerprint, EnginePins, EditRecipe, EditOperation, MaskDefinition, DurableDerivative, CatalogJob, and the service and XPC protocol contracts.

### Task 4: Catalog and durable job core

Test-first SQLite WAL catalog with migrations, asset and edit persistence, FTS search, job persistence, source checksum checks, backup, reopen, and recoverable missing-file state.

### Task 5: Render and export core

Test-first Core Image decoder and render graph for common images and CIRAWFilter-supported RAW, exposure, contrast, highlights, shadows, saturation, crop, rotation, preview, and atomic tagged JPEG export.

### Task 6: Native application shell and first-photograph workflow

Build Library, Develop, and Deliver workspaces with native menus, settings, import, thumbnail grid, image canvas, edit inspector, proof mode, Liquid Glass navigation on macOS 26, fallback materials, catalog reopen, and export.

### Task 7: Integration verification and review

Run Swift tests, Xcode build and tests, accessibility checks, source-integrity tests, visual inspection, and broad code review. Record the implemented subset and remaining parity rows without overstating delivery.

