// SPDX-License-Identifier: MPL-2.0

import Foundation
import PhotoDomain
import XCTest

@testable import RenderCore

final class DNGContainerReaderTests: XCTestCase {
  func testDNGVersionUsesFourByteVersionAndExposesWriterContract() throws {
    let version = try XCTUnwrap(DNGVersion(bytes: [1, 7, 1, 0]))

    XCTAssertEqual(version, .dng171)
    XCTAssertEqual(version.stringValue, "1.7.1")
    XCTAssertEqual(version.bytes, [1, 7, 1, 0])
    XCTAssertTrue(version.isSupportedMetadataVersion)
    XCTAssertEqual(DNGWriterContract.metadataOnly.targetVersion, .dng171)
    XCTAssertTrue(DNGWriterContract.metadataOnly.supportsMetadataPatch)
    XCTAssertFalse(DNGWriterContract.metadataOnly.supportsRawPixelEncoding)
  }

  func testRawCapabilityResultDecodesBeforeSourceKindWasAdded() throws {
    let legacyData = Data(
      #"{"supportedCameraModels":["Camera"],"supportedDecoderVersions":[]}"#.utf8
    )
    let result = try JSONDecoder().decode(RawCapabilityResult.self, from: legacyData)

    XCTAssertEqual(result.supportedCameraModels, ["Camera"])
    XCTAssertEqual(result.sourceKind, .unknown)
  }

  func testReadsLittleEndianDNGMetadataWithoutReadingRawPayload() throws {
    let fixture = makeDNGFixture(byteOrder: .littleEndian)
    let inspection = try DNGMetadataReader().inspect(data: fixture)

    XCTAssertEqual(inspection.state, .valid)
    XCTAssertEqual(inspection.dngVersion, .dng171)
    XCTAssertEqual(inspection.byteOrder, .littleEndian)
    XCTAssertFalse(inspection.isBigTIFF)
    XCTAssertEqual(inspection.metadata?.imageWidth, 4)
    XCTAssertEqual(inspection.metadata?.imageHeight, 3)
    XCTAssertEqual(inspection.metadata?.bitsPerSample, [16])
    XCTAssertEqual(inspection.metadata?.photometricInterpretation, 32803)
    XCTAssertEqual(inspection.metadata?.make, "PhotoSuite")
    XCTAssertEqual(inspection.metadata?.model, "Test Camera")
    XCTAssertEqual(inspection.metadata?.uniqueCameraModel, "PhotoSuite Test Camera")
    XCTAssertEqual(
      inspection.metadata?.activeArea, DNGActiveArea(top: 0, left: 0, bottom: 3, right: 4))
    XCTAssertEqual(inspection.metadata?.cfaPattern, [0, 1, 1, 2])
    XCTAssertTrue(inspection.metadata?.hasRawImageData == true)
  }

  func testReadsBigEndianDNGMetadata() throws {
    let fixture = makeDNGFixture(byteOrder: .bigEndian)
    let inspection = try DNGMetadataReader().inspect(data: fixture)

    XCTAssertEqual(inspection.state, .valid)
    XCTAssertEqual(inspection.dngVersion, .dng171)
    XCTAssertEqual(inspection.byteOrder, .bigEndian)
    XCTAssertEqual(inspection.metadata?.whiteLevel, [4095])
  }

  func testNonDNGTIFFAndCommonImageAreNotClassifiedAsDNG() throws {
    let tiff = makeClassicTIFFWithoutDNGVersion()
    let tiffInspection = try DNGMetadataReader().inspect(data: tiff)
    XCTAssertEqual(tiffInspection.state, .notDNG)
    XCTAssertNil(tiffInspection.metadata)

    let pngInspection = try DNGMetadataReader().inspect(
      data: Data([
        0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A,
      ]))
    XCTAssertEqual(pngInspection.state, .notDNG)
  }

