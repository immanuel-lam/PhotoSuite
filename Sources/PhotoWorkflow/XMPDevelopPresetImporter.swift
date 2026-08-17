// SPDX-License-Identifier: MPL-2.0

import Foundation
import PhotoDomain

public enum XMPDevelopPresetImportError: Error, Equatable, LocalizedError, Sendable {
  case unreadable(URL)
  case malformed
  case invalidValue(field: String)
  case noDevelopAdjustments

  public var errorDescription: String? {
    switch self {
    case .unreadable(let url):
      "The XMP preset could not be read: \(url.lastPathComponent)."
    case .malformed:
      "The XMP preset is malformed or does not contain an XML document."
    case .invalidValue(let field):
      "The XMP preset contains an invalid value for \(field)."
    case .noDevelopAdjustments:
      "The XMP preset contains no supported Develop adjustments."
    }
  }
}

/// The result of importing a standards-based Adobe Camera Raw XMP sidecar.
///
/// This importer intentionally reads only public XMP attributes. It does not parse an Adobe
/// catalog, execute Adobe code, or claim pixel-identical Lightroom compatibility. Unsupported
/// attributes are returned to the caller so migration can be reviewed instead of silently
/// discarding information.
public struct XMPDevelopPresetImportResult: Codable, Hashable, Sendable {
  public let preset: DevelopPreset
  public let importedFields: [String]
  public let skippedFields: [String]

  public init(preset: DevelopPreset, importedFields: [String], skippedFields: [String]) {
    self.preset = preset
    self.importedFields = importedFields
    self.skippedFields = skippedFields
  }
}

