// SPDX-License-Identifier: MPL-2.0

import Foundation
import PhotoDomain

/// A bounded TIFF/DNG metadata reader.
///
/// This reader deliberately stops at container metadata. It validates classic
/// TIFF offsets and values, reads the DNG version and common raw-image tags,
/// and never decodes or rewrites raw pixels. CIRAW remains the decode authority
/// when Apple's filter identifies a real raw source.
public struct DNGMetadataReader: DNGContainerReader, Sendable {
  private static let maximumIFDEntries: UInt16 = 4_096
  private static let maximumSelectedValues = 1_024

  public init() {}

  public func inspect(_ request: DNGInspectionRequest) throws -> DNGContainerInspection {
    let values = try? request.sourceURL.resourceValues(
      forKeys: [.isRegularFileKey, .isReadableKey, .fileSizeKey]
    )
    guard values?.isRegularFile == true, values?.isReadable != false else {
      throw DNGReaderError.sourceUnavailable(request.sourceURL)
    }
    let fileSize = UInt64(values?.fileSize ?? 0)
    guard fileSize <= request.maximumFileSize else {
      throw DNGReaderError.fileTooLarge(actual: fileSize, limit: request.maximumFileSize)
    }
    guard let data = try? Data(contentsOf: request.sourceURL, options: [.mappedIfSafe]) else {
      throw DNGReaderError.sourceUnavailable(request.sourceURL)
    }
    return try inspect(data: data, maximumFileSize: request.maximumFileSize)
  }

  public func inspect(
    data: Data,
    maximumFileSize: UInt64 = DNGInspectionRequest.defaultMaximumFileSize
  ) throws -> DNGContainerInspection {
    guard UInt64(data.count) <= maximumFileSize else {
      throw DNGReaderError.fileTooLarge(actual: UInt64(data.count), limit: maximumFileSize)
    }
    return parse(data: data)
  }

  private func parse(data: Data) -> DNGContainerInspection {
    let byteCount = UInt64(data.count)
    guard data.count >= 2 else {
      return inspection(
        state: .notDNG,
        byteOrder: nil,
        isBigTIFF: false,
        sourceByteCount: byteCount
      )
    }

    let byteOrder: DNGByteOrder
    switch (data[data.startIndex], data[data.startIndex + 1]) {
    case (0x49, 0x49): byteOrder = .littleEndian
    case (0x4D, 0x4D): byteOrder = .bigEndian
    default:
      return inspection(
        state: .notDNG,
        byteOrder: nil,
        isBigTIFF: false,
        sourceByteCount: byteCount
      )
    }

    guard data.count >= 8 else {
      return inspection(
        state: .malformed,
        byteOrder: byteOrder,
        isBigTIFF: false,
        issue: .truncatedHeader,
        sourceByteCount: byteCount
      )
    }
    guard let magic = readUInt16(from: data, at: 2, byteOrder: byteOrder) else {
      return inspection(
        state: .malformed,
        byteOrder: byteOrder,
        isBigTIFF: false,
        issue: .truncatedHeader,
        sourceByteCount: byteCount
      )
    }
    if magic == 43 {
      return inspection(
        state: .unsupportedContainer,
        byteOrder: byteOrder,
        isBigTIFF: true,
        issue: .bigTIFFUnsupported,
        sourceByteCount: byteCount
      )
    }
    guard magic == 42 else {
      return inspection(
        state: .notDNG,
        byteOrder: byteOrder,
        isBigTIFF: false,
        issue: .invalidTIFFMagic,
        sourceByteCount: byteCount
      )
    }
    guard let firstIFDOffset = readUInt32(from: data, at: 4, byteOrder: byteOrder) else {
      return inspection(
        state: .malformed,
        byteOrder: byteOrder,
        isBigTIFF: false,
        issue: .truncatedHeader,
        sourceByteCount: byteCount
      )
    }
    guard firstIFDOffset != 0 else {
      return inspection(
        state: .malformed,
        byteOrder: byteOrder,
        isBigTIFF: false,
        issue: .missingFirstIFD,
        sourceByteCount: byteCount
      )
    }
    let entriesResult = parseEntries(
      in: data,
      offset: Int(firstIFDOffset),
      byteOrder: byteOrder
    )
    guard case .success(let entries) = entriesResult else {
      let issue: DNGContainerIssue
      if case .failure(let parsedIssue) = entriesResult {
        issue = parsedIssue
      } else {
        issue = .invalidTagValue
      }
      return inspection(
        state: .malformed,
        byteOrder: byteOrder,
        isBigTIFF: false,
        issue: issue,
        sourceByteCount: byteCount
      )
    }

    guard let versionEntry = entries.first(where: { $0.tag == 50706 }) else {
      return inspection(
        state: .notDNG,
        byteOrder: byteOrder,
        isBigTIFF: false,
        issue: .missingDNGVersion,
        sourceByteCount: byteCount
      )
    }
    guard versionEntry.type == 1, versionEntry.count == 4,
      let version = DNGVersion(bytes: bytes(for: versionEntry, in: data))
    else {
      return inspection(
        state: .malformed,
        byteOrder: byteOrder,
        isBigTIFF: false,
        issue: .invalidTagValue,
        sourceByteCount: byteCount
      )
    }

    let backwardVersion: DNGVersion? = entries.first(where: { $0.tag == 50707 }).flatMap { entry in
      guard entry.type == 1, entry.count == 4 else { return nil }
      return DNGVersion(bytes: bytes(for: entry, in: data))
    }
    let metadataResult = metadata(from: entries, in: data, byteOrder: byteOrder)
    guard case .success(let metadata) = metadataResult else {
      return inspection(
        state: .malformed,
        version: version,
        backwardVersion: backwardVersion,
        byteOrder: byteOrder,
        isBigTIFF: false,
        issue: .invalidTagValue,
        sourceByteCount: byteCount
      )
    }
    let dngState: DNGContainerState =
      version.isSupportedMetadataVersion
      ? .valid
      : .unsupportedVersion
    return inspection(
      state: dngState,
      version: version,
      backwardVersion: backwardVersion,
      byteOrder: byteOrder,
      isBigTIFF: false,
      metadata: metadata,
      issue: version.isSupportedMetadataVersion ? nil : .unsupportedDNGVersion,
      sourceByteCount: byteCount
    )
  }

