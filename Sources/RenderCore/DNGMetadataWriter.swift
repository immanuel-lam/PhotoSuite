// SPDX-License-Identifier: MPL-2.0

import Foundation
import PhotoDomain

/// A conservative DNG metadata writer.
///
/// The writer copies a valid classic DNG and patches existing fixed-size
/// ASCII fields in the first IFD in place. It never changes IFD offsets,
/// strip/tile locations, source bytes, or raw pixel payloads. A complete
/// Bayer/X-Trans encoder is a separate implementation and is intentionally
/// not claimed here.
public struct DNGMetadataWriter: DNGContainerWriter, Sendable {
  private static let maximumIFDEntries: UInt16 = 4_096
  private static let maximumPatchBytes: UInt32 = 4_096

  public let contract: DNGWriterContract = .metadataOnly

  public init() {}

  public func write(_ request: DNGWriteRequest) throws -> DNGWriteResult {
    try Task.checkCancellation()
    guard request.sourceURL.isFileURL, request.destinationURL.isFileURL else {
      throw DNGWriterError.invalidDestination(request.destinationURL)
    }

    let resolvedSource = request.sourceURL.standardizedFileURL.resolvingSymlinksInPath()
    let resolvedDestination = request.destinationURL.standardizedFileURL.resolvingSymlinksInPath()
    guard resolvedSource != resolvedDestination else {
      throw DNGWriterError.sourceDestinationConflict(request.sourceURL)
    }

    let destinationDirectory = request.destinationURL.deletingLastPathComponent()
    var isDirectory: ObjCBool = false
    guard
      FileManager.default.fileExists(
        atPath: destinationDirectory.path,
        isDirectory: &isDirectory
      ),
      isDirectory.boolValue
    else {
      throw DNGWriterError.invalidDestination(request.destinationURL)
    }

    let reader = DNGMetadataReader()
    let sourceInspection = try reader.inspect(DNGInspectionRequest(sourceURL: request.sourceURL))
    guard sourceInspection.state == .valid,
      let byteOrder = sourceInspection.byteOrder,
      !sourceInspection.isBigTIFF
    else {
      throw DNGWriterError.unsupportedContainer(sourceInspection.state)
    }
    guard let sourceData = try? Data(contentsOf: request.sourceURL, options: [.mappedIfSafe]) else {
      throw DNGReaderError.sourceUnavailable(request.sourceURL)
    }
    let dataInspection = try reader.inspect(data: sourceData)
    guard dataInspection.state == .valid,
      dataInspection.byteOrder == byteOrder,
      !dataInspection.isBigTIFF
    else {
      throw DNGWriterError.unsupportedContainer(dataInspection.state)
    }

    let entries = try parseEntries(in: sourceData, byteOrder: byteOrder)
    var patchedData = sourceData
    try patch(
      request.metadataPatch.make,
      tag: 271,
      entries: entries,
      data: &patchedData
    )
    try patch(
      request.metadataPatch.model,
      tag: 272,
      entries: entries,
      data: &patchedData
    )
    try patch(
      request.metadataPatch.uniqueCameraModel,
      tag: 50708,
      entries: entries,
      data: &patchedData
    )
    try patch(
      request.metadataPatch.software,
      tag: 305,
      entries: entries,
      data: &patchedData
    )
    try Task.checkCancellation()

    let patchedInspection = try reader.inspect(data: patchedData)
    guard patchedInspection.state == .valid else {
      throw DNGWriterError.atomicWriteFailed(request.destinationURL)
    }
    do {
      try patchedData.write(to: request.destinationURL, options: [.atomic])
    } catch {
      throw DNGWriterError.atomicWriteFailed(request.destinationURL)
    }
    try Task.checkCancellation()
    guard
      let publishedData = try? Data(contentsOf: request.destinationURL),
      publishedData == patchedData
    else {
      throw DNGWriterError.atomicWriteFailed(request.destinationURL)
    }

    return DNGWriteResult(
      destinationURL: request.destinationURL,
      contract: contract
    )
  }

  private struct Entry: Sendable {
    let tag: UInt16
    let type: UInt16
    let count: UInt32
    let valuePosition: Int
    let valueSize: Int
  }

  private func parseEntries(in data: Data, byteOrder: DNGByteOrder) throws -> [Entry] {
    guard data.count >= 8,
      let magic = readUInt16(from: data, at: 2, byteOrder: byteOrder),
      magic == 42,
      let firstIFDOffset = readUInt32(from: data, at: 4, byteOrder: byteOrder),
      firstIFDOffset != 0,
      firstIFDOffset <= UInt32(data.count - 2)
    else {
      throw DNGWriterError.unsupportedContainer(.malformed)
    }

    let offset = Int(firstIFDOffset)
    guard let entryCount = readUInt16(from: data, at: offset, byteOrder: byteOrder),
      entryCount <= Self.maximumIFDEntries
    else {
      throw DNGWriterError.unsupportedContainer(.malformed)
    }
    let tableSize = Int(entryCount) * 12 + 2 + 4
    guard tableSize <= data.count - offset else {
      throw DNGWriterError.unsupportedContainer(.malformed)
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
        throw DNGWriterError.metadataTagMalformed(0)
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
          ),
          valueOffset <= UInt32(data.count),
          valueSize <= data.count - Int(valueOffset)
        else {
          throw DNGWriterError.metadataTagMalformed(tag)
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
    return entries
  }

  private func patch(
    _ value: String?,
    tag: UInt16,
    entries: [Entry],
    data: inout Data
  ) throws {
    guard let value else { return }
    guard let entry = entries.last(where: { $0.tag == tag }) else {
      throw DNGWriterError.metadataTagUnavailable(tag)
    }
    guard entry.type == 2,
      entry.count <= Self.maximumPatchBytes,
      entry.valueSize == Int(entry.count),
      entry.valuePosition >= 0,
      entry.valuePosition <= data.count,
      entry.valueSize <= data.count - entry.valuePosition
    else {
      throw DNGWriterError.metadataTagMalformed(tag)
    }
    guard !value.unicodeScalars.contains(where: { $0.value == 0 }) else {
      throw DNGWriterError.metadataValueContainsNUL(tag)
    }
    let encoded = Array(value.utf8)
    guard encoded.allSatisfy({ $0 < 0x80 }) else {
      throw DNGWriterError.metadataValueNotASCII(tag)
    }
    guard encoded.count < Int(entry.count) else {
      throw DNGWriterError.metadataValueTooLong(tag: tag, maximumBytes: entry.count)
    }
    var replacement = encoded
    replacement.append(0)
    replacement.append(contentsOf: repeatElement(0, count: Int(entry.count) - replacement.count))
    data.replaceSubrange(
      entry.valuePosition..<(entry.valuePosition + entry.valueSize),
      with: replacement
    )
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

  private func checkedByteCount(count: UInt32, typeSize: Int) -> Int? {
    let result = UInt64(count).multipliedReportingOverflow(by: UInt64(typeSize))
    guard !result.overflow, result.partialValue <= UInt64(Int.max) else { return nil }
    return Int(result.partialValue)
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
}
