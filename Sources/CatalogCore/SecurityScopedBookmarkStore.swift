// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation

public struct ResolvedSecurityScopedBookmark: Sendable {
  public let url: URL
  public let isStale: Bool
  public let renewedData: Data?

  public init(url: URL, isStale: Bool, renewedData: Data?) {
    self.url = url
    self.isStale = isStale
    self.renewedData = renewedData
  }
}

public enum SecurityScopedBookmarkStore {
  public static func create(url: URL) throws -> Data {
    do {
      return try url.bookmarkData(
        options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess],
        includingResourceValuesForKeys: nil,
        relativeTo: nil
      )
    } catch {
      throw CatalogStoreError.bookmark(
        operation: "bookmark.create", message: error.localizedDescription)
    }
  }

  public static func resolve(data: Data) throws -> ResolvedSecurityScopedBookmark {
    do {
      var isStale = false
      let url = try URL(
        resolvingBookmarkData: data,
        options: [.withSecurityScope],
        relativeTo: nil,
        bookmarkDataIsStale: &isStale
      )
      let renewedData = isStale ? try renew(url: url) : nil
      return ResolvedSecurityScopedBookmark(url: url, isStale: isStale, renewedData: renewedData)
    } catch let error as CatalogStoreError {
      throw error
    } catch {
      throw CatalogStoreError.bookmark(
        operation: "bookmark.resolve", message: error.localizedDescription)
    }
  }

  public static func withAccess<Result>(
    to url: URL,
    operation: () throws -> Result
  ) throws -> Result {
    let started = url.startAccessingSecurityScopedResource()
    defer {
      if started {
        url.stopAccessingSecurityScopedResource()
      }
    }
    return try operation()
  }

  static func renewForTesting(
    url: URL,
    access: () -> Bool,
    stopAccess: () -> Void,
    create: (URL) throws -> Data
  ) throws -> Data {
    try renew(url: url, access: access, stopAccess: stopAccess, create: create)
  }

  private static func renew(url: URL) throws -> Data {
    try renew(
      url: url,
      access: { url.startAccessingSecurityScopedResource() },
      stopAccess: { url.stopAccessingSecurityScopedResource() },
      create: create
    )
  }

  private static func renew(
    url: URL,
    access: () -> Bool,
    stopAccess: () -> Void,
    create: (URL) throws -> Data
  ) throws -> Data {
    let started = access()
    defer {
      if started {
        stopAccess()
      }
    }
    return try create(url)
  }
}