  private struct Entry: Sendable {
    let tag: UInt16
    let type: UInt16
    let count: UInt32
    let valuePosition: Int
    let valueSize: Int
  }

  private func parseEntries(
    in data: Data,
    offset: Int,
    byteOrder: DNGByteOrder
  ) -> Result<[Entry], DNGContainerIssue> {
    guard offset >= 0, offset <= data.count - 2 else {
      return .failure(.invalidIFDOffset)
    }
    guard let entryCount = readUInt16(from: data, at: offset, byteOrder: byteOrder),
      entryCount <= Self.maximumIFDEntries
    else {
      return .failure(.truncatedIFD)
    }
    let tableSize = Int(entryCount) * 12 + 2 + 4
    guard tableSize <= data.count - offset else {
      return .failure(.truncatedIFD)
    }

    var entries: [Entry] = []
    entries.reserveCapacity(Int(entryCount))
    for index in 0..<Int(entryCount) {
      let entryOffset = offset + 2 + (index * 12)
      guard
        let tag = readUInt16(from: data, at: entryOffset, byteOrder: byteOrder),
        let type = readUInt16(from: data, at: entryOffset + 2, byteOrder: byteOrder),
        let count = readUInt32(from: data, at: entryOffset + 4, byteOrder: byteOrder),
        let typeSize = Self.typeSize(type),
        let valueSize = checkedByteCount(count: count, typeSize: typeSize)
      else {
        return .failure(.invalidTagValue)
      }

      let valuePosition: Int
      if valueSize <= 4 {
        valuePosition = entryOffset + 8
      } else {
        guard
          let valueOffset = readUInt32(
            from: data,
            at: entryOffset + 8,
            byteOrder: byteOrder
          )
        else {
          return .failure(.invalidTagValue)
        }
        guard
          valueOffset <= UInt32(data.count),
          valueSize <= data.count - Int(valueOffset)
        else {
          return .failure(.invalidTagValue)
        }
        valuePosition = Int(valueOffset)
      }
      entries.append(
        Entry(
          tag: tag,
          type: type,
          count: count,
          valuePosition: valuePosition,
          valueSize: valueSize
        )
      )
    }
    return .success(entries)
  }

