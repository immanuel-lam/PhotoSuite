// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation

public enum CatalogStoreError: Error, LocalizedError, Sendable {
  case sqlite(operation: String, code: Int32, extendedCode: Int32, message: String)
  case notFound(operation: String, message: String)
  case invalidRequest(operation: String, message: String)
  case encoding(operation: String, message: String)
  case decoding(operation: String, message: String)
  case source(operation: String, message: String)
  case bookmark(operation: String, message: String)
  case unsupported(operation: String, message: String)

  public var errorDescription: String? {
    switch self {
    case .sqlite(let operation, let code, let extendedCode, let message):
      "\(operation) failed with SQLite code \(code), extended code \(extendedCode): \(message)"
    case .notFound(let operation, let message), .invalidRequest(let operation, let message),
      .encoding(let operation, let message), .decoding(let operation, let message),
      .source(let operation, let message), .bookmark(let operation, let message),
      .unsupported(let operation, let message):
      "\(operation): \(message)"
    }
  }
}