public enum XMPDevelopPresetImporter {
  public static func importResult(
    from url: URL,
    name requestedName: String? = nil
  ) throws -> XMPDevelopPresetImportResult {
    let data: Data
    do {
      data = try Data(contentsOf: url)
    } catch {
      throw XMPDevelopPresetImportError.unreadable(url)
    }

    let document: XMLDocument
    do {
      document = try XMLDocument(data: data, options: [.nodePreserveAll])
    } catch {
      throw XMPDevelopPresetImportError.malformed
    }
    guard document.rootElement() != nil else {
      throw XMPDevelopPresetImportError.malformed
    }

    let attributes = adobeAttributes(in: document)
    var operations: [EditOperation] = []
    var importedFields: [String] = []

    func scalar(
      _ field: String,
      scale: Double = 1,
      range: ClosedRange<Double>
    ) throws -> Double? {
      guard let raw = attributes[field] else { return nil }
      guard let value = Double(raw), value.isFinite, range.contains(value) else {
        throw XMPDevelopPresetImportError.invalidValue(field: field)
      }
      importedFields.append(field)
      return value / scale
    }

    if let value = try scalar("Exposure2012", range: -20...20) {
      operations.append(.exposureEV(value))
    }
    if let value = try scalar("Contrast2012", scale: 100, range: -100...100) {
      operations.append(.contrast(value))
    }
    if let value = try scalar("Highlights2012", scale: 100, range: -100...100) {
      operations.append(.highlights(value))
    }
    if let value = try scalar("Shadows2012", scale: 100, range: -100...100) {
      operations.append(.shadows(value))
    }
    if let value = try scalar("Saturation", scale: 100, range: -100...100) {
      operations.append(.saturation(value))
    }

    let temperatureRaw = attributes["Temperature"]
    let tintRaw = attributes["Tint"]
    if temperatureRaw != nil || tintRaw != nil {
      let temperature: Double
      if let temperatureRaw {
        guard let value = Double(temperatureRaw), value.isFinite, (2_000...50_000).contains(value)
        else { throw XMPDevelopPresetImportError.invalidValue(field: "Temperature") }
        temperature = max(-1, min(1, (value - 6_500) / 3_500))
        importedFields.append("Temperature")
      } else {
        temperature = 0
      }
      let tint: Double
      if let tintRaw {
        guard let value = Double(tintRaw), value.isFinite, (-150...150).contains(value)
        else { throw XMPDevelopPresetImportError.invalidValue(field: "Tint") }
        tint = value / 150
        importedFields.append("Tint")
      } else {
        tint = 0
      }
      guard let adjustment = WhiteBalanceAdjustmentV1(temperature: temperature, tint: tint) else {
        throw XMPDevelopPresetImportError.invalidValue(field: "WhiteBalance")
      }
      operations.append(.whiteBalance(adjustment))
    }

    let sharpening = try scalar("Sharpness", scale: 100, range: 0...150)
    let noiseReduction = try scalar("LuminanceSmoothing", scale: 100, range: 0...100)
    if sharpening != nil || noiseReduction != nil {
      guard
        let adjustment = DetailAdjustmentV1(
          sharpening: min(1, max(0, sharpening ?? 0)),
          luminanceNoiseReduction: min(1, max(0, noiseReduction ?? 0))
        )
      else { throw XMPDevelopPresetImportError.invalidValue(field: "Detail") }
      operations.append(.detail(adjustment))
    }

    if let vignette = try scalar("VignetteAmount", scale: 100, range: -100...100) {
      if vignette < 0 {
        guard let adjustment = OpticsAdjustmentV1(vignetteCorrection: -vignette) else {
          throw XMPDevelopPresetImportError.invalidValue(field: "VignetteAmount")
        }
        operations.append(.optics(adjustment))
      } else if vignette > 0 {
        guard let adjustment = EffectsAdjustmentV1(vignetteAmount: vignette) else {
          throw XMPDevelopPresetImportError.invalidValue(field: "VignetteAmount")
        }
        operations.append(.effects(adjustment))
      }
    }

    if let raw = attributes["ConvertToGrayscale"] {
      let normalized = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
      guard ["true", "1", "yes"].contains(normalized) || ["false", "0", "no"].contains(normalized)
      else { throw XMPDevelopPresetImportError.invalidValue(field: "ConvertToGrayscale") }
      importedFields.append("ConvertToGrayscale")
      if ["true", "1", "yes"].contains(normalized) {
        guard
          let adjustment = BlackAndWhiteAdjustmentV1(
            redWeight: 0.299,
            greenWeight: 0.587,
            blueWeight: 0.114
          )
        else { throw XMPDevelopPresetImportError.invalidValue(field: "ConvertToGrayscale") }
        operations.append(.blackAndWhite(adjustment))
      }
    }

    guard !operations.isEmpty else {
      throw XMPDevelopPresetImportError.noDevelopAdjustments
    }
    let name = (requestedName ?? url.deletingPathExtension().lastPathComponent)
      .trimmingCharacters(in: .whitespacesAndNewlines)
    guard
      let preset = DevelopPreset(
        name: name.isEmpty ? "Imported XMP Preset" : name, operations: operations)
    else { throw XMPDevelopPresetImportError.noDevelopAdjustments }

    let skippedFields = attributes.keys
      .filter { !importedFields.contains($0) }
      .sorted()
    return XMPDevelopPresetImportResult(
      preset: preset,
      importedFields: importedFields,
      skippedFields: skippedFields
    )
  }

  private static func adobeAttributes(in document: XMLDocument) -> [String: String] {
    var result: [String: String] = [:]

    func visit(_ node: XMLNode) {
      if let element = node as? XMLElement {
        for attribute in element.attributes ?? [] {
          let name = attribute.localName ?? attribute.name ?? ""
          let qualifiedName = attribute.name ?? ""
          guard
            qualifiedName.hasPrefix("crs:")
              || attribute.uri == "http://ns.adobe.com/camera-raw-settings/1.0/"
          else { continue }
          if let value = attribute.stringValue { result[name] = value }
        }
      }
      for child in node.children ?? [] { visit(child) }
    }

    if let root = document.rootElement() { visit(root) }
    return result
  }
}
