// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import CatalogCore
import Foundation
import ImageIO
import PhotoDomain
import RenderCore
import UniformTypeIdentifiers

@MainActor
public enum PhotoWorkspaceComposition {
  public static func live(catalogURL: URL? = nil) throws -> PhotoWorkspace {
    let resolvedCatalogURL = try catalogURL ?? defaultCatalogURL()
    let catalog = try SQLiteCatalogStore(catalogURL: resolvedCatalogURL)
    let decoder = try AppleRawDecoder()

    return PhotoWorkspace(
      catalog: catalog,
      renderer: CoreImageRenderEngine(decoder: decoder),
      exporter: AtomicJPEGExporter(decoder: decoder),
      sourceAccess: SourceAccessOperations(
        persist: { assetID, _ in _ = try await catalog.createBookmark(forAssetID: assetID) },
        resolve: { asset in
          let resolved = try await catalog.resolveBookmark(forAssetID: asset.id)
          return try validatedSourceURL(resolved.url)
        },
        start: { url in url.startAccessingSecurityScopedResource() },
        stop: { url in url.stopAccessingSecurityScopedResource() }
      ),
      fingerprint: { url in try SourceFingerprinter.fingerprint(url: url) },
      probe: { url in
        let decoded = try await decoder.decode(RawDecodeRequest(sourceURL: url))
        return SourceProbe(
          dimensions: decoded.image.dimensions,
          pins: EnginePins(
            decoderIdentifier: decoded.decoderIdentifier,
            decoderVersion: decoded.decoderVersion,
            renderSchemaVersion: 1,
            cameraProfileVersion: nil,
            modelVersions: [:]
          ),
          typeIdentifier: UTType(filenameExtension: url.pathExtension)?.identifier
        )
      },
      locationProbe: { url in photoCoordinate(from: url) }
    )
  }

  public static func defaultCatalogURL() throws -> URL {
    guard
      let applicationSupport = FileManager.default.urls(
        for: .applicationSupportDirectory,
        in: .userDomainMask
      ).first
    else {
      throw PhotoWorkspaceError.sourceMissing(URL(fileURLWithPath: "Application Support"))
    }
    let directory = applicationSupport.appendingPathComponent("PhotoSuite", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory.appendingPathComponent("PhotoSuite.sqlite")
  }

  nonisolated static func validatedSourceURL(
    _ url: URL,
    start: (URL) -> Bool = { $0.startAccessingSecurityScopedResource() },
    stop: (URL) -> Void = { $0.stopAccessingSecurityScopedResource() },
    fileExists: (URL) -> Bool = { FileManager.default.fileExists(atPath: $0.path) }
  ) throws -> URL {
    let started = start(url)
    defer {
      if started { stop(url) }
    }
    guard fileExists(url) else {
      throw PhotoWorkspaceError.sourceMissing(url)
    }
    return url
  }
}

private func photoCoordinate(from url: URL) -> PhotoCoordinate? {
  guard
    let source = CGImageSourceCreateWithURL(url as CFURL, nil),
    let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil)
      as? [CFString: Any],
    let gps = properties[kCGImagePropertyGPSDictionary] as? [CFString: Any],
    let latitude = (gps[kCGImagePropertyGPSLatitude] as? NSNumber)?.doubleValue,
    let longitude = (gps[kCGImagePropertyGPSLongitude] as? NSNumber)?.doubleValue
  else {
    return nil
  }

  let latitudeReference = (gps[kCGImagePropertyGPSLatitudeRef] as? String)?.uppercased()
  let longitudeReference = (gps[kCGImagePropertyGPSLongitudeRef] as? String)?.uppercased()
  let signedLatitude = latitudeReference == "S" ? -abs(latitude) : abs(latitude)
  let signedLongitude = longitudeReference == "W" ? -abs(longitude) : abs(longitude)
  return PhotoCoordinate(latitude: signedLatitude, longitude: signedLongitude)
}
