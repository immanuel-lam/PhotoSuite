// SPDX-License-Identifier: MPL-2.0

import Foundation
import PhotoDomain

public enum XMPMetadataSidecarError: Error, Equatable, LocalizedError, Sendable {
  case malformed
  case invalidValue
  case writeFailed

  public var errorDescription: String? {
    switch self {
    case .malformed: "The XMP sidecar is malformed or uses an unsupported schema."
    case .invalidValue: "The XMP sidecar contains an invalid metadata value."
    case .writeFailed: "The XMP sidecar could not be written atomically."
    }
  }
}

/// A small, offline XMP sidecar interchange format for the PhotoMetadata fields.
///
/// The writer never opens the source image. `Data.write(options: .atomic)` publishes the sidecar
/// through a temporary sibling, so a failed write cannot leave a partial XML document.
public enum XMPMetadataSidecar {
  private static let namespace = "https://photosuite.app/ns/1.0/"

  public static func sidecarURL(for sourceURL: URL) -> URL {
    sourceURL.deletingPathExtension().appendingPathExtension("xmp")
  }

  @discardableResult
  public static func write(_ metadata: PhotoMetadata, for sourceURL: URL) throws -> URL {
    let destinationURL = sidecarURL(for: sourceURL)
    guard destinationURL.standardizedFileURL != sourceURL.standardizedFileURL else {
      throw XMPMetadataSidecarError.writeFailed
    }
    let data = Data(xml(for: metadata).utf8)
    do {
      try data.write(to: destinationURL, options: .atomic)
    } catch {
      throw XMPMetadataSidecarError.writeFailed
    }
    return destinationURL
  }

  public static func read(from sidecarURL: URL) throws -> PhotoMetadata {
    let data: Data
    do {
      data = try Data(contentsOf: sidecarURL)
    } catch {
      throw XMPMetadataSidecarError.malformed
    }

    let document: XMLDocument
    do {
      document = try XMLDocument(data: data, options: [.nodePreserveAll])
    } catch {
      throw XMPMetadataSidecarError.malformed
    }

    guard document.rootElement() != nil else { throw XMPMetadataSidecarError.malformed }
    func value(_ name: String) -> String? {
      (try? document.nodes(forXPath: "//*[local-name()='\(name)']"))?.first?.stringValue
    }
    func values(_ name: String) -> [String] {
      (try? document.nodes(forXPath: "//*[local-name()='\(name)']"))?.compactMap(\.stringValue)
        ?? []
    }
    func doubleValue(_ name: String) throws -> Double? {
      guard let raw = value(name), !raw.isEmpty else { return nil }
      guard let parsed = Double(raw) else { throw XMPMetadataSidecarError.invalidValue }
      return parsed
    }
    func intValue(_ name: String) throws -> Int? {
      guard let raw = value(name), !raw.isEmpty else { return nil }
      guard let parsed = Int(raw) else { throw XMPMetadataSidecarError.invalidValue }
      return parsed
    }

    guard
      let metadata = PhotoMetadata(
        title: value("title"),
        headline: value("headline"),
        description: value("description"),
        creator: value("creator"),
        credit: value("credit"),
        source: value("source"),
        copyrightNotice: value("copyrightNotice"),
        rightsUsageTerms: value("rightsUsageTerms"),
        city: value("city"),
        stateProvince: value("stateProvince"),
        country: value("country"),
        countryCode: value("countryCode"),
        cameraMake: value("cameraMake"),
        cameraModel: value("cameraModel"),
        lensModel: value("lensModel"),
        exposureTime: try doubleValue("exposureTime"),
        aperture: try doubleValue("aperture"),
        iso: try intValue("iso"),
        focalLengthMillimeters: try doubleValue("focalLengthMillimeters"),
        gpsLatitude: try doubleValue("gpsLatitude"),
        gpsLongitude: try doubleValue("gpsLongitude"),
        keywords: values("keyword")
      )
    else {
      throw XMPMetadataSidecarError.invalidValue
    }
    return metadata
  }

  private static func xml(for metadata: PhotoMetadata) -> String {
    let fields: [(String, String?)] = [
      ("title", metadata.title),
      ("headline", metadata.headline),
      ("description", metadata.description),
      ("creator", metadata.creator),
      ("credit", metadata.credit),
      ("source", metadata.source),
      ("copyrightNotice", metadata.copyrightNotice),
      ("rightsUsageTerms", metadata.rightsUsageTerms),
      ("city", metadata.city),
      ("stateProvince", metadata.stateProvince),
      ("country", metadata.country),
      ("countryCode", metadata.countryCode),
      ("cameraMake", metadata.cameraMake),
      ("cameraModel", metadata.cameraModel),
      ("lensModel", metadata.lensModel),
      ("exposureTime", metadata.exposureTime.map { String($0) }),
      ("aperture", metadata.aperture.map { String($0) }),
      ("iso", metadata.iso.map { String($0) }),
      ("focalLengthMillimeters", metadata.focalLengthMillimeters.map { String($0) }),
      ("gpsLatitude", metadata.gpsLatitude.map { String($0) }),
      ("gpsLongitude", metadata.gpsLongitude.map { String($0) }),
    ]
    let body =
      fields.compactMap { name, value in
        guard let value else { return nil }
        return "    <photosuite:\(name)>\(escape(value))</photosuite:\(name)>"
      }
      + metadata.keywords.map {
        "    <photosuite:keyword>\(escape($0))</photosuite:keyword>"
      }
    return """
      <?xml version="1.0" encoding="UTF-8"?>
      <photosuite:metadata xmlns:photosuite="\(namespace)" version="1">
      \(body.joined(separator: "\n"))
      </photosuite:metadata>
      """
  }

  private static func escape(_ value: String) -> String {
    value
      .replacingOccurrences(of: "&", with: "&amp;")
      .replacingOccurrences(of: "<", with: "&lt;")
      .replacingOccurrences(of: ">", with: "&gt;")
      .replacingOccurrences(of: "\"", with: "&quot;")
      .replacingOccurrences(of: "'", with: "&apos;")
  }
}
