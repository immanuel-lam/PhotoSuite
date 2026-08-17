// SPDX-License-Identifier: MPL-2.0
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation

/// Attribution information for a lens profile data source.
///
/// Lensfun's database is distributed under a share-alike Creative Commons
/// database licence. PhotoSuite stores the source notice beside each imported
/// profile so an exported recipe does not silently lose attribution.
public struct LensProfileAttributionV1: Codable, Hashable, Sendable {
  public let schemaVersion: UInt
  public let source: String
  public let license: String
  public let notice: String
  public let sourceURL: String?

  public init?(
    source: String,
    license: String,
    notice: String,
    sourceURL: String? = nil
  ) {
    let normalizedSource = source.trimmingCharacters(in: .whitespacesAndNewlines)
    let normalizedLicense = license.trimmingCharacters(in: .whitespacesAndNewlines)
    let normalizedNotice = notice.trimmingCharacters(in: .whitespacesAndNewlines)
    let normalizedURL = sourceURL?.trimmingCharacters(in: .whitespacesAndNewlines)
    guard
      !normalizedSource.isEmpty,
      !normalizedLicense.isEmpty,
      !normalizedNotice.isEmpty,
      normalizedSource.count <= 256,
      normalizedLicense.count <= 256,
      normalizedNotice.count <= 2_048,
      normalizedURL.map({ !$0.isEmpty && $0.count <= 2_048 }) ?? true
    else { return nil }
    schemaVersion = 1
    self.source = normalizedSource
    self.license = normalizedLicense
    self.notice = normalizedNotice
    self.sourceURL = normalizedURL
  }
}

/// A normalized, durable lens correction profile.
///
/// The values deliberately use the same bounded ranges as the existing optics
/// adjustment. Lensfun polynomial coefficients are converted once at import
/// time. This keeps render output deterministic and prevents an untrusted XML
/// file from injecting unbounded filter parameters.
public struct LensProfileV1: Codable, Hashable, Sendable, Identifiable {
  public let schemaVersion: UInt
  public let identifier: String
  public let maker: String
  public let model: String
  public let mount: String?
  /// Normalized barrel or pincushion correction in -1...1.
  public let distortion: Double
  /// Normalized correction strength in 0...1.
  public let vignetting: Double
  /// Normalized chromatic aberration correction in 0...1.
  public let chromaticAberration: Double
  /// Normalized colour-fringe suppression in 0...1.
  public let defringe: Double
  public let attribution: LensProfileAttributionV1

  public var id: String { identifier }

  public var displayName: String {
    if maker.isEmpty { return model }
    return "\(maker) \(model)"
  }

  public init?(
    identifier: String,
    maker: String,
    model: String,
    mount: String?,
    distortion: Double,
    vignetting: Double,
    chromaticAberration: Double,
    defringe: Double,
    attribution: LensProfileAttributionV1
  ) {
    let normalizedIdentifier = identifier.trimmingCharacters(in: .whitespacesAndNewlines)
    let normalizedMaker = maker.trimmingCharacters(in: .whitespacesAndNewlines)
    let normalizedModel = model.trimmingCharacters(in: .whitespacesAndNewlines)
    let normalizedMount = mount?.trimmingCharacters(in: .whitespacesAndNewlines)
    guard
      !normalizedIdentifier.isEmpty,
      !normalizedMaker.isEmpty,
      !normalizedModel.isEmpty,
      normalizedIdentifier.count <= 512,
      normalizedMaker.count <= 256,
      normalizedModel.count <= 512,
      normalizedMount.map({ !$0.isEmpty && $0.count <= 256 }) ?? true,
      distortion.isFinite,
      (-1...1).contains(distortion),
      vignetting.isFinite,
      (0...1).contains(vignetting),
      chromaticAberration.isFinite,
      (0...1).contains(chromaticAberration),
      defringe.isFinite,
      (0...1).contains(defringe)
    else { return nil }
    schemaVersion = 1
    self.identifier = normalizedIdentifier
    self.maker = normalizedMaker
    self.model = normalizedModel
    self.mount = normalizedMount?.isEmpty == true ? nil : normalizedMount
    self.distortion = distortion
    self.vignetting = vignetting
    self.chromaticAberration = chromaticAberration
    self.defringe = defringe
    self.attribution = attribution
  }

  /// Converts the profile into the existing deterministic optics operation.
  public func opticsAdjustment() -> OpticsAdjustmentV1? {
    OpticsAdjustmentV1(
      vignetteCorrection: vignetting,
      lensDistortion: distortion,
      chromaticAberration: chromaticAberration,
      defringe: defringe,
      lensProfileID: identifier
    )
  }
}