  func testMalformedAndUnsupportedContainersAreClassifiedSafely() throws {
    var truncated = Data([0x49, 0x49, 0x2A, 0x00, 0x08, 0x00, 0x00, 0x00])
    truncated.append(contentsOf: [0x01])
    let truncatedInspection = try DNGMetadataReader().inspect(data: truncated)
    XCTAssertEqual(truncatedInspection.state, .malformed)
    XCTAssertEqual(truncatedInspection.issue, .invalidIFDOffset)

    let bigTIFF = makeBigTIFFHeader()
    let bigTIFFInspection = try DNGMetadataReader().inspect(data: bigTIFF)
    XCTAssertEqual(bigTIFFInspection.state, .unsupportedContainer)
    XCTAssertEqual(bigTIFFInspection.issue, .bigTIFFUnsupported)

    var future = makeDNGFixture(byteOrder: .littleEndian)
    writeBytes([1, 8, 0, 0], into: &future, at: 18)
    let futureInspection = try DNGMetadataReader().inspect(data: future)
    XCTAssertEqual(futureInspection.state, .unsupportedVersion)
    XCTAssertEqual(futureInspection.dngVersion, DNGVersion(major: 1, minor: 8))
  }

  func testMaximumFileSizeStopsUntrustedRead() throws {
    let fixture = makeDNGFixture(byteOrder: .littleEndian)
    XCTAssertThrowsError(
      try DNGMetadataReader().inspect(
        data: fixture,
        maximumFileSize: UInt64(fixture.count - 1)
      )
    ) { error in
      XCTAssertEqual(
        error as? DNGReaderError,
        .fileTooLarge(actual: UInt64(fixture.count), limit: UInt64(fixture.count - 1))
      )
    }
  }

  func testOutOfBoundsRawSegmentIsMalformedInsteadOfClaimingPixelData() throws {
    var fixture = makeDNGFixture(byteOrder: .littleEndian)
    let stripOffsetEntry = 8 + 2 + (14 * 12)
    writeUInt32(500, into: &fixture, at: stripOffsetEntry + 8, byteOrder: .littleEndian)

    let inspection = try DNGMetadataReader().inspect(data: fixture)

    XCTAssertEqual(inspection.state, .malformed)
    XCTAssertEqual(inspection.issue, .invalidTagValue)
    XCTAssertNil(inspection.metadata)
  }

  func testMetadataWriterPatchesExistingASCIIFieldsAndLeavesSourceUnchanged() throws {
    let directory = try DeterministicImageFixture.makeDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let sourceURL = directory.appendingPathComponent("source.dng")
    let destinationURL = directory.appendingPathComponent("patched.dng")
    let sourceData = makeDNGFixture(byteOrder: .littleEndian)
    try sourceData.write(to: sourceURL)

    let result = try DNGMetadataWriter().write(
      DNGWriteRequest(
        sourceURL: sourceURL,
        destinationURL: destinationURL,
        metadataPatch: DNGMetadataPatch(
          make: "Open Photo",
          model: "Pro Camera",
          uniqueCameraModel: "Open Photo Pro Camera"
        )
      )
    )

    XCTAssertEqual(result.destinationURL, destinationURL)
    XCTAssertEqual(result.contract, DNGWriterContract.metadataOnly)
    XCTAssertEqual(try Data(contentsOf: sourceURL), sourceData)
    XCTAssertEqual(try Data(contentsOf: destinationURL).count, sourceData.count)

    let inspection = try DNGMetadataReader().inspect(
      DNGInspectionRequest(sourceURL: destinationURL)
    )
    XCTAssertEqual(inspection.state, .valid)
    XCTAssertEqual(inspection.metadata?.make, "Open Photo")
    XCTAssertEqual(inspection.metadata?.model, "Pro Camera")
    XCTAssertEqual(inspection.metadata?.uniqueCameraModel, "Open Photo Pro Camera")
    XCTAssertEqual(inspection.metadata?.imageWidth, 4)
    XCTAssertEqual(inspection.metadata?.imageHeight, 3)
  }

  func testMetadataWriterPatchesBigEndianASCIIFields() throws {
    let directory = try DeterministicImageFixture.makeDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let sourceURL = directory.appendingPathComponent("big-endian-source.dng")
    let destinationURL = directory.appendingPathComponent("big-endian-patched.dng")
    try makeDNGFixture(byteOrder: .bigEndian).write(to: sourceURL)

    _ = try DNGMetadataWriter().write(
      DNGWriteRequest(
        sourceURL: sourceURL,
        destinationURL: destinationURL,
        metadataPatch: DNGMetadataPatch(make: "Open Photo")
      )
    )

    let inspection = try DNGMetadataReader().inspect(
      DNGInspectionRequest(sourceURL: destinationURL)
    )
    XCTAssertEqual(inspection.state, .valid)
    XCTAssertEqual(inspection.byteOrder, .bigEndian)
    XCTAssertEqual(inspection.metadata?.make, "Open Photo")
  }