  private func metadata(
    from entries: [Entry],
    in data: Data,
    byteOrder: DNGByteOrder
  ) -> Result<DNGContainerMetadata, DNGContainerIssue> {
    var values: [UInt16: Entry] = [:]
    for entry in entries {
      values[entry.tag] = entry
    }
    let width = unsignedValues(values[256], in: data, byteOrder: byteOrder)?.first
    let height = unsignedValues(values[257], in: data, byteOrder: byteOrder)?.first
    let bitsPerSample = unsigned16Values(values[258], in: data, byteOrder: byteOrder)
    let compression = unsignedValues(values[259], in: data, byteOrder: byteOrder)?.first
      .flatMap(UInt16.init)
    let photometric = unsignedValues(values[262], in: data, byteOrder: byteOrder)?.first
      .flatMap(UInt16.init)
    let samplesPerPixel = unsignedValues(values[277], in: data, byteOrder: byteOrder)?.first
      .flatMap(UInt16.init)
    let cfaDimensions = unsigned16Values(values[33421], in: data, byteOrder: byteOrder)
    let activeValues = unsignedValues(values[50829], in: data, byteOrder: byteOrder)
    let activeArea: DNGActiveArea?
    if let activeValues, activeValues.count == 4 {
      activeArea = DNGActiveArea(
        top: activeValues[0],
        left: activeValues[1],
        bottom: activeValues[2],
        right: activeValues[3]
      )
    } else {
      activeArea = nil
    }

    let stripOffsets = unsignedValues(values[273], in: data, byteOrder: byteOrder) ?? []
    let stripByteCounts = unsignedValues(values[279], in: data, byteOrder: byteOrder) ?? []
    let tileOffsets = unsignedValues(values[324], in: data, byteOrder: byteOrder) ?? []
    let tileByteCounts = unsignedValues(values[325], in: data, byteOrder: byteOrder) ?? []
    guard
      segmentsAreInBounds(stripOffsets, byteCounts: stripByteCounts, dataCount: data.count),
      segmentsAreInBounds(tileOffsets, byteCounts: tileByteCounts, dataCount: data.count)
    else {
      return .failure(.invalidTagValue)
    }
    let hasStrips = !stripOffsets.isEmpty && stripOffsets.count == stripByteCounts.count
    let hasTiles = !tileOffsets.isEmpty && tileOffsets.count == tileByteCounts.count

    return .success(
      DNGContainerMetadata(
        imageWidth: width,
        imageHeight: height,
        bitsPerSample: bitsPerSample,
        compression: compression,
        photometricInterpretation: photometric,
        samplesPerPixel: samplesPerPixel,
        make: asciiValue(values[271], in: data),
        model: asciiValue(values[272], in: data),
        uniqueCameraModel: asciiValue(values[50708], in: data),
        cfaRepeatPatternWidth: cfaDimensions.count >= 1 ? cfaDimensions[0] : nil,
        cfaRepeatPatternHeight: cfaDimensions.count >= 2 ? cfaDimensions[1] : nil,
        cfaPattern: byteValues(values[33422], in: data),
        activeArea: activeArea,
        whiteLevel: unsignedValues(values[50717], in: data, byteOrder: byteOrder) ?? [],
        blackLevel: rationalValues(values[50714], in: data, byteOrder: byteOrder),
        defaultCropOrigin: rationalValues(values[50719], in: data, byteOrder: byteOrder),
        defaultCropSize: rationalValues(values[50720], in: data, byteOrder: byteOrder),
        colorMatrix1: rationalValues(values[50721], in: data, byteOrder: byteOrder),
        colorMatrix2: rationalValues(values[50722], in: data, byteOrder: byteOrder),
        stripCount: hasStrips ? UInt32(stripOffsets.count) : 0,
        tileCount: hasTiles ? UInt32(tileOffsets.count) : 0,
        hasRawImageData: hasStrips || hasTiles,
        recognizedTagIDs: entries.map(\.tag).sorted()
      ))
  }

  private func segmentsAreInBounds(
    _ offsets: [UInt32],
    byteCounts: [UInt32],
    dataCount: Int
  ) -> Bool {
    guard offsets.count == byteCounts.count else {
      return offsets.isEmpty && byteCounts.isEmpty
    }
    for (offset, byteCount) in zip(offsets, byteCounts) {
      guard offset <= UInt32(dataCount),
        byteCount <= UInt32(dataCount - Int(offset))
      else {
        return false
      }
    }
    return true
  }

  private func unsignedValues(
    _ entry: Entry?,
    in data: Data,
    byteOrder: DNGByteOrder
  ) -> [UInt32]? {
    guard let entry, entry.count <= UInt32(Self.maximumSelectedValues) else { return nil }
    switch entry.type {
    case 3:
      return unsigned16Values(entry, in: data, byteOrder: byteOrder).map(UInt32.init)
    case 4:
      return stride(from: 0, to: Int(entry.count), by: 1).compactMap { index in
        readUInt32(
          from: data,
          at: entry.valuePosition + (index * 4),
          byteOrder: byteOrder
        )
      }
    default:
      return nil
    }
  }

