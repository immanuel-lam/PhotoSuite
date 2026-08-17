// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import CoreGraphics
import CryptoKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

@testable import RenderCore

enum DeterministicImageFixture {
  static func makeCommonImageDecoder() throws -> AppleRawDecoder {
    try AppleRawDecoder(rawFilterProvider: NoAppleRAWFilterProvider())
  }

  static func makeDirectory() throws -> URL {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("PhotoSuite-RenderCoreTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(
      at: directory,
      withIntermediateDirectories: true
    )
    return directory
  }

  static func makePNG(
    in directory: URL,
    name: String = "fixture.png",
    width: Int = 8,
    height: Int = 6
  ) throws -> URL {
    var pixels = [UInt8]()
    pixels.reserveCapacity(width * height * 4)

    for y in 0..<height {
      for x in 0..<width {
        pixels.append(UInt8(20 + x * 28))
        pixels.append(UInt8(24 + y * 36))
        pixels.append(UInt8(16 + ((x + y) % 6) * 36))
        pixels.append(255)
      }
    }

    let data = Data(pixels)
    guard
      let provider = CGDataProvider(data: data as CFData),
      let image = CGImage(
        width: width,
        height: height,
        bitsPerComponent: 8,
        bitsPerPixel: 32,
        bytesPerRow: width * 4,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),
        provider: provider,
        decode: nil,
        shouldInterpolate: false,
        intent: .defaultIntent
      )
    else {
      throw FixtureError.imageCreationFailed
    }

    let url = directory.appendingPathComponent(name)
    guard
      let destination = CGImageDestinationCreateWithURL(
        url as CFURL,
        UTType.png.identifier as CFString,
        1,
        nil
      )
    else {
      throw FixtureError.destinationCreationFailed
    }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else {
      throw FixtureError.encodingFailed
    }
    return url
  }

  static func makeOrientedTIFF(
    in directory: URL,
    name: String = "oriented.tiff"
  ) throws -> URL {
    let width = 2
    let height = 3
    let red: [UInt8] = [240, 20, 20, 255]
    let blue: [UInt8] = [20, 20, 240, 255]
    let data = Data((0..<height).flatMap { _ in red + blue })
    guard
      let provider = CGDataProvider(data: data as CFData),
      let image = CGImage(
        width: width,
        height: height,
        bitsPerComponent: 8,
        bitsPerPixel: 32,
        bytesPerRow: width * 4,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),
        provider: provider,
        decode: nil,
        shouldInterpolate: false,
        intent: .defaultIntent
      )
    else {
      throw FixtureError.imageCreationFailed
    }

    let url = directory.appendingPathComponent(name)
    guard
      let destination = CGImageDestinationCreateWithURL(
        url as CFURL,
        UTType.tiff.identifier as CFString,
        1,
        nil
      )
    else {
      throw FixtureError.destinationCreationFailed
    }
    CGImageDestinationAddImage(
      destination,
      image,
      [kCGImagePropertyOrientation: 6] as CFDictionary
    )
    guard CGImageDestinationFinalize(destination) else {
      throw FixtureError.encodingFailed
    }
    return url
  }

  static func checksum(of url: URL) throws -> String {
    SHA256.hash(data: try Data(contentsOf: url))
      .map { String(format: "%02x", $0) }
      .joined()
  }

  static func rgba8Data(from image: CGImage) throws -> Data {
    let bytesPerRow = image.width * 4
    var data = Data(count: bytesPerRow * image.height)
    let created = data.withUnsafeMutableBytes { buffer -> Bool in
      guard
        let address = buffer.baseAddress,
        let context = CGContext(
          data: address,
          width: image.width,
          height: image.height,
          bitsPerComponent: 8,
          bytesPerRow: bytesPerRow,
          space: CGColorSpace(name: CGColorSpace.sRGB)!,
          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
      else {
        return false
      }
      context.draw(
        image,
        in: CGRect(x: 0, y: 0, width: image.width, height: image.height)
      )
      return true
    }
    guard created else { throw FixtureError.imageCreationFailed }
    return data
  }

  static func pixel(
    x: Int,
    y: Int,
    width: Int,
    in data: Data
  ) -> (red: UInt8, green: UInt8, blue: UInt8, alpha: UInt8) {
    let offset = (y * width + x) * 4
    return (
      data[offset],
      data[offset + 1],
      data[offset + 2],
      data[offset + 3]
    )
  }

  enum FixtureError: Error {
    case imageCreationFailed
    case destinationCreationFailed
    case encodingFailed
  }
}

private struct NoAppleRAWFilterProvider: AppleRAWFilterProviding {
  func makeFilter(imageURL: URL) -> (any AppleRAWFilterAccess)? {
    nil
  }
}