  func testMetadataWriterRejectsOffsetRewriteWhenValueDoesNotFitExistingField() throws {
    let directory = try DeterministicImageFixture.makeDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let sourceURL = directory.appendingPathComponent("source.dng")
    let destinationURL = directory.appendingPathComponent("too-long.dng")
    try makeDNGFixture(byteOrder: .littleEndian).write(to: sourceURL)

    XCTAssertThrowsError(
      try DNGMetadataWriter().write(
        DNGWriteRequest(
          sourceURL: sourceURL,
          destinationURL: destinationURL,
          metadataPatch: DNGMetadataPatch(model: "This value cannot fit without moving any offsets")
        )
      )
    ) { error in
      XCTAssertEqual(
        error as? DNGWriterError,
        .metadataValueTooLong(tag: 272, maximumBytes: 12)
      )
    }
    XCTAssertFalse(FileManager.default.fileExists(atPath: destinationURL.path))
  }

  func testMetadataWriterRejectsUnavailableTagAndSourceDestinationConflict() throws {
    let directory = try DeterministicImageFixture.makeDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let sourceURL = directory.appendingPathComponent("source.dng")
    try makeDNGFixture(byteOrder: .littleEndian).write(to: sourceURL)

    XCTAssertThrowsError(
      try DNGMetadataWriter().write(
        DNGWriteRequest(
          sourceURL: sourceURL,
          destinationURL: directory.appendingPathComponent("missing-tag.dng"),
          metadataPatch: DNGMetadataPatch(software: "PhotoSuite")
        )
      )
    ) { error in
      XCTAssertEqual(error as? DNGWriterError, .metadataTagUnavailable(305))
    }

    XCTAssertThrowsError(
      try DNGMetadataWriter().write(
        DNGWriteRequest(
          sourceURL: sourceURL,
          destinationURL: sourceURL,
          metadataPatch: DNGMetadataPatch(make: "Other")
        )
      )
    ) { error in
      XCTAssertEqual(error as? DNGWriterError, .sourceDestinationConflict(sourceURL))
    }
  }

  func testRawCapabilityClassifiesDNGWithoutClaimingCIRAWDecoderVersion() async throws {
    let fixtureURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("photosuite-(UUID().uuidString).dng")
    try makeDNGFixture(byteOrder: .littleEndian).write(to: fixtureURL)
    defer { try? FileManager.default.removeItem(at: fixtureURL) }

    let decoder = try AppleRawDecoder()
    let capabilities = try await decoder.capabilities(
      RawCapabilityRequest(sourceURL: fixtureURL)
    )

    XCTAssertEqual(capabilities.sourceKind, .dngContainer)
    XCTAssertTrue(capabilities.supportedDecoderVersions.isEmpty)
  }

  func testRawCapabilityClassifiesImageIOImageWithoutClaimingRAWVersions() async throws {
    let directory = try DeterministicImageFixture.makeDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let source = try DeterministicImageFixture.makePNG(in: directory)

    let decoder = try AppleRawDecoder()
    let capabilities = try await decoder.capabilities(
      RawCapabilityRequest(sourceURL: source)
    )

    XCTAssertEqual(capabilities.sourceKind, .imageIOImage)
    XCTAssertTrue(capabilities.supportedDecoderVersions.isEmpty)
  }
}