/// An imported profile database with its licence notice retained.
public struct LensProfileDatabaseV1: Codable, Hashable, Sendable {
  public let schemaVersion: UInt
  public let sourceVersion: String
  public let attribution: LensProfileAttributionV1
  public let profiles: [LensProfileV1]

  public init?(
    sourceVersion: String,
    attribution: LensProfileAttributionV1,
    profiles: [LensProfileV1]
  ) {
    let normalizedVersion = sourceVersion.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !normalizedVersion.isEmpty, normalizedVersion.count <= 64 else { return nil }
    var unique: [String: LensProfileV1] = [:]
    for profile in profiles where profile.attribution == attribution {
      unique[profile.identifier] = profile
    }
    schemaVersion = 1
    self.sourceVersion = normalizedVersion
    self.attribution = attribution
    self.profiles = unique.values.sorted { lhs, rhs in
      let comparison = lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName)
      if comparison == .orderedSame { return lhs.identifier < rhs.identifier }
      return comparison == .orderedAscending
    }
  }

  public static func empty(
    sourceVersion: String = "none",
    attribution: LensProfileAttributionV1 = .photosuite
  ) -> LensProfileDatabaseV1 {
    LensProfileDatabaseV1(
      sourceVersion: sourceVersion,
      attribution: attribution,
      profiles: []
    )!
  }

  public func search(_ query: String) -> [LensProfileV1] {
    let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines)
      .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    guard !normalized.isEmpty else { return profiles }
    return profiles.filter { profile in
      [profile.maker, profile.model, profile.mount ?? "", profile.identifier]
        .contains { value in
          value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .contains(normalized)
        }
    }
  }
}

extension LensProfileAttributionV1 {
  /// Attribution for the optional hand-authored PhotoSuite fixture profile set.
  public static var photosuite: LensProfileAttributionV1 {
    LensProfileAttributionV1(
      source: "PhotoSuite",
      license: "MPL-2.0",
      notice: "PhotoSuite profile contract; no third-party lens measurements bundled."
    )!
  }

  /// The attribution supplied by the Lensfun adapter when the caller does not
  /// provide a custom notice.
  public static var lensfun: LensProfileAttributionV1 {
    LensProfileAttributionV1(
      source: "Lensfun",
      license: "CC BY-SA 3.0",
      notice: "Lensfun database contributors",
      sourceURL: "https://lensfun.github.io/"
    )!
  }
}

public enum LensProfileXMLLoaderError: Error, Equatable, Sendable {
  case parseFailed(String)
  case noProfiles
  case invalidProfile(String)
}

extension LensProfileXMLLoaderError: LocalizedError {
  public var errorDescription: String? {
    switch self {
    case .parseFailed(let message): "The lens profile XML could not be read: \(message)"
    case .noProfiles: "The lens profile XML contains no usable lens profiles."
    case .invalidProfile(let message): "The lens profile is invalid: \(message)"
    }
  }
}

/// Dependency-free Lensfun XML adapter.
///
/// The adapter reads the public Lensfun XML shape but does not link to Lensfun
/// or any GPL metadata library. The conversion is intentionally conservative:
/// it imports one representative calibration per lens and clamps all values.
public enum LensProfileXMLLoader {
  public static func load(
    data: Data,
    attribution: LensProfileAttributionV1 = .lensfun
  ) throws -> LensProfileDatabaseV1 {
    let delegate = LensfunXMLDelegate(attribution: attribution)
    let parser = XMLParser(data: data)
    parser.delegate = delegate
    guard parser.parse() else {
      throw LensProfileXMLLoaderError.parseFailed(
        parser.parserError?.localizedDescription ?? "unknown XML parser error"
      )
    }
    guard !delegate.profiles.isEmpty else {
      throw LensProfileXMLLoaderError.noProfiles
    }
    guard
      let database = LensProfileDatabaseV1(
        sourceVersion: delegate.sourceVersion,
        attribution: attribution,
        profiles: delegate.profiles
      )
    else {
      throw LensProfileXMLLoaderError.invalidProfile("database metadata is invalid")
    }
    guard !database.profiles.isEmpty else {
      throw LensProfileXMLLoaderError.noProfiles
    }
    return database
  }
}

private final class LensfunXMLDelegate: NSObject, XMLParserDelegate {
  struct RawLens {
    var maker = ""
    var model = ""
    var mounts: [String] = []
    var distortions: [[String: String]] = []
    var tcas: [[String: String]] = []
    var vignettings: [[String: String]] = []
  }

