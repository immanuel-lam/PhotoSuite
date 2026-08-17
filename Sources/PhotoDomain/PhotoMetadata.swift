// SPDX-License-Identifier: MPL-2.0

import Foundation

/// Descriptive, rights, location and camera metadata that can be stored independently of the
/// immutable source file. The field names intentionally follow the common IPTC Core, EXIF and
/// XMP vocabulary, while the catalog keeps the value as a versioned PhotoSuite record.
public struct PhotoMetadata: Codable, Hashable, Sendable {
  public let title: String?
  public let headline: String?
  public let description: String?
  public let creator: String?
  public let credit: String?
  public let source: String?
  public let copyrightNotice: String?
  public let rightsUsageTerms: String?
  public let city: String?
  public let stateProvince: String?
  public let country: String?
  public let countryCode: String?
  public let cameraMake: String?
  public let cameraModel: String?
  public let lensModel: String?
  public let exposureTime: Double?
  public let aperture: Double?
  public let iso: Int?
  public let focalLengthMillimeters: Double?
  public let gpsLatitude: Double?
  public let gpsLongitude: Double?
  public let keywords: [String]

  public static let empty = PhotoMetadata()!

  public init?(
    title: String? = nil,
    headline: String? = nil,
    description: String? = nil,
    creator: String? = nil,
    credit: String? = nil,
    source: String? = nil,
    copyrightNotice: String? = nil,
    rightsUsageTerms: String? = nil,
    city: String? = nil,
    stateProvince: String? = nil,
    country: String? = nil,
    countryCode: String? = nil,
    cameraMake: String? = nil,
    cameraModel: String? = nil,
    lensModel: String? = nil,
    exposureTime: Double? = nil,
    aperture: Double? = nil,
    iso: Int? = nil,
    focalLengthMillimeters: Double? = nil,
    gpsLatitude: Double? = nil,
    gpsLongitude: Double? = nil,
    keywords: [String] = []
  ) {
    guard
      Self.isValid(
        exposureTime: exposureTime, aperture: aperture, iso: iso,
        focalLengthMillimeters: focalLengthMillimeters,
        gpsLatitude: gpsLatitude, gpsLongitude: gpsLongitude)
    else {
      return nil
    }
    if let countryCode, !countryCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      let normalized = countryCode.trimmingCharacters(in: .whitespacesAndNewlines)
      guard normalized.count == 2,
        normalized.unicodeScalars.allSatisfy({ CharacterSet.letters.contains($0) })
      else {
        return nil
      }
    }