extension DNGContainerReaderTests {
  fileprivate func makeDNGFixture(byteOrder: DNGByteOrder) -> Data {
    let entryCount = 16
    let ifdOffset = 8
    let ifdSize = 2 + (entryCount * 12) + 4
    var data = Data(repeating: 0, count: 512)
    data.replaceSubrange(0..<2, with: byteOrder == .littleEndian ? [0x49, 0x49] : [0x4D, 0x4D])
    writeUInt16(42, into: &data, at: 2, byteOrder: byteOrder)
    writeUInt32(UInt32(ifdOffset), into: &data, at: 4, byteOrder: byteOrder)
    writeUInt16(UInt16(entryCount), into: &data, at: ifdOffset, byteOrder: byteOrder)

    var entry = ifdOffset + 2
    writeEntry(
      tag: 50706, type: 1, count: 4, bytes: [1, 7, 1, 0], into: &data, at: &entry,
      byteOrder: byteOrder)
    writeEntry(
      tag: 50707, type: 1, count: 4, bytes: [1, 4, 0, 0], into: &data, at: &entry,
      byteOrder: byteOrder)
    writeEntry(tag: 256, type: 4, count: 1, value: 4, into: &data, at: &entry, byteOrder: byteOrder)
    writeEntry(tag: 257, type: 4, count: 1, value: 3, into: &data, at: &entry, byteOrder: byteOrder)
    writeEntry(
      tag: 258, type: 3, count: 1, value: 16, into: &data, at: &entry, byteOrder: byteOrder)
    writeEntry(tag: 259, type: 3, count: 1, value: 1, into: &data, at: &entry, byteOrder: byteOrder)
    writeEntry(
      tag: 262, type: 3, count: 1, value: 32803, into: &data, at: &entry, byteOrder: byteOrder)
    writeEntry(
      tag: 271, type: 2, count: 11, offset: 256, into: &data, at: &entry, byteOrder: byteOrder)
    writeEntry(
      tag: 272, type: 2, count: 12, offset: 267, into: &data, at: &entry, byteOrder: byteOrder)
    writeEntry(
      tag: 50708, type: 2, count: 23, offset: 279, into: &data, at: &entry, byteOrder: byteOrder)
    writeEntry(
      tag: 33421, type: 3, count: 2, shorts: [2, 2], into: &data, at: &entry, byteOrder: byteOrder)
    writeEntry(
      tag: 33422, type: 1, count: 4, bytes: [0, 1, 1, 2], into: &data, at: &entry,
      byteOrder: byteOrder)
    writeEntry(
      tag: 50829, type: 4, count: 4, longs: [0, 0, 3, 4], into: &data, at: &entry,
      byteOrder: byteOrder)
    writeEntry(
      tag: 50717, type: 4, count: 1, value: 4095, into: &data, at: &entry, byteOrder: byteOrder)
    writeEntry(
      tag: 273, type: 4, count: 1, value: 400, into: &data, at: &entry, byteOrder: byteOrder)
    writeEntry(
      tag: 279, type: 4, count: 1, value: 24, into: &data, at: &entry, byteOrder: byteOrder)
    writeUInt32(0, into: &data, at: ifdOffset + ifdSize - 4, byteOrder: byteOrder)

    data.replaceSubrange(256..<267, with: Array("PhotoSuite\0".utf8))
    data.replaceSubrange(267..<279, with: Array("Test Camera\0".utf8))
    data.replaceSubrange(279..<302, with: Array("PhotoSuite Test Camera\0".utf8))
    return data
  }

  fileprivate func makeClassicTIFFWithoutDNGVersion() -> Data {
    var data = Data(repeating: 0, count: 32)
    data.replaceSubrange(0..<2, with: [0x49, 0x49])
    writeUInt16(42, into: &data, at: 2, byteOrder: .littleEndian)
    writeUInt32(8, into: &data, at: 4, byteOrder: .littleEndian)
    writeUInt16(0, into: &data, at: 8, byteOrder: .littleEndian)
    return data
  }

  fileprivate func makeBigTIFFHeader() -> Data {
    var data = Data(repeating: 0, count: 16)
    data.replaceSubrange(0..<2, with: [0x49, 0x49])
    writeUInt16(43, into: &data, at: 2, byteOrder: .littleEndian)
    writeUInt16(8, into: &data, at: 4, byteOrder: .littleEndian)
    return data
  }

  fileprivate func writeEntry(
    tag: UInt16,
    type: UInt16,
    count: UInt32,
    value: UInt32? = nil,
    offset: UInt32? = nil,
    into data: inout Data,
    at entry: inout Int,
    byteOrder: DNGByteOrder
  ) {
    writeUInt16(tag, into: &data, at: entry, byteOrder: byteOrder)
    writeUInt16(type, into: &data, at: entry + 2, byteOrder: byteOrder)
    writeUInt32(count, into: &data, at: entry + 4, byteOrder: byteOrder)
    if let offset {
      writeUInt32(offset, into: &data, at: entry + 8, byteOrder: byteOrder)
    } else if let value {
      if type == 3 && count == 1 {
        writeUInt16(UInt16(value), into: &data, at: entry + 8, byteOrder: byteOrder)
      } else {
        writeUInt32(value, into: &data, at: entry + 8, byteOrder: byteOrder)
      }
    }
    entry += 12
  }

