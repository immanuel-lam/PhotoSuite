// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import CryptoKit
import Foundation
import PhotoDomain

public enum SourceFingerprinter {
  public static func fingerprint(url: URL, chunkSize: Int = 1_048_576) throws -> SourceFingerprint {
    guard url.isFileURL else {
      throw CatalogStoreError.invalidRequest(
        operation: "fingerprint",
        message: "The source URL must be a file URL."
      )
    }
    guard chunkSize > 0 else {
      throw CatalogStoreError.invalidRequest(
        operation: "fingerprint",
        message: "The chunk size must be greater than zero."
      )
    }

    do {
      let fileHandle = try FileHandle(forReadingFrom: url)
      defer { try? fileHandle.close() }
      var digest = SHA256()
      var byteCount: UInt64 = 0

      while let data = try fileHandle.read(upToCount: chunkSize), !data.isEmpty {
        let (nextCount, overflow) = byteCount.addingReportingOverflow(UInt64(data.count))
        guard !overflow else {
          throw CatalogStoreError.source(
            operation: "fingerprint",
            message: "The source byte count overflowed UInt64."
          )
        }
        byteCount = nextCount
        digest.update(data: data)
      }

      let hash = digest.finalize().map { String(format: "%02x", $0) }.joined()
      let modificationDate = try url.resourceValues(forKeys: [.contentModificationDateKey])
        .contentModificationDate
      guard
        let fingerprint = SourceFingerprint(
          sha256: hash,
          byteCount: byteCount,
          modificationDate: modificationDate
        )
      else {
        throw CatalogStoreError.source(
          operation: "fingerprint",
          message: "The generated SHA-256 value was invalid."
        )
      }
      return fingerprint
    } catch let error as CatalogStoreError {
      throw error
    } catch {
      throw CatalogStoreError.source(operation: "fingerprint", message: error.localizedDescription)
    }
  }

  public static func verify(url: URL, expected: SourceFingerprint) throws -> Bool {
    let actual = try fingerprint(url: url)
    return actual.sha256 == expected.sha256 && actual.byteCount == expected.byteCount
  }
}