  private func unsigned16Values(
    _ entry: Entry?,
    in data: Data,
    byteOrder: DNGByteOrder
  ) -> [UInt16] {
    guard let entry, entry.type == 3,
      entry.count <= UInt32(Self.maximumSelectedValues)
    else { return [] }
    return stride(from: 0, to: Int(entry.count), by: 1).compactMap { index in
      readUInt16(
        from: data,
        at: entry.valuePosition + (index * 2),
        byteOrder: byteOrder
      )
    }
  }

  private func byteValues(_ entry: Entry?, in data: Data) -> [UInt8] {
    guard let entry, entry.type == 1 || entry.type == 7,
      entry.count <= UInt32(Self.maximumSelectedValues)
    else { return [] }
    return Array(data[entry.valuePosition..<(entry.valuePosition + entry.valueSize)])
  }

  private func asciiValue(_ entry: Entry?, in data: Data) -> String? {
    guard let entry, entry.type == 2,
      entry.count <= UInt32(Self.maximumSelectedValues)
    else { return nil }
    let bytes = Array(data[entry.valuePosition..<(entry.valuePosition + entry.valueSize)])
    let withoutNull = bytes.prefix { $0 != 0 }
    let value =
      String(bytes: withoutNull, encoding: .utf8)
      ?? String(bytes: withoutNull, encoding: .ascii)
    let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed?.isEmpty == true ? nil : trimmed
  }

  private func rationalValues(
    _ entry: Entry?,
    in data: Data,
    byteOrder: DNGByteOrder
  ) -> [Double] {
    guard let entry, entry.type == 5 || entry.type == 10,
      entry.count <= UInt32(Self.maximumSelectedValues)
    else { return [] }
    return stride(from: 0, to: Int(entry.count), by: 1).compactMap { index in
      let position = entry.valuePosition + (index * 8)
      guard
        let numerator = readUInt32(from: data, at: position, byteOrder: byteOrder),
        let denominator = readUInt32(from: data, at: position + 4, byteOrder: byteOrder),
        denominator != 0
      else { return nil }
      if entry.type == 10 {
        let signedNumerator = Int32(bitPattern: numerator)
        let signedDenominator = Int32(bitPattern: denominator)
        guard signedDenominator != 0 else { return nil }
        return Double(signedNumerator) / Double(signedDenominator)
      }
      return Double(numerator) / Double(denominator)
    }
  }

  private func bytes(for entry: Entry, in data: Data) -> [UInt8] {
    Array(data[entry.valuePosition..<(entry.valuePosition + entry.valueSize)])
  }

  private func checkedByteCount(count: UInt32, typeSize: Int) -> Int? {
    let count = UInt64(count)
    let size = UInt64(typeSize)
    let result = count.multipliedReportingOverflow(by: size)
    guard !result.overflow, result.partialValue <= UInt64(Int.max) else { return nil }
    return Int(result.partialValue)
  }

  private static func typeSize(_ type: UInt16) -> Int? {
    switch type {
    case 1, 2, 6, 7: 1
    case 3, 8: 2
    case 4, 9, 11: 4
    case 5, 10, 12: 8
    default: nil
    }
  }

  private func readUInt16(
    from data: Data,
    at offset: Int,
    byteOrder: DNGByteOrder
  ) -> UInt16? {
    guard offset >= 0, offset <= data.count - 2 else { return nil }
    let first = UInt16(data[offset])
    let second = UInt16(data[offset + 1])
    switch byteOrder {
    case .littleEndian: return first | (second << 8)
    case .bigEndian: return (first << 8) | second
    }
  }

  private func readUInt32(
    from data: Data,
    at offset: Int,
    byteOrder: DNGByteOrder
  ) -> UInt32? {
    guard offset >= 0, offset <= data.count - 4 else { return nil }
    let bytes = (0..<4).map { UInt32(data[offset + $0]) }
    switch byteOrder {
    case .littleEndian:
      return bytes[0] | (bytes[1] << 8) | (bytes[2] << 16) | (bytes[3] << 24)
    case .bigEndian:
      return (bytes[0] << 24) | (bytes[1] << 16) | (bytes[2] << 8) | bytes[3]
    }
  }

  private func inspection(
    state: DNGContainerState,
    version: DNGVersion? = nil,
    backwardVersion: DNGVersion? = nil,
    byteOrder: DNGByteOrder?,
    isBigTIFF: Bool,
    metadata: DNGContainerMetadata? = nil,
    issue: DNGContainerIssue? = nil,
    sourceByteCount: UInt64
  ) -> DNGContainerInspection {
    DNGContainerInspection(
      state: state,
      dngVersion: version,
      backwardVersion: backwardVersion,
      byteOrder: byteOrder,
      isBigTIFF: isBigTIFF,
      metadata: metadata,
      issue: issue,
      sourceByteCount: sourceByteCount
    )
  }
}
