// SPDX-License-Identifier: MPL-2.0

import Foundation
import PhotoDomain
import Testing

@testable import PhotoWorkflow

struct XMPDevelopPresetImporterTests {
  @Test
  func importsValidatedAdobeFieldsAndReportsUnsupportedFields() throws {
    let url = try fixture(
      """
      <?xml version="1.0" encoding="UTF-8"?>
      <x:xmpmeta xmlns:x="adobe:ns:meta/" xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#" xmlns:crs="http://ns.adobe.com/camera-raw-settings/1.0/">
        <rdf:RDF><rdf:Description
          crs:Exposure2012="-1.25"
          crs:Contrast2012="40"
          crs:Highlights2012="-30"
          crs:Shadows2012="25"
          crs:Saturation="-20"
          crs:Temperature="7200"
          crs:Tint="-15"
          crs:Sharpness="50"
          crs:LuminanceSmoothing="25"
          crs:VignetteAmount="-30"
          crs:ConvertToGrayscale="True"
          crs:Clarity2012="20" />
        </rdf:RDF>
      </x:xmpmeta>
      """
    )

    let result = try XMPDevelopPresetImporter.importResult(from: url, name: "  Travel  ")

    #expect(result.preset.name == "Travel")
    #expect(result.importedFields.contains("Exposure2012"))
    #expect(result.importedFields.contains("ConvertToGrayscale"))
    #expect(result.skippedFields == ["Clarity2012"])
    #expect(result.preset.operations.contains(.exposureEV(-1.25)))
    #expect(result.preset.operations.contains(.contrast(0.4)))
    #expect(result.preset.operations.contains(.highlights(-0.3)))
    #expect(result.preset.operations.contains(.shadows(0.25)))
    #expect(result.preset.operations.contains(.saturation(-0.2)))
    #expect(
      result.preset.operations.contains(
        .whiteBalance(try #require(WhiteBalanceAdjustmentV1(temperature: 0.2, tint: -0.1)))
      )
    )
    #expect(
      result.preset.operations.contains(
        .detail(try #require(DetailAdjustmentV1(sharpening: 0.5, luminanceNoiseReduction: 0.25)))
      )
    )
    #expect(
      result.preset.operations.contains(
        .optics(try #require(OpticsAdjustmentV1(vignetteCorrection: 0.3)))
      )
    )
    #expect(
      result.preset.operations.contains(
        .blackAndWhite(
          try #require(
            BlackAndWhiteAdjustmentV1(redWeight: 0.299, greenWeight: 0.587, blueWeight: 0.114)
          )
        )
      )
    )
  }

  @Test
  func malformedEmptyAndInvalidValuesAreTypedFailures() throws {
    let malformed = try fixture("<not-xml")
    #expect(throws: XMPDevelopPresetImportError.malformed) {
      _ = try XMPDevelopPresetImporter.importResult(from: malformed)
    }

    let empty = try fixture(
      "<x:xmpmeta xmlns:x=\"adobe:ns:meta/\"><x:empty /></x:xmpmeta>"
    )
    #expect(throws: XMPDevelopPresetImportError.noDevelopAdjustments) {
      _ = try XMPDevelopPresetImporter.importResult(from: empty)
    }

    let invalid = try fixture(
      """
      <x:xmpmeta xmlns:x="adobe:ns:meta/" xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#" xmlns:crs="http://ns.adobe.com/camera-raw-settings/1.0/"><rdf:RDF><rdf:Description crs:Contrast2012="not-a-number" /></rdf:RDF></x:xmpmeta>
      """
    )
    #expect(throws: XMPDevelopPresetImportError.invalidValue(field: "Contrast2012")) {
      _ = try XMPDevelopPresetImporter.importResult(from: invalid)
    }
  }

  @Test
  func defaultNameUsesTheSidecarStemAndDoesNotMutateSource() throws {
    let url = try fixture(
      """
      <x:xmpmeta xmlns:x="adobe:ns:meta/" xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#" xmlns:crs="http://ns.adobe.com/camera-raw-settings/1.0/"><rdf:RDF><rdf:Description crs:Exposure2012="0.5" /></rdf:RDF></x:xmpmeta>
      """,
      filename: "Golden.xmp"
    )
    let before = try Data(contentsOf: url)

    let result = try XMPDevelopPresetImporter.importResult(from: url)

    #expect(result.preset.name == "Golden")
    #expect(try Data(contentsOf: url) == before)
  }

  private func fixture(_ xml: String, filename: String = "Preset.xmp") throws -> URL {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let url = directory.appendingPathComponent(filename)
    try Data(xml.utf8).write(to: url)
    return url
  }
}