  fileprivate func writeEntry(
    tag: UInt16,
    type: UInt16,
    count: UInt32,
    shorts: [UInt16],
    into data: inout Data,
    at entry: inout Int,
    byteOrder: DNGByteOrder
  ) {
    writeUInt16(tag, into: &data, at: entry, byteOrder: byteOrder)
    writeUInt16(type, into: &data, at: entry + 2, byteOrder: byteOrder)
    writeUInt32(count, into: &data, at: entry + 4, byteOrder: byteOrder)
    if shorts.count == 1 {
      writeUInt16(shorts[0], into: &data, at: entry + 8, byteOrder: byteOrder)
    } else {
      writeUInt16(shorts[0], into: &data, at: entry + 8, byteOrder: byteOrder)
      writeUInt16(shorts[1], into: &data, at: entry + 10, byteOrder: byteOrder)
    }
    entry += 12
  }

  fileprivate func writeEntry(
    tag: UInt16,
    type: UInt16,
    count: UInt32,
    longs: [UInt32],
    into data: inout Data,
    at entry: inout Int,
    byteOrder: DNGByteOrder
  ) {
    let payloadOffset = 320
    writeUInt16(tag, into: &data, at: entry, byteOrder: byteOrder)
    writeUInt16(type, into: &data, at: entry + 2, byteOrder: byteOrder)
    writeUInt32(count, into: &data, at: entry + 4, byteOrder: byteOrder)
    writeUInt32(UInt32(payloadOffset), into: &data, at: entry + 8, byteOrder: byteOrder)
    for (index, number) in longs.enumerated() {
      writeUInt32(number, into: &data, at: payloadOffset + (index * 4), byteOrder: byteOrder)
    }
    entry += 12
  }

  fileprivate func writeEntry(
    tag: UInt16,
    type: UInt16,
    count: UInt32,
    bytes: [UInt8],
    into data: inout Data,
    at entry: inout Int,
    byteOrder: DNGByteOrder
  ) {
    writeUInt16(tag, into: &data, at: entry, byteOrder: byteOrder)
    writeUInt16(type, into: &data, at: entry + 2, byteOrder: byteOrder)
    writeUInt32(count, into: &data, at: entry + 4, byteOrder: byteOrder)
    data.replaceSubrange(entry + 8..<(entry + 8 + min(4, bytes.count)), with: bytes.prefix(4))
    entry += 12
  }

  fileprivate func writeBytes(_ bytes: [UInt8], into data: inout Data, at offset: Int) {
    data.replaceSubrange(offset..<(offset + bytes.count), with: bytes)
  }

  fileprivate func writeUInt16(
    _ value: UInt16, into data: inout Data, at offset: Int, byteOrder: DNGByteOrder
  ) {
    let bytes: [UInt8]
    switch byteOrder {
    case .littleEndian:
      bytes = [UInt8(value & 0xFF), UInt8(value >> 8)]
    case .bigEndian:
      bytes = [UInt8(value >> 8), UInt8(value & 0xFF)]
    }
    data.replaceSubrange(offset..<(offset + 2), with: bytes)
  }

  fileprivate func writeUInt32(
    _ value: UInt32, into data: inout Data, at offset: Int, byteOrder: DNGByteOrder
  ) {
    let bytes: [UInt8]
    switch byteOrder {
    case .littleEndian:
      bytes = [
        UInt8(value & 0xFF), UInt8((value >> 8) & 0xFF), UInt8((value >> 16) & 0xFF),
        UInt8(value >> 24),
      ]
    case .bigEndian:
      bytes = [
        UInt8(value >> 24), UInt8((value >> 16) & 0xFF), UInt8((value >> 8) & 0xFF),
        UInt8(value & 0xFF),
      ]
    }
    data.replaceSubrange(offset..<(offset + 4), with: bytes)
  }
}
