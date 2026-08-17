// SPDX-License-Identifier: MPL-2.0

import Foundation

public struct SourceFingerprint: Codable, Hashable, Sendable {
  public let sha256: String
  public let byteCount: UInt64
  public let modificationDate: Date?

  public init?(sha256: String, byteCount: UInt64, modificationDate: Date?) {
    guard Self.isCanonicalSHA256(sha256) else {
      return nil
    }

    self.sha256 = sha256
    self.byteCount = byteCount
    self.modificationDate = modificationDate
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let sha256 = try container.decode(String.self, forKey: .sha256)
    let byteCount = try container.decode(UInt64.self, forKey: .byteCount)
    let modificationDate = try container.decodeIfPresent(Date.self, forKey: .modificationDate)

    guard
      let fingerprint = Self(
        sha256: sha256,
        byteCount: byteCount,
        modificationDate: modificationDate
      )
    else {
      throw DecodingError.dataCorruptedError(
        forKey: .sha256,
        in: container,
        debugDescription: "SHA-256 must contain exactly 64 lower-case hexadecimal characters."
      )
    }

    self = fingerprint
  }

  private static func isCanonicalSHA256(_ value: String) -> Bool {
    value.utf8.count == 64
      && value.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
  }
}