    self.title = Self.clean(title)
    self.headline = Self.clean(headline)
    self.description = Self.clean(description)
    self.creator = Self.clean(creator)
    self.credit = Self.clean(credit)
    self.source = Self.clean(source)
    self.copyrightNotice = Self.clean(copyrightNotice)
    self.rightsUsageTerms = Self.clean(rightsUsageTerms)
    self.city = Self.clean(city)
    self.stateProvince = Self.clean(stateProvince)
    self.country = Self.clean(country)
    self.countryCode = Self.clean(countryCode)?.uppercased()
    self.cameraMake = Self.clean(cameraMake)
    self.cameraModel = Self.clean(cameraModel)
    self.lensModel = Self.clean(lensModel)
    self.exposureTime = exposureTime
    self.aperture = aperture
    self.iso = iso
    self.focalLengthMillimeters = focalLengthMillimeters
    self.gpsLatitude = gpsLatitude
    self.gpsLongitude = gpsLongitude
    self.keywords = Self.cleanKeywords(keywords)
  }

  private enum CodingKeys: String, CodingKey {
    case title
    case headline
    case description
    case creator
    case credit
    case source
    case copyrightNotice
    case rightsUsageTerms
    case city
    case stateProvince
    case country
    case countryCode
    case cameraMake
    case cameraModel
    case lensModel
    case exposureTime
    case aperture
    case iso
    case focalLengthMillimeters
    case gpsLatitude
    case gpsLongitude
    case keywords
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    guard
      let metadata = Self(
        title: try container.decodeIfPresent(String.self, forKey: .title),
        headline: try container.decodeIfPresent(String.self, forKey: .headline),
        description: try container.decodeIfPresent(String.self, forKey: .description),
        creator: try container.decodeIfPresent(String.self, forKey: .creator),
        credit: try container.decodeIfPresent(String.self, forKey: .credit),
        source: try container.decodeIfPresent(String.self, forKey: .source),
        copyrightNotice: try container.decodeIfPresent(String.self, forKey: .copyrightNotice),
        rightsUsageTerms: try container.decodeIfPresent(String.self, forKey: .rightsUsageTerms),
        city: try container.decodeIfPresent(String.self, forKey: .city),
        stateProvince: try container.decodeIfPresent(String.self, forKey: .stateProvince),
        country: try container.decodeIfPresent(String.self, forKey: .country),
        countryCode: try container.decodeIfPresent(String.self, forKey: .countryCode),
        cameraMake: try container.decodeIfPresent(String.self, forKey: .cameraMake),
        cameraModel: try container.decodeIfPresent(String.self, forKey: .cameraModel),
        lensModel: try container.decodeIfPresent(String.self, forKey: .lensModel),
        exposureTime: try container.decodeIfPresent(Double.self, forKey: .exposureTime),
        aperture: try container.decodeIfPresent(Double.self, forKey: .aperture),
        iso: try container.decodeIfPresent(Int.self, forKey: .iso),
        focalLengthMillimeters: try container.decodeIfPresent(
          Double.self, forKey: .focalLengthMillimeters),
        gpsLatitude: try container.decodeIfPresent(Double.self, forKey: .gpsLatitude),
        gpsLongitude: try container.decodeIfPresent(Double.self, forKey: .gpsLongitude),
        keywords: try container.decodeIfPresent([String].self, forKey: .keywords) ?? []
      )
    else {
      throw DecodingError.dataCorruptedError(
        forKey: .keywords,
        in: container,
        debugDescription: "The metadata contains an invalid EXIF value or country code."
      )
    }
    self = metadata
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encodeIfPresent(title, forKey: .title)
    try container.encodeIfPresent(headline, forKey: .headline)
    try container.encodeIfPresent(description, forKey: .description)
    try container.encodeIfPresent(creator, forKey: .creator)
    try container.encodeIfPresent(credit, forKey: .credit)
    try container.encodeIfPresent(source, forKey: .source)
    try container.encodeIfPresent(copyrightNotice, forKey: .copyrightNotice)
    try container.encodeIfPresent(rightsUsageTerms, forKey: .rightsUsageTerms)
    try container.encodeIfPresent(city, forKey: .city)
    try container.encodeIfPresent(stateProvince, forKey: .stateProvince)
    try container.encodeIfPresent(country, forKey: .country)
    try container.encodeIfPresent(countryCode, forKey: .countryCode)
    try container.encodeIfPresent(cameraMake, forKey: .cameraMake)
    try container.encodeIfPresent(cameraModel, forKey: .cameraModel)
    try container.encodeIfPresent(lensModel, forKey: .lensModel)
    try container.encodeIfPresent(exposureTime, forKey: .exposureTime)
    try container.encodeIfPresent(aperture, forKey: .aperture)
    try container.encodeIfPresent(iso, forKey: .iso)
    try container.encodeIfPresent(focalLengthMillimeters, forKey: .focalLengthMillimeters)
    try container.encodeIfPresent(gpsLatitude, forKey: .gpsLatitude)
    try container.encodeIfPresent(gpsLongitude, forKey: .gpsLongitude)
    try container.encode(keywords, forKey: .keywords)
  }

  private static func isValid(
    exposureTime: Double?,
    aperture: Double?,
    iso: Int?,
    focalLengthMillimeters: Double?,
    gpsLatitude: Double?,
    gpsLongitude: Double?
  ) -> Bool {
    if let exposureTime, !exposureTime.isFinite || exposureTime <= 0 { return false }
    if let aperture, !aperture.isFinite || aperture <= 0 { return false }
    if let iso, iso <= 0 { return false }
    if let focalLengthMillimeters,
      !focalLengthMillimeters.isFinite || focalLengthMillimeters <= 0
    {
      return false
    }
    if let gpsLatitude, !gpsLatitude.isFinite || !(-90...90).contains(gpsLatitude) { return false }
    if let gpsLongitude, !gpsLongitude.isFinite || !(-180...180).contains(gpsLongitude) {
      return false
    }
    return true
  }

  private static func clean(_ value: String?) -> String? {
    guard let value else { return nil }
    let cleaned = value.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    return cleaned.isEmpty ? nil : cleaned
  }

  private static func cleanKeywords(_ values: [String]) -> [String] {
    var seen = Set<String>()
    return values.compactMap { value in
      guard let cleaned = clean(value) else { return nil }
      let key = cleaned.lowercased()
      guard seen.insert(key).inserted else { return nil }
      return cleaned
    }
  }
}

/// A reusable metadata assignment. Presets contain only durable metadata and never a source URL or
/// source fingerprint, so applying one cannot replace or mutate the original file.
public struct MetadataPreset: Codable, Hashable, Sendable, Identifiable {
  public let id: UUID
  public let name: String
  public let metadata: PhotoMetadata
  public let createdAt: Date
  public let updatedAt: Date

  public init?(
    id: UUID = UUID(),
    name: String,
    metadata: PhotoMetadata,
    createdAt: Date = Date(),
    updatedAt: Date = Date()
  ) {
    let normalizedName = name.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    guard !normalizedName.isEmpty else { return nil }
    self.id = id
    self.name = normalizedName
    self.metadata = metadata
    self.createdAt = createdAt
    self.updatedAt = updatedAt
  }
}