  let attribution: LensProfileAttributionV1
  var sourceVersion = "1"
  var profiles: [LensProfileV1] = []
  private var currentLens: RawLens?
  private var currentTextElement: String?
  private var textBuffer = ""

  init(attribution: LensProfileAttributionV1) {
    self.attribution = attribution
  }

  func parser(
    _ parser: XMLParser,
    didStartElement elementName: String,
    namespaceURI: String?,
    qualifiedName qName: String?,
    attributes attributeDict: [String: String] = [:]
  ) {
    switch elementName {
    case "lensdatabase":
      let version = attributeDict["version"]?.trimmingCharacters(in: .whitespacesAndNewlines)
      sourceVersion = version?.isEmpty == false ? version! : "1"
    case "lens":
      currentLens = RawLens()
    case "maker", "model", "mount":
      guard currentLens != nil else { return }
      currentTextElement = elementName
      textBuffer = ""
    case "distortion":
      currentLens?.distortions.append(attributeDict)
    case "tca":
      currentLens?.tcas.append(attributeDict)
    case "vignetting":
      currentLens?.vignettings.append(attributeDict)
    default:
      break
    }
  }

  func parser(_ parser: XMLParser, foundCharacters string: String) {
    guard currentTextElement != nil else { return }
    textBuffer.append(string)
  }

  func parser(
    _ parser: XMLParser,
    didEndElement elementName: String,
    namespaceURI: String?,
    qualifiedName qName: String?
  ) {
    if let currentTextElement, currentTextElement == elementName {
      let value = textBuffer.trimmingCharacters(in: .whitespacesAndNewlines)
      if !value.isEmpty {
        switch elementName {
        case "maker": currentLens?.maker = value
        case "model": currentLens?.model = value
        case "mount": currentLens?.mounts.append(value)
        default: break
        }
      }
      self.currentTextElement = nil
      textBuffer = ""
    }

    guard elementName == "lens", let raw = currentLens else { return }
    currentLens = nil
    guard
      !raw.maker.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
      !raw.model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    else { return }

    let mount = raw.mounts.first
    let identifier = "lensfun:\(slug(raw.maker))|\(slug(raw.model))|\(slug(mount ?? "generic"))"
    let distortion = normalizedDistortion(raw.distortions)
    let tca = normalizedTCA(raw.tcas)
    let vignetting = normalizedVignetting(raw.vignettings)
    let profile = LensProfileV1(
      identifier: identifier,
      maker: raw.maker,
      model: raw.model,
      mount: mount,
      distortion: distortion,
      vignetting: vignetting,
      chromaticAberration: tca,
      defringe: min(1, tca * 0.75),
      attribution: attribution
    )
    if let profile { profiles.append(profile) }
  }

  private func slug(_ value: String) -> String {
    value
      .folding(
        options: [.diacriticInsensitive, .caseInsensitive],
        locale: Locale(identifier: "en_US_POSIX")
      )
      .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
      .joined(separator: "-")
  }

  private func number(_ values: [String: String], _ key: String) -> Double {
    guard let raw = values[key], let value = Double(raw), value.isFinite else { return 0 }
    return value
  }

  private func normalizedDistortion(_ records: [[String: String]]) -> Double {
    guard
      let record = records.max(by: {
        score($0, keys: ["k1", "k2", "k3"])
          < score($1, keys: ["k1", "k2", "k3"])
      })
    else { return 0 }
    let coefficient =
      number(record, "k1") + number(record, "k2") * 0.5
      + number(record, "k3") * 0.25
    return max(-1, min(1, coefficient * 4))
  }

  private func normalizedVignetting(_ records: [[String: String]]) -> Double {
    guard
      let record = records.max(by: {
        score($0, keys: ["k1", "k2", "k3", "k4"])
          < score($1, keys: ["k1", "k2", "k3", "k4"])
      })
    else { return 0 }
    let magnitude =
      abs(number(record, "k1")) + abs(number(record, "k2")) * 0.5
      + abs(number(record, "k3")) * 0.25 + abs(number(record, "k4")) * 0.125
    return min(1, magnitude)
  }

  private func normalizedTCA(_ records: [[String: String]]) -> Double {
    guard
      let record = records.max(by: {
        score($0, keys: ["vr", "vb", "vc"])
          < score($1, keys: ["vr", "vb", "vc"])
      })
    else { return 0 }
    let magnitude = max(
      abs(number(record, "vr")),
      abs(number(record, "vb")),
      abs(number(record, "vc"))
    )
    return min(1, magnitude * 200)
  }

  private func score(_ values: [String: String], keys: [String]) -> Double {
    keys.reduce(0) { partialResult, key in partialResult + abs(number(values, key)) }
  }
}
