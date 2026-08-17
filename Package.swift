// swift-tools-version: 6.3

// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import PackageDescription

let package = Package(
  name: "PhotoSuite",
  platforms: [
    .macOS(.v15)
  ],
  products: [
    .library(name: "PhotoDomain", targets: ["PhotoDomain"]),
    .library(name: "CatalogCore", targets: ["CatalogCore"]),
    .library(name: "RenderCore", targets: ["RenderCore"]),
    .library(name: "PhotoWorkflow", targets: ["PhotoWorkflow"]),
  ],
  targets: [
    .target(name: "PhotoDomain"),
    .target(
      name: "CatalogCore",
      dependencies: ["PhotoDomain"]
    ),
    .target(
      name: "RenderCore",
      dependencies: ["PhotoDomain"]
    ),
    .target(
      name: "PhotoWorkflow",
      dependencies: ["PhotoDomain", "CatalogCore", "RenderCore"]
    ),
    .testTarget(
      name: "PhotoDomainTests",
      dependencies: ["PhotoDomain"]
    ),
    .testTarget(
      name: "CatalogCoreTests",
      dependencies: ["CatalogCore"]
    ),
    .testTarget(
      name: "RenderCoreTests",
      dependencies: ["RenderCore"]
    ),
    .testTarget(
      name: "PhotoWorkflowTests",
      dependencies: ["PhotoWorkflow"]
    ),
  ],
  swiftLanguageModes: [.v6]
)
