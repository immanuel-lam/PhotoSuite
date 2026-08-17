// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import PhotoDomain
import SQLite3

private final class SQLiteConnection: @unchecked Sendable {
  let database: OpaquePointer
  private var isClosed = false

  init(database: OpaquePointer) {
    self.database = database
  }

  deinit {
    _ = close()
  }

  func close() -> Int32 {
    guard !isClosed else { return SQLITE_OK }
    let code = sqlite3_close_v2(database)
    if code == SQLITE_OK {
      isClosed = true
    }
    return code
  }
}

struct SQLiteCatalogBackupFaults: Sendable {
  let stepCode: Int32?
  let finishCode: Int32?
  let closeCode: Int32?
  let filesystemCleanupMessage: String?

  init(
    stepCode: Int32? = nil,
    finishCode: Int32? = nil,
    closeCode: Int32? = nil,
    filesystemCleanupMessage: String? = nil
  ) {
    self.stepCode = stepCode
    self.finishCode = finishCode
    self.closeCode = closeCode
    self.filesystemCleanupMessage = filesystemCleanupMessage
  }

  static let none = SQLiteCatalogBackupFaults()
}

private struct SQLiteSchemaColumn: Equatable {
  let position: Int32
  let name: String
  let type: String
  let isNotNull: Bool
  let defaultValue: String?
  let primaryKeyPosition: Int32
}

private struct SQLiteIndexColumn: Equatable {
  let sequence: Int32
  let tableColumn: Int32
  let name: String?
  let isDescending: Bool
  let collation: String?
  let isKey: Bool
}

public actor SQLiteCatalogStore: CatalogStore, JobEngine {
  private static let schemaVersion: Int64 = 1
  private let connection: SQLiteConnection
  private let ftsAvailable: Bool
  private let encoder: JSONEncoder
  private let decoder: JSONDecoder
  private let catalogURL: URL
  private let backupFaults: SQLiteCatalogBackupFaults
  private var isUsable = true

  private var database: OpaquePointer { connection.database }

  public init(catalogURL: URL) throws {
    try self.init(
      catalogURL: catalogURL, ftsAvailabilityOverride: nil, backupFaults: .none)
  }

  init(
    catalogURL: URL,
    ftsAvailabilityOverride: Bool?,
    backupFaults: SQLiteCatalogBackupFaults = .none
  ) throws {
    guard catalogURL.isFileURL else {
      throw CatalogStoreError.invalidRequest(
        operation: "catalog.open",
        message: "The catalog URL must be a file URL."
      )
    }

    self.catalogURL = catalogURL.standardizedFileURL
    self.backupFaults = backupFaults
    let database = try Self.openDatabase(at: catalogURL)
    do {
      let version = try Self.readSchemaVersion(database)
      guard version <= Self.schemaVersion else {
        throw CatalogStoreError.unsupported(
          operation: "catalog.open",
          message:
            "Catalog schema version \(version) is newer than supported version \(Self.schemaVersion)."
        )
      }
      try Self.configure(database)
      let ftsAvailable = try Self.migrate(
        database, version: version, ftsAvailabilityOverride: ftsAvailabilityOverride)
      self.connection = SQLiteConnection(database: database)
      self.ftsAvailable = ftsAvailable
      self.encoder = Self.makeEncoder()
      self.decoder = Self.makeDecoder()
    } catch let primaryError {
      let closeCode = sqlite3_close_v2(database)
      guard closeCode == SQLITE_OK else {
        throw CatalogStoreError.cleanup(
          operation: "catalog.open.close",
          primaryError: String(describing: primaryError),
          cleanupError: Self.sqliteError(
            operation: "catalog.open.close", database: database, code: closeCode
          ).localizedDescription
        )
      }
      throw primaryError
    }
  }

  public func upsertAsset(
    _ request: CatalogAssetUpsertRequest
  ) async throws -> CatalogAssetUpsertResult {
    try storeAsset(request.asset)
    return CatalogAssetUpsertResult(asset: request.asset)
  }

  public func close() throws {
    guard isUsable else { return }
    let code = connection.close()
    guard code == SQLITE_OK else {
      isUsable = false
      throw sqliteError(operation: "catalog.close", code: code)
    }
    isUsable = false
  }

  private func storeAsset(_ asset: PhotoAsset) throws {
    try withTransaction(operation: "asset.upsert") {
      try storeAssetInTransaction(asset)
    }
  }

  private func storeAssetInTransaction(_ asset: PhotoAsset) throws {
    try withStatement(
      """
      INSERT INTO assets (
        id, source_url, filename, type_identifier, fingerprint_json, import_ms,
        capture_ms, dimensions_json, rating, color_label, is_missing
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT(id) DO UPDATE SET
        source_url=excluded.source_url,
        filename=excluded.filename,
        type_identifier=excluded.type_identifier,
        fingerprint_json=excluded.fingerprint_json,
        import_ms=excluded.import_ms,
        capture_ms=excluded.capture_ms,
        dimensions_json=excluded.dimensions_json,
        rating=excluded.rating,
        color_label=excluded.color_label,
        is_missing=excluded.is_missing;
      """,
      operation: "asset.upsert"
    ) { statement in
      try bind(assetID: asset.id, to: statement, index: 1, operation: "asset.upsert")
      try bind(
        asset.sourceURL.absoluteString, to: statement, index: 2, operation: "asset.upsert"
      )
      try bind(asset.filename, to: statement, index: 3, operation: "asset.upsert")
      try bind(asset.typeIdentifier, to: statement, index: 4, operation: "asset.upsert")
      try bind(
        try encode(asset.fingerprint, operation: "asset.upsert.fingerprint"),
        to: statement, index: 5, operation: "asset.upsert")
      try bind(
        milliseconds(asset.importDate), to: statement, index: 6, operation: "asset.upsert"
      )
      try bind(
        asset.captureDate.map(milliseconds), to: statement, index: 7,
        operation: "asset.upsert")
      try bind(
        try asset.pixelDimensions.map {
          try encode($0, operation: "asset.upsert.dimensions")
        },
        to: statement,
        index: 8,
        operation: "asset.upsert"
      )
      try bind(Int64(asset.rating), to: statement, index: 9, operation: "asset.upsert")
      try bind(
        try asset.colorLabel.map { try encode($0, operation: "asset.upsert.colorLabel") },
        to: statement,
        index: 10,
        operation: "asset.upsert"
      )
      try bind(
        asset.isMissing ? Int64(1) : Int64(0), to: statement, index: 11,
        operation: "asset.upsert")
      try stepDone(statement, operation: "asset.upsert")
    }
    try updateSearchIndex(for: asset)
  }

  public func fetchAsset(
    _ request: CatalogAssetFetchRequest
  ) async throws -> CatalogAssetFetchResult {
    CatalogAssetFetchResult(asset: try asset(id: request.assetID, operation: "asset.fetch"))
  }

  public func listAssets(
    _ request: CatalogAssetListRequest
  ) async throws -> CatalogAssetListResult {
    guard request.offset >= 0 else {
      throw CatalogStoreError.invalidRequest(
        operation: "asset.list",
        message: "The offset must not be negative."
      )
    }
    if let limit = request.limit, limit <= 0 {
      throw CatalogStoreError.invalidRequest(
        operation: "asset.list",
        message: "The limit must be greater than zero."
      )
    }

    let order =
      switch request.order {
      case .importDateAscending: "import_ms ASC, id ASC"
      case .importDateDescending: "import_ms DESC, id ASC"
      case .captureDateAscending: "capture_ms ASC, id ASC"
      case .captureDateDescending: "capture_ms DESC, id ASC"
      case .filenameAscending: "filename COLLATE NOCASE ASC, id ASC"
      case .filenameDescending: "filename COLLATE NOCASE DESC, id ASC"
      }
    let limit = request.limit.map(Int64.init) ?? Int64.max
    return CatalogAssetListResult(
      assets: try assets(
        sql:
          "SELECT id, source_url, filename, type_identifier, fingerprint_json, import_ms, capture_ms, dimensions_json, rating, color_label, is_missing FROM assets ORDER BY \(order) LIMIT ? OFFSET ?;",
        operation: "asset.list",
        bindValues: { statement in
          try bind(limit, to: statement, index: 1, operation: "asset.list")
          try bind(Int64(request.offset), to: statement, index: 2, operation: "asset.list")
        }
      )
    )
  }

  public func searchAssets(
    _ request: CatalogAssetSearchRequest
  ) async throws -> CatalogAssetSearchResult {
    let query = request.query.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !query.isEmpty else {
      return CatalogAssetSearchResult(assets: [])
    }
    if let limit = request.limit, limit <= 0 {
      throw CatalogStoreError.invalidRequest(
        operation: "asset.search",
        message: "The limit must be greater than zero."
      )
    }
    let limit = request.limit.map(Int64.init) ?? Int64.max

    let pattern = "%\(escapeLike(query))%"
    if ftsAvailable, query.allSatisfy({ $0.isLetter || $0.isNumber }) {
      return CatalogAssetSearchResult(
        assets: try assets(
          sql: """
            SELECT assets.id, assets.source_url, assets.filename, assets.type_identifier,
              assets.fingerprint_json, assets.import_ms, assets.capture_ms,
              assets.dimensions_json, assets.rating, assets.color_label, assets.is_missing
            FROM assets
            WHERE assets.id IN (
                SELECT asset_id FROM asset_search WHERE asset_search MATCH ?
              )
              OR assets.filename LIKE ? ESCAPE '\\'
              OR COALESCE(assets.type_identifier, '') LIKE ? ESCAPE '\\'
              OR assets.source_url LIKE ? ESCAPE '\\'
            ORDER BY assets.import_ms DESC, assets.id ASC
            LIMIT ?;
            """,
          operation: "asset.search.fts",
          bindValues: { statement in
            try bind(query, to: statement, index: 1, operation: "asset.search.fts")
            try bind(pattern, to: statement, index: 2, operation: "asset.search.fts")
            try bind(pattern, to: statement, index: 3, operation: "asset.search.fts")
            try bind(pattern, to: statement, index: 4, operation: "asset.search.fts")
            try bind(limit, to: statement, index: 5, operation: "asset.search.fts")
          }
        )
      )
    }

    return CatalogAssetSearchResult(
      assets: try assets(
        sql: """
          SELECT id, source_url, filename, type_identifier, fingerprint_json, import_ms,
            capture_ms, dimensions_json, rating, color_label, is_missing FROM assets
          WHERE filename LIKE ? ESCAPE '\\'
            OR COALESCE(type_identifier, '') LIKE ? ESCAPE '\\'
            OR source_url LIKE ? ESCAPE '\\'
          ORDER BY import_ms DESC, id ASC
          LIMIT ?;
          """,
        operation: "asset.search.like",
        bindValues: { statement in
          try bind(pattern, to: statement, index: 1, operation: "asset.search.like")
          try bind(pattern, to: statement, index: 2, operation: "asset.search.like")
          try bind(pattern, to: statement, index: 3, operation: "asset.search.like")
          try bind(limit, to: statement, index: 4, operation: "asset.search.like")
        }
      )
    )
  }

  public func saveRecipe(
    _ request: CatalogRecipeSaveRequest
  ) async throws -> CatalogRecipeSaveResult {
    guard try assetExists(request.recipe.assetID, operation: "recipe.save") else {
      throw CatalogStoreError.notFound(
        operation: "recipe.save", message: "The asset does not exist.")
    }
    let data = try encode(request.recipe, operation: "recipe.save.encode")
    try withStatement(
      """
      INSERT INTO edit_recipes (asset_id, revision, date_ms, recipe_json)
      VALUES (?, ?, ?, ?)
      ON CONFLICT(asset_id, revision) DO UPDATE SET
        date_ms=excluded.date_ms,
        recipe_json=excluded.recipe_json;
      """,
      operation: "recipe.save"
    ) { statement in
      try bind(assetID: request.recipe.assetID, to: statement, index: 1, operation: "recipe.save")
      try bind(
        Int64(exactly: request.recipe.revision), to: statement, index: 2, operation: "recipe.save")
      try bind(milliseconds(request.recipe.date), to: statement, index: 3, operation: "recipe.save")
      try bind(data, to: statement, index: 4, operation: "recipe.save")
      try stepDone(statement, operation: "recipe.save")
    }
    return CatalogRecipeSaveResult(recipe: request.recipe)
  }

  public func latestRecipe(
    _ request: CatalogLatestRecipeRequest
  ) async throws -> CatalogLatestRecipeResult {
    let recipe: EditRecipe? = try withStatement(
      """
      SELECT recipe_json FROM edit_recipes
      WHERE asset_id = ?
      ORDER BY revision DESC, date_ms DESC
      LIMIT 1;
      """,
      operation: "recipe.latest"
    ) { statement in
      try bind(assetID: request.assetID, to: statement, index: 1, operation: "recipe.latest")
      let code = sqlite3_step(statement)
      if code == SQLITE_DONE {
        return nil
      }
      guard code == SQLITE_ROW else {
        throw sqliteError(operation: "recipe.latest", code: code)
      }
      return try decode(
        EditRecipe.self, from: columnData(statement, column: 0, operation: "recipe.latest"),
        operation: "recipe.latest")
    }
    return CatalogLatestRecipeResult(recipe: recipe)
  }

  public func markAssetMissing(
    _ request: CatalogMarkMissingRequest
  ) async throws -> CatalogMarkMissingResult {
    guard let existing = try asset(id: request.assetID, operation: "asset.markMissing") else {
      throw CatalogStoreError.notFound(
        operation: "asset.markMissing", message: "The asset does not exist.")
    }
    guard
      let updated = PhotoAsset(
        id: existing.id,
        sourceURL: existing.sourceURL,
        filename: existing.filename,
        typeIdentifier: existing.typeIdentifier,
        fingerprint: existing.fingerprint,
        importDate: existing.importDate,
        captureDate: existing.captureDate,
        pixelDimensions: existing.pixelDimensions,
        rating: existing.rating,
        colorLabel: existing.colorLabel,
        isMissing: request.isMissing
      )
    else {
      throw CatalogStoreError.decoding(
        operation: "asset.markMissing", message: "Stored asset is invalid.")
    }
    try storeAsset(updated)
    return CatalogMarkMissingResult(asset: updated)
  }

  public func relinkAsset(
    _ request: CatalogRelinkAssetRequest
  ) async throws -> CatalogRelinkAssetResult {
    try relinkAsset(request, bookmarkCreator: SecurityScopedBookmarkStore.create)
  }

  func relinkAssetForTesting(
    _ request: CatalogRelinkAssetRequest,
    bookmarkCreator: (URL) throws -> Data
  ) throws -> CatalogRelinkAssetResult {
    try relinkAsset(request, bookmarkCreator: bookmarkCreator)
  }

  private func relinkAsset(
    _ request: CatalogRelinkAssetRequest,
    bookmarkCreator: (URL) throws -> Data
  ) throws -> CatalogRelinkAssetResult {
    guard let existing = try asset(id: request.assetID, operation: "asset.relink") else {
      throw CatalogStoreError.notFound(
        operation: "asset.relink", message: "The asset does not exist.")
    }
    guard
      let relinked = PhotoAsset(
        id: existing.id,
        sourceURL: request.sourceURL,
        filename: request.filename,
        typeIdentifier: request.typeIdentifier,
        fingerprint: request.fingerprint,
        importDate: existing.importDate,
        captureDate: existing.captureDate,
        pixelDimensions: existing.pixelDimensions,
        rating: existing.rating,
        colorLabel: existing.colorLabel,
        isMissing: false
      )
    else {
      throw CatalogStoreError.invalidRequest(
        operation: "asset.relink", message: "The relinked asset is invalid.")
    }
    // Create access before durable mutation. A scope failure is recoverable, but an old
    // bookmark must never survive a successful relink.
    let replacementBookmark = try? bookmarkCreator(relinked.sourceURL)
    try withTransaction(operation: "asset.relink") {
      try storeAssetInTransaction(relinked)
      if let replacementBookmark {
        try storeBookmarkInTransaction(replacementBookmark, forAssetID: relinked.id)
      } else {
        try deleteBookmarkInTransaction(forAssetID: relinked.id)
      }
    }
    return CatalogRelinkAssetResult(asset: relinked)
  }

  public func createBookmark(forAssetID assetID: UUID) throws -> Data {
    guard let storedAsset = try asset(id: assetID, operation: "bookmark.create") else {
      throw CatalogStoreError.notFound(
        operation: "bookmark.create", message: "The asset does not exist.")
    }
    let data = try SecurityScopedBookmarkStore.create(url: storedAsset.sourceURL)
    try storeBookmark(data, forAssetID: assetID)
    return data
  }

  public func bookmarkData(forAssetID assetID: UUID) throws -> Data? {
    try withStatement(
      "SELECT bookmark FROM asset_bookmarks WHERE asset_id = ?;", operation: "bookmark.read"
    ) { statement in
      try bind(assetID: assetID, to: statement, index: 1, operation: "bookmark.read")
      let code = sqlite3_step(statement)
      if code == SQLITE_DONE { return nil }
      guard code == SQLITE_ROW else { throw sqliteError(operation: "bookmark.read", code: code) }
      return try columnData(statement, column: 0, operation: "bookmark.read")
    }
  }

  public func resolveBookmark(forAssetID assetID: UUID) throws -> ResolvedSecurityScopedBookmark {
    try resolveBookmark(forAssetID: assetID, using: SecurityScopedBookmarkStore.resolve)
  }

  func resolveBookmarkForTesting(
    forAssetID assetID: UUID,
    _ resolver: (Data) throws -> ResolvedSecurityScopedBookmark
  ) throws -> ResolvedSecurityScopedBookmark {
    try resolveBookmark(forAssetID: assetID, using: resolver)
  }

  private func resolveBookmark(
    forAssetID assetID: UUID,
    using resolver: (Data) throws -> ResolvedSecurityScopedBookmark
  ) throws -> ResolvedSecurityScopedBookmark {
    guard let data = try bookmarkData(forAssetID: assetID) else {
      throw CatalogStoreError.notFound(
        operation: "bookmark.resolve", message: "The asset has no stored bookmark.")
    }
    let resolved = try resolver(data)
    if let renewedData = resolved.renewedData {
      try storeBookmark(renewedData, forAssetID: assetID)
    }
    return resolved
  }

  public func checkIntegrity(
    _ request: CatalogIntegrityRequest
  ) async throws -> CatalogIntegrityResult {
    _ = request
    let messages: [String] = try withStatement(
      "PRAGMA integrity_check;", operation: "catalog.integrity"
    ) { statement in
      var messages: [String] = []
      while true {
        let code = sqlite3_step(statement)
        if code == SQLITE_DONE { break }
        guard code == SQLITE_ROW else {
          throw sqliteError(operation: "catalog.integrity", code: code)
        }
        messages.append(try columnString(statement, column: 0, operation: "catalog.integrity"))
      }
      return messages
    }
    return CatalogIntegrityResult(
      isValid: messages.allSatisfy { $0.lowercased() == "ok" }, messages: messages)
  }

  public func backup(_ request: CatalogBackupRequest) async throws -> CatalogBackupResult {
    try ensureUsable(operation: "catalog.backup")
    guard request.destinationURL.isFileURL else {
      throw CatalogStoreError.invalidRequest(
        operation: "catalog.backup", message: "The destination must be a file URL.")
    }
    guard request.destinationURL.standardizedFileURL != catalogURL else {
      throw CatalogStoreError.invalidRequest(
        operation: "catalog.backup", message: "The destination must not be the open catalog file.")
    }
    guard !FileManager.default.fileExists(atPath: request.destinationURL.path) else {
      throw CatalogStoreError.invalidRequest(
        operation: "catalog.backup", message: "The destination already exists.")
    }
    var destination: OpaquePointer?
    let openCode = sqlite3_open_v2(
      request.destinationURL.path,
      &destination,
      SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX,
      nil
    )
    guard openCode == SQLITE_OK, let destination else {
      let primaryError = Self.sqliteError(
        operation: "catalog.backup.open", database: destination, code: openCode)
      if let destination {
        let closeCode = sqlite3_close_v2(destination)
        guard closeCode == SQLITE_OK else {
          throw CatalogStoreError.cleanup(
            operation: "catalog.backup.open.close",
            primaryError: primaryError.localizedDescription,
            cleanupError: Self.sqliteError(
              operation: "catalog.backup.open.close", database: destination, code: closeCode
            ).localizedDescription
          )
        }
      }
      throw primaryError
    }
    var failures: [CatalogStoreError] = []
    if let backup = sqlite3_backup_init(destination, "main", database, "main") {
      let start = Date()
      var actualStepCode: Int32 = SQLITE_OK
      repeat {
        actualStepCode = sqlite3_backup_step(backup, -1)
        if actualStepCode == SQLITE_BUSY || actualStepCode == SQLITE_LOCKED {
          _ = sqlite3_sleep(50)
        }
      } while (actualStepCode == SQLITE_BUSY || actualStepCode == SQLITE_LOCKED)
        && Date().timeIntervalSince(start) < 5
      let stepCode = backupFaults.stepCode ?? actualStepCode
      if stepCode != SQLITE_DONE {
        failures.append(
          backupError(
            operation: "catalog.backup.step", database: destination, code: stepCode,
            isInjected: backupFaults.stepCode != nil))
      }
      let actualFinishCode = sqlite3_backup_finish(backup)
      let finishCode = backupFaults.finishCode ?? actualFinishCode
      if finishCode != SQLITE_OK {
        failures.append(
          backupError(
            operation: "catalog.backup.finish", database: destination, code: finishCode,
            isInjected: backupFaults.finishCode != nil))
      }
    } else {
      failures.append(
        Self.sqliteError(
          operation: "catalog.backup.init", database: destination,
          code: sqlite3_errcode(destination)))
    }

    let actualCloseCode = sqlite3_close_v2(destination)
    let closeCode = backupFaults.closeCode ?? actualCloseCode
    if closeCode != SQLITE_OK {
      failures.append(
        backupError(
          operation: "catalog.backup.close",
          database: actualCloseCode == SQLITE_OK ? nil : destination,
          code: closeCode,
          isInjected: backupFaults.closeCode != nil))
    }

    guard let primaryError = failures.first else {
      return CatalogBackupResult(destinationURL: request.destinationURL)
    }
    var cleanupErrors = failures.dropFirst().map(\.localizedDescription)
    cleanupErrors.append(
      contentsOf: backupCleanupErrors(
        for: request.destinationURL,
        forcedMessage: backupFaults.filesystemCleanupMessage))
    guard cleanupErrors.isEmpty else {
      throw CatalogStoreError.cleanup(
        operation: "catalog.backup",
        primaryError: primaryError.localizedDescription,
        cleanupError: cleanupErrors.joined(separator: " | ")
      )
    }
    throw primaryError
  }

  public func enqueue(_ request: JobEnqueueRequest) async throws -> JobEnqueueResult {
    try withStatement(
      "INSERT INTO catalog_jobs (id, created_ms, updated_ms, job_json) VALUES (?, ?, ?, ?);",
      operation: "job.enqueue"
    ) { statement in
      try bind(jobID: request.job.id, to: statement, index: 1, operation: "job.enqueue")
      try bind(
        milliseconds(request.job.createdAt), to: statement, index: 2, operation: "job.enqueue")
      try bind(
        milliseconds(request.job.updatedAt), to: statement, index: 3, operation: "job.enqueue")
      try bind(
        try encode(request.job, operation: "job.enqueue.encode"), to: statement, index: 4,
        operation: "job.enqueue")
      try stepDone(statement, operation: "job.enqueue")
    }
    return JobEnqueueResult(job: request.job)
  }

  public func update(_ request: JobUpdateRequest) async throws -> JobUpdateResult {
    try withStatement(
      "UPDATE catalog_jobs SET created_ms = ?, updated_ms = ?, job_json = ? WHERE id = ?;",
      operation: "job.update"
    ) { statement in
      try bind(
        milliseconds(request.job.createdAt), to: statement, index: 1, operation: "job.update")
      try bind(
        milliseconds(request.job.updatedAt), to: statement, index: 2, operation: "job.update")
      try bind(
        try encode(request.job, operation: "job.update.encode"), to: statement, index: 3,
        operation: "job.update")
      try bind(jobID: request.job.id, to: statement, index: 4, operation: "job.update")
      try stepDone(statement, operation: "job.update")
    }
    guard sqlite3_changes(database) == 1 else {
      throw CatalogStoreError.notFound(operation: "job.update", message: "The job does not exist.")
    }
    return JobUpdateResult(job: request.job)
  }

  public func list(_ request: JobListRequest) async throws -> JobListResult {
    let jobs: [CatalogJob] = try withStatement(
      "SELECT job_json FROM catalog_jobs ORDER BY updated_ms DESC, id ASC;",
      operation: "job.list"
    ) { statement in
      var jobs: [CatalogJob] = []
      while true {
        let code = sqlite3_step(statement)
        if code == SQLITE_DONE { break }
        guard code == SQLITE_ROW else {
          throw sqliteError(operation: "job.list", code: code)
        }
        jobs.append(
          try decode(
            CatalogJob.self, from: columnData(statement, column: 0, operation: "job.list"),
            operation: "job.list"))
      }
      return jobs
    }
    let filtered = request.states.isEmpty ? jobs : jobs.filter { request.states.contains($0.state) }
    return JobListResult(jobs: filtered)
  }

  func configurationForTesting() throws -> (
    journalMode: String,
    synchronous: Int64,
    foreignKeys: Int64,
    busyTimeout: Int64
  ) {
    (
      try scalarString(sql: "PRAGMA journal_mode;", operation: "catalog.diagnostics.journalMode"),
      try scalarInt(sql: "PRAGMA synchronous;", operation: "catalog.diagnostics.synchronous"),
      try scalarInt(sql: "PRAGMA foreign_keys;", operation: "catalog.diagnostics.foreignKeys"),
      try scalarInt(sql: "PRAGMA busy_timeout;", operation: "catalog.diagnostics.busyTimeout")
    )
  }

  private func asset(id: UUID, operation: String) throws -> PhotoAsset? {
    try withStatement(
      "SELECT id, source_url, filename, type_identifier, fingerprint_json, import_ms, capture_ms, dimensions_json, rating, color_label, is_missing FROM assets WHERE id = ?;",
      operation: operation
    ) {
      statement in
      try bind(assetID: id, to: statement, index: 1, operation: operation)
      let code = sqlite3_step(statement)
      if code == SQLITE_DONE { return nil }
      guard code == SQLITE_ROW else { throw sqliteError(operation: operation, code: code) }
      return try decodeAsset(statement, operation: operation)
    }
  }

  private func scalarInt(sql: String, operation: String) throws -> Int64 {
    try withStatement(sql, operation: operation) { statement in
      let code = sqlite3_step(statement)
      guard code == SQLITE_ROW else { throw sqliteError(operation: operation, code: code) }
      return sqlite3_column_int64(statement, 0)
    }
  }

  private func scalarString(sql: String, operation: String) throws -> String {
    try withStatement(sql, operation: operation) { statement in
      let code = sqlite3_step(statement)
      guard code == SQLITE_ROW else { throw sqliteError(operation: operation, code: code) }
      return try columnString(statement, column: 0, operation: operation)
    }
  }

  private func assetExists(_ id: UUID, operation: String) throws -> Bool {
    try withStatement("SELECT 1 FROM assets WHERE id = ? LIMIT 1;", operation: operation) {
      statement in
      try bind(assetID: id, to: statement, index: 1, operation: operation)
      let code = sqlite3_step(statement)
      if code == SQLITE_DONE { return false }
      guard code == SQLITE_ROW else { throw sqliteError(operation: operation, code: code) }
      return true
    }
  }

  private func storeBookmark(_ data: Data, forAssetID assetID: UUID) throws {
    guard try assetExists(assetID, operation: "bookmark.write") else {
      throw CatalogStoreError.notFound(
        operation: "bookmark.write", message: "The asset does not exist.")
    }
    try storeBookmarkInTransaction(data, forAssetID: assetID)
  }

  private func storeBookmarkInTransaction(_ data: Data, forAssetID assetID: UUID) throws {
    try withStatement(
      """
      INSERT INTO asset_bookmarks (asset_id, bookmark, updated_ms) VALUES (?, ?, ?)
      ON CONFLICT(asset_id) DO UPDATE SET
        bookmark=excluded.bookmark,
        updated_ms=excluded.updated_ms;
      """,
      operation: "bookmark.write"
    ) { statement in
      try bind(assetID: assetID, to: statement, index: 1, operation: "bookmark.write")
      try bind(data, to: statement, index: 2, operation: "bookmark.write")
      try bind(milliseconds(Date()), to: statement, index: 3, operation: "bookmark.write")
      try stepDone(statement, operation: "bookmark.write")
    }
  }

  private func deleteBookmarkInTransaction(forAssetID assetID: UUID) throws {
    try withStatement(
      "DELETE FROM asset_bookmarks WHERE asset_id = ?;", operation: "bookmark.delete"
    ) { statement in
      try bind(assetID: assetID, to: statement, index: 1, operation: "bookmark.delete")
      try stepDone(statement, operation: "bookmark.delete")
    }
  }

  private func assets(
    sql: String,
    operation: String,
    bindValues: (OpaquePointer) throws -> Void
  ) throws -> [PhotoAsset] {
    try withStatement(sql, operation: operation) { statement in
      try bindValues(statement)
      var results: [PhotoAsset] = []
      while true {
        let code = sqlite3_step(statement)
        if code == SQLITE_DONE { break }
        guard code == SQLITE_ROW else { throw sqliteError(operation: operation, code: code) }
        results.append(try decodeAsset(statement, operation: operation))
      }
      return results
    }
  }

  private func updateSearchIndex(for asset: PhotoAsset) throws {
    guard ftsAvailable else { return }
    try withStatement(
      "DELETE FROM asset_search WHERE asset_id = ?;", operation: "asset.searchIndex.delete"
    ) { statement in
      try bind(assetID: asset.id, to: statement, index: 1, operation: "asset.searchIndex.delete")
      try stepDone(statement, operation: "asset.searchIndex.delete")
    }
    try withStatement(
      "INSERT INTO asset_search (asset_id, filename, type_identifier, source_url) VALUES (?, ?, ?, ?);",
      operation: "asset.searchIndex.insert"
    ) { statement in
      try bind(assetID: asset.id, to: statement, index: 1, operation: "asset.searchIndex.insert")
      try bind(asset.filename, to: statement, index: 2, operation: "asset.searchIndex.insert")
      try bind(asset.typeIdentifier, to: statement, index: 3, operation: "asset.searchIndex.insert")
      try bind(
        asset.sourceURL.absoluteString, to: statement, index: 4,
        operation: "asset.searchIndex.insert")
      try stepDone(statement, operation: "asset.searchIndex.insert")
    }
  }

  private func withTransaction<T>(operation: String, _ body: () throws -> T) throws -> T {
    try ensureUsable(operation: operation)
    try execute("BEGIN IMMEDIATE;", operation: "\(operation).begin")
    do {
      let result = try body()
      try execute("COMMIT;", operation: "\(operation).commit")
      return result
    } catch let primaryError {
      do {
        try execute("ROLLBACK;", operation: "\(operation).rollback")
      } catch let rollbackError {
        isUsable = false
        throw CatalogStoreError.cleanup(
          operation: operation,
          primaryError: String(describing: primaryError),
          cleanupError: String(describing: rollbackError)
        )
      }
      throw primaryError
    }
  }

  private func withStatement<T>(
    _ sql: String,
    operation: String,
    _ body: (OpaquePointer) throws -> T
  ) throws -> T {
    try ensureUsable(operation: operation)
    var statement: OpaquePointer?
    let prepareCode = sqlite3_prepare_v2(database, sql, -1, &statement, nil)
    guard prepareCode == SQLITE_OK, let statement else {
      throw sqliteError(operation: "\(operation).prepare", code: prepareCode)
    }
    let result: T
    do {
      result = try body(statement)
    } catch {
      let finalizeCode = sqlite3_finalize(statement)
      if finalizeCode != SQLITE_OK && !Self.isRepeatedStatementError(finalizeCode, primary: error) {
        throw CatalogStoreError.cleanup(
          operation: "\(operation).finalize",
          primaryError: String(describing: error),
          cleanupError: sqliteError(operation: "\(operation).finalize", code: finalizeCode)
            .localizedDescription
        )
      }
      throw error
    }
    let finalizeCode = sqlite3_finalize(statement)
    guard finalizeCode == SQLITE_OK else {
      throw sqliteError(operation: "\(operation).finalize", code: finalizeCode)
    }
    return result
  }

  private static func isRepeatedStatementError(_ code: Int32, primary: Error) -> Bool {
    guard case .sqlite(_, let primaryCode, _, _) = primary as? CatalogStoreError else {
      return false
    }
    return code == primaryCode
  }

  private func execute(_ sql: String, operation: String) throws {
    try ensureUsable(operation: operation)
    var errorMessage: UnsafeMutablePointer<CChar>?
    let code = sqlite3_exec(database, sql, nil, nil, &errorMessage)
    defer {
      if let errorMessage { sqlite3_free(errorMessage) }
    }
    guard code == SQLITE_OK else {
      let message =
        errorMessage.map { String(cString: $0) } ?? String(cString: sqlite3_errmsg(database))
      throw CatalogStoreError.sqlite(
        operation: operation,
        code: code,
        extendedCode: sqlite3_extended_errcode(database),
        message: message
      )
    }
  }

  private func stepDone(_ statement: OpaquePointer, operation: String) throws {
    let code = sqlite3_step(statement)
    guard code == SQLITE_DONE else {
      throw sqliteError(operation: "\(operation).step", code: code)
    }
  }

  private func bind(_ value: String?, to statement: OpaquePointer, index: Int32, operation: String)
    throws
  {
    let code: Int32
    if let value {
      code = sqlite3_bind_text(statement, index, value, -1, Self.sqliteTransient)
    } else {
      code = sqlite3_bind_null(statement, index)
    }
    try checkBind(code, operation: operation)
  }

  private func bind(_ value: Int64?, to statement: OpaquePointer, index: Int32, operation: String)
    throws
  {
    let code =
      value.map { sqlite3_bind_int64(statement, index, $0) } ?? sqlite3_bind_null(statement, index)
    try checkBind(code, operation: operation)
  }

  private func bind(_ value: Data?, to statement: OpaquePointer, index: Int32, operation: String)
    throws
  {
    let code: Int32
    if let value {
      guard value.count <= Int(Int32.max) else {
        throw CatalogStoreError.invalidRequest(
          operation: operation, message: "The BLOB value exceeds SQLite's Int32 binding limit.")
      }
      code = value.withUnsafeBytes { bytes in
        sqlite3_bind_blob(
          statement, index, bytes.baseAddress, Int32(value.count), Self.sqliteTransient)
      }
    } else {
      code = sqlite3_bind_null(statement, index)
    }
    try checkBind(code, operation: operation)
  }

  private func bind(assetID: UUID, to statement: OpaquePointer, index: Int32, operation: String)
    throws
  {
    try bind(assetID.uuidString.lowercased(), to: statement, index: index, operation: operation)
  }

  private func bind(jobID: UUID, to statement: OpaquePointer, index: Int32, operation: String)
    throws
  {
    try bind(jobID.uuidString.lowercased(), to: statement, index: index, operation: operation)
  }

  private func checkBind(_ code: Int32, operation: String) throws {
    guard code == SQLITE_OK else { throw sqliteError(operation: "\(operation).bind", code: code) }
  }

  private func ensureUsable(operation: String) throws {
    guard isUsable else {
      throw CatalogStoreError.closed(
        operation: operation, message: "The SQLite catalog connection is closed or unusable.")
    }
  }

  private func backupCleanupErrors(
    for destinationURL: URL,
    forcedMessage: String? = nil
  ) -> [String] {
    let artifacts = [
      destinationURL,
      URL(fileURLWithPath: destinationURL.path + "-wal"),
      URL(fileURLWithPath: destinationURL.path + "-shm"),
    ]
    var pendingForcedMessage = forcedMessage
    return artifacts.compactMap { artifact in
      guard FileManager.default.fileExists(atPath: artifact.path) else { return nil }
      if let message = pendingForcedMessage {
        pendingForcedMessage = nil
        return "\(artifact.lastPathComponent): \(message)"
      }
      do {
        try FileManager.default.removeItem(at: artifact)
        return nil
      } catch {
        return "\(artifact.lastPathComponent): \(error.localizedDescription)"
      }
    }
  }

  private func backupError(
    operation: String,
    database: OpaquePointer?,
    code: Int32,
    isInjected: Bool
  ) -> CatalogStoreError {
    if isInjected {
      return CatalogStoreError.sqlite(
        operation: operation,
        code: code,
        extendedCode: code,
        message: "A deterministic backup fault was injected."
      )
    }
    return Self.sqliteError(operation: operation, database: database, code: code)
  }

  private func columnData(_ statement: OpaquePointer, column: Int32, operation: String) throws
    -> Data
  {
    guard sqlite3_column_type(statement, column) != SQLITE_NULL else {
      throw CatalogStoreError.decoding(
        operation: operation, message: "A required BLOB value is NULL.")
    }
    let count = Int(sqlite3_column_bytes(statement, column))
    guard count >= 0, let bytes = sqlite3_column_blob(statement, column) else {
      throw CatalogStoreError.decoding(
        operation: operation, message: "A required BLOB value is invalid.")
    }
    return Data(bytes: bytes, count: count)
  }

  private func columnString(_ statement: OpaquePointer, column: Int32, operation: String) throws
    -> String
  {
    guard let value = sqlite3_column_text(statement, column) else {
      throw CatalogStoreError.decoding(
        operation: operation, message: "A required text value is NULL.")
    }
    return String(cString: value)
  }

  private func optionalColumnString(_ statement: OpaquePointer, column: Int32) -> String? {
    guard sqlite3_column_type(statement, column) != SQLITE_NULL,
      let value = sqlite3_column_text(statement, column)
    else {
      return nil
    }
    return String(cString: value)
  }

  private func optionalColumnData(_ statement: OpaquePointer, column: Int32) -> Data? {
    guard sqlite3_column_type(statement, column) != SQLITE_NULL else { return nil }
    let count = Int(sqlite3_column_bytes(statement, column))
    guard count >= 0 else { return nil }
    if count == 0 { return Data() }
    guard let bytes = sqlite3_column_blob(statement, column) else { return nil }
    return Data(bytes: bytes, count: count)
  }

  private func optionalDate(_ statement: OpaquePointer, column: Int32) -> Date? {
    guard sqlite3_column_type(statement, column) != SQLITE_NULL else { return nil }
    return Date(
      timeIntervalSince1970: TimeInterval(sqlite3_column_int64(statement, column)) / 1_000)
  }

  private func decodeAsset(_ statement: OpaquePointer, operation: String) throws -> PhotoAsset {
    guard let id = UUID(uuidString: try columnString(statement, column: 0, operation: operation))
    else {
      throw CatalogStoreError.decoding(operation: operation, message: "The asset ID is invalid.")
    }
    guard let sourceURL = URL(string: try columnString(statement, column: 1, operation: operation))
    else {
      throw CatalogStoreError.decoding(operation: operation, message: "The source URL is invalid.")
    }
    let filename = try columnString(statement, column: 2, operation: operation)
    let fingerprint: SourceFingerprint = try decode(
      SourceFingerprint.self,
      from: columnData(statement, column: 4, operation: operation),
      operation: operation
    )
    let dimensions = try optionalColumnData(statement, column: 7).map {
      try decode(PixelDimensions.self, from: $0, operation: operation)
    }
    let rating = sqlite3_column_int64(statement, 8)
    guard let integerRating = Int(exactly: rating), (0...5).contains(integerRating) else {
      throw CatalogStoreError.decoding(
        operation: operation, message: "The asset rating is invalid.")
    }
    let missing = sqlite3_column_int64(statement, 10)
    guard missing == 0 || missing == 1 else {
      throw CatalogStoreError.decoding(
        operation: operation, message: "The missing-file flag is invalid.")
    }
    guard
      let asset = PhotoAsset(
        id: id,
        sourceURL: sourceURL,
        filename: filename,
        typeIdentifier: optionalColumnString(statement, column: 3),
        fingerprint: fingerprint,
        importDate: Date(
          timeIntervalSince1970: TimeInterval(sqlite3_column_int64(statement, 5)) / 1_000),
        captureDate: optionalDate(statement, column: 6),
        pixelDimensions: dimensions,
        rating: integerRating,
        colorLabel: try optionalColumnData(statement, column: 9).map {
          try decode(ColorLabel.self, from: $0, operation: operation)
        },
        isMissing: missing == 1
      )
    else {
      throw CatalogStoreError.decoding(
        operation: operation, message: "The normalized asset row is invalid.")
    }
    return asset
  }

  private func encode<T: Encodable>(_ value: T, operation: String) throws -> Data {
    do {
      return try encoder.encode(value)
    } catch {
      throw CatalogStoreError.encoding(operation: operation, message: error.localizedDescription)
    }
  }

  private func decode<T: Decodable>(_ type: T.Type, from data: Data, operation: String) throws -> T
  {
    do {
      return try decoder.decode(T.self, from: data)
    } catch {
      throw CatalogStoreError.decoding(operation: operation, message: error.localizedDescription)
    }
  }

  private func sqliteError(operation: String, code: Int32) -> CatalogStoreError {
    Self.sqliteError(operation: operation, database: database, code: code)
  }

  private static func openDatabase(at url: URL) throws -> OpaquePointer {
    var database: OpaquePointer?
    let code = sqlite3_open_v2(
      url.path,
      &database,
      SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX,
      nil
    )
    guard code == SQLITE_OK, let database else {
      let primaryError = sqliteError(operation: "catalog.open", database: database, code: code)
      if let database {
        let closeCode = sqlite3_close_v2(database)
        guard closeCode == SQLITE_OK else {
          throw CatalogStoreError.cleanup(
            operation: "catalog.open.close",
            primaryError: primaryError.localizedDescription,
            cleanupError: sqliteError(
              operation: "catalog.open.close", database: database, code: closeCode
            ).localizedDescription
          )
        }
      }
      throw primaryError
    }
    return database
  }

  private static func configure(_ database: OpaquePointer) throws {
    try execute(
      "PRAGMA journal_mode=WAL;", database: database, operation: "catalog.configure.journalMode")
    try execute(
      "PRAGMA synchronous=FULL;", database: database, operation: "catalog.configure.synchronous")
    try execute(
      "PRAGMA foreign_keys=ON;", database: database, operation: "catalog.configure.foreignKeys")
    try execute(
      "PRAGMA busy_timeout=5000;", database: database, operation: "catalog.configure.busyTimeout")
    let journalMode = try scalarString(
      database, sql: "PRAGMA journal_mode;", operation: "catalog.configure.validateJournalMode")
    let synchronous = try scalarInt(
      database, sql: "PRAGMA synchronous;", operation: "catalog.configure.validateSynchronous")
    let foreignKeys = try scalarInt(
      database, sql: "PRAGMA foreign_keys;", operation: "catalog.configure.validateForeignKeys")
    let busyTimeout = try scalarInt(
      database, sql: "PRAGMA busy_timeout;", operation: "catalog.configure.validateBusyTimeout")
    guard journalMode.caseInsensitiveCompare("wal") == .orderedSame,
      synchronous == 2,
      foreignKeys == 1,
      busyTimeout == 5_000
    else {
      throw CatalogStoreError.unsupported(
        operation: "catalog.configure",
        message: "SQLite did not accept the required durability configuration."
      )
    }
  }

  private static func readSchemaVersion(_ database: OpaquePointer) throws -> Int64 {
    try scalarInt(database, sql: "PRAGMA user_version;", operation: "catalog.open.version")
  }

  private static func migrate(
    _ database: OpaquePointer,
    version: Int64,
    ftsAvailabilityOverride: Bool?
  ) throws
    -> Bool
  {
    let shouldUseFTS = ftsAvailabilityOverride ?? (sqlite3_compileoption_used("ENABLE_FTS5") != 0)
    if version == schemaVersion {
      return try validateVersionOneSchema(database, shouldUseFTS: shouldUseFTS)
    }

    try execute("BEGIN IMMEDIATE;", database: database, operation: "catalog.migrate.begin")
    do {
      try execute(
        """
        CREATE TABLE assets (
          id TEXT PRIMARY KEY,
          source_url TEXT NOT NULL,
          filename TEXT NOT NULL,
          type_identifier TEXT,
          fingerprint_json BLOB NOT NULL,
          import_ms INTEGER NOT NULL,
          capture_ms INTEGER,
          dimensions_json BLOB,
          rating INTEGER NOT NULL CHECK (rating BETWEEN 0 AND 5),
          color_label BLOB,
          is_missing INTEGER NOT NULL CHECK (is_missing IN (0, 1))
        );
        CREATE INDEX assets_import_ms_index ON assets(import_ms);
        CREATE INDEX assets_capture_ms_index ON assets(capture_ms);
        CREATE INDEX assets_filename_index ON assets(filename COLLATE NOCASE);
        CREATE TABLE edit_recipes (
          asset_id TEXT NOT NULL REFERENCES assets(id) ON DELETE CASCADE,
          revision INTEGER NOT NULL,
          date_ms INTEGER NOT NULL,
          recipe_json BLOB NOT NULL,
          PRIMARY KEY (asset_id, revision)
        );
        CREATE TABLE catalog_jobs (
          id TEXT PRIMARY KEY,
          created_ms INTEGER NOT NULL,
          updated_ms INTEGER NOT NULL,
          job_json BLOB NOT NULL
        );
        CREATE INDEX catalog_jobs_updated_ms_index ON catalog_jobs(updated_ms, created_ms);
        CREATE TABLE asset_bookmarks (
          asset_id TEXT PRIMARY KEY REFERENCES assets(id) ON DELETE CASCADE,
          bookmark BLOB NOT NULL,
          updated_ms INTEGER NOT NULL
        );
        """,
        database: database,
        operation: "catalog.migrate.v1"
      )
      var ftsAvailable = false
      if shouldUseFTS {
        do {
          try execute(
            "CREATE VIRTUAL TABLE asset_search USING fts5(asset_id UNINDEXED, filename, type_identifier, source_url);",
            database: database,
            operation: "catalog.migrate.fts"
          )
          ftsAvailable = true
        } catch let error as CatalogStoreError {
          guard case .sqlite(_, _, _, let message) = error,
            message.localizedCaseInsensitiveContains("fts5")
              || message.localizedCaseInsensitiveContains("no such module")
          else {
            throw error
          }
          // FTS5 is optional. Other SQLite failures can corrupt or invalidate the catalog.
          ftsAvailable = false
        } catch {
          throw error
        }
      }
      try execute(
        "PRAGMA user_version=1;", database: database, operation: "catalog.migrate.setVersion")
      try execute("COMMIT;", database: database, operation: "catalog.migrate.commit")
      return ftsAvailable
    } catch let primaryError {
      do {
        try execute("ROLLBACK;", database: database, operation: "catalog.migrate.rollback")
      } catch let rollbackError {
        throw CatalogStoreError.cleanup(
          operation: "catalog.migrate",
          primaryError: String(describing: primaryError),
          cleanupError: String(describing: rollbackError)
        )
      }
      throw primaryError
    }
  }

  private static func withStaticStatement<T>(
    _ database: OpaquePointer,
    sql: String,
    operation: String,
    _ body: (OpaquePointer) throws -> T
  ) throws -> T {
    var statement: OpaquePointer?
    let prepareCode = sqlite3_prepare_v2(database, sql, -1, &statement, nil)
    guard prepareCode == SQLITE_OK, let statement else {
      throw sqliteError(operation: "\(operation).prepare", database: database, code: prepareCode)
    }
    let result: Result<T, Error>
    do {
      result = .success(try body(statement))
    } catch {
      result = .failure(error)
    }
    let finalizeCode = sqlite3_finalize(statement)
    switch result {
    case .success(let value):
      guard finalizeCode == SQLITE_OK else {
        throw sqliteError(
          operation: "\(operation).finalize", database: database, code: finalizeCode)
      }
      return value
    case .failure(let primaryError):
      guard finalizeCode == SQLITE_OK else {
        throw CatalogStoreError.cleanup(
          operation: "\(operation).finalize",
          primaryError: String(describing: primaryError),
          cleanupError: sqliteError(
            operation: "\(operation).finalize", database: database, code: finalizeCode
          ).localizedDescription
        )
      }
      throw primaryError
    }
  }

  private static func tableExists(_ database: OpaquePointer, name: String) throws -> Bool {
    try withStaticStatement(
      database,
      sql: "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ? LIMIT 1;",
      operation: "catalog.migrate.tableExists"
    ) { statement in
      let bindCode = sqlite3_bind_text(statement, 1, name, -1, sqliteTransient)
      guard bindCode == SQLITE_OK else {
        throw sqliteError(
          operation: "catalog.migrate.tableExists.bind", database: database, code: bindCode)
      }
      let stepCode = sqlite3_step(statement)
      if stepCode == SQLITE_ROW { return true }
      if stepCode == SQLITE_DONE { return false }
      throw sqliteError(
        operation: "catalog.migrate.tableExists.step", database: database, code: stepCode)
    }
  }

  private static func validateVersionOneSchema(
    _ database: OpaquePointer,
    shouldUseFTS: Bool
  ) throws -> Bool {
    let requiredColumns: [String: [SQLiteSchemaColumn]] = [
      "assets": [
        .init(
          position: 0, name: "id", type: "TEXT", isNotNull: false, defaultValue: nil,
          primaryKeyPosition: 1),
        .init(
          position: 1, name: "source_url", type: "TEXT", isNotNull: true, defaultValue: nil,
          primaryKeyPosition: 0),
        .init(
          position: 2, name: "filename", type: "TEXT", isNotNull: true, defaultValue: nil,
          primaryKeyPosition: 0),
        .init(
          position: 3, name: "type_identifier", type: "TEXT", isNotNull: false,
          defaultValue: nil, primaryKeyPosition: 0),
        .init(
          position: 4, name: "fingerprint_json", type: "BLOB", isNotNull: true,
          defaultValue: nil, primaryKeyPosition: 0),
        .init(
          position: 5, name: "import_ms", type: "INTEGER", isNotNull: true,
          defaultValue: nil, primaryKeyPosition: 0),
        .init(
          position: 6, name: "capture_ms", type: "INTEGER", isNotNull: false,
          defaultValue: nil, primaryKeyPosition: 0),
        .init(
          position: 7, name: "dimensions_json", type: "BLOB", isNotNull: false,
          defaultValue: nil, primaryKeyPosition: 0),
        .init(
          position: 8, name: "rating", type: "INTEGER", isNotNull: true, defaultValue: nil,
          primaryKeyPosition: 0),
        .init(
          position: 9, name: "color_label", type: "BLOB", isNotNull: false,
          defaultValue: nil, primaryKeyPosition: 0),
        .init(
          position: 10, name: "is_missing", type: "INTEGER", isNotNull: true,
          defaultValue: nil, primaryKeyPosition: 0),
      ],
      "edit_recipes": [
        .init(
          position: 0, name: "asset_id", type: "TEXT", isNotNull: true, defaultValue: nil,
          primaryKeyPosition: 1),
        .init(
          position: 1, name: "revision", type: "INTEGER", isNotNull: true, defaultValue: nil,
          primaryKeyPosition: 2),
        .init(
          position: 2, name: "date_ms", type: "INTEGER", isNotNull: true, defaultValue: nil,
          primaryKeyPosition: 0),
        .init(
          position: 3, name: "recipe_json", type: "BLOB", isNotNull: true, defaultValue: nil,
          primaryKeyPosition: 0),
      ],
      "catalog_jobs": [
        .init(
          position: 0, name: "id", type: "TEXT", isNotNull: false, defaultValue: nil,
          primaryKeyPosition: 1),
        .init(
          position: 1, name: "created_ms", type: "INTEGER", isNotNull: true,
          defaultValue: nil, primaryKeyPosition: 0),
        .init(
          position: 2, name: "updated_ms", type: "INTEGER", isNotNull: true,
          defaultValue: nil, primaryKeyPosition: 0),
        .init(
          position: 3, name: "job_json", type: "BLOB", isNotNull: true, defaultValue: nil,
          primaryKeyPosition: 0),
      ],
      "asset_bookmarks": [
        .init(
          position: 0, name: "asset_id", type: "TEXT", isNotNull: false, defaultValue: nil,
          primaryKeyPosition: 1),
        .init(
          position: 1, name: "bookmark", type: "BLOB", isNotNull: true, defaultValue: nil,
          primaryKeyPosition: 0),
        .init(
          position: 2, name: "updated_ms", type: "INTEGER", isNotNull: true,
          defaultValue: nil, primaryKeyPosition: 0),
      ],
    ]
    for (table, expected) in requiredColumns {
      guard try tableExists(database, name: table) else {
        throw schemaError("The required table '\(table)' is missing.")
      }
      let actual = try tableColumns(database, table: table)
      guard expected == actual else {
        throw schemaError("The table '\(table)' does not have the exact version-1 columns.")
      }
    }
    let expectedTableSQL = [
      "assets": """
      CREATE TABLE assets (
        id TEXT PRIMARY KEY,
        source_url TEXT NOT NULL,
        filename TEXT NOT NULL,
        type_identifier TEXT,
        fingerprint_json BLOB NOT NULL,
        import_ms INTEGER NOT NULL,
        capture_ms INTEGER,
        dimensions_json BLOB,
        rating INTEGER NOT NULL CHECK (rating BETWEEN 0 AND 5),
        color_label BLOB,
        is_missing INTEGER NOT NULL CHECK (is_missing IN (0, 1))
      )
      """,
      "edit_recipes": """
      CREATE TABLE edit_recipes (
        asset_id TEXT NOT NULL REFERENCES assets(id) ON DELETE CASCADE,
        revision INTEGER NOT NULL,
        date_ms INTEGER NOT NULL,
        recipe_json BLOB NOT NULL,
        PRIMARY KEY (asset_id, revision)
      )
      """,
      "catalog_jobs": """
      CREATE TABLE catalog_jobs (
        id TEXT PRIMARY KEY,
        created_ms INTEGER NOT NULL,
        updated_ms INTEGER NOT NULL,
        job_json BLOB NOT NULL
      )
      """,
      "asset_bookmarks": """
      CREATE TABLE asset_bookmarks (
        asset_id TEXT PRIMARY KEY REFERENCES assets(id) ON DELETE CASCADE,
        bookmark BLOB NOT NULL,
        updated_ms INTEGER NOT NULL
      )
      """,
    ]
    for (table, expectedSQL) in expectedTableSQL {
      try validateSchemaSQL(
        database, object: table, type: "table", expectedSQL: expectedSQL)
    }

    let expectedIndexes: [String: (sql: String, columns: [SQLiteIndexColumn])] = [
      "assets_import_ms_index": (
        "CREATE INDEX assets_import_ms_index ON assets(import_ms)",
        [
          .init(
            sequence: 0, tableColumn: 5, name: "import_ms", isDescending: false,
            collation: "BINARY", isKey: true),
          .init(
            sequence: 1, tableColumn: -1, name: nil, isDescending: false,
            collation: "BINARY", isKey: false),
        ]
      ),
      "assets_capture_ms_index": (
        "CREATE INDEX assets_capture_ms_index ON assets(capture_ms)",
        [
          .init(
            sequence: 0, tableColumn: 6, name: "capture_ms", isDescending: false,
            collation: "BINARY", isKey: true),
          .init(
            sequence: 1, tableColumn: -1, name: nil, isDescending: false,
            collation: "BINARY", isKey: false),
        ]
      ),
      "assets_filename_index": (
        "CREATE INDEX assets_filename_index ON assets(filename COLLATE NOCASE)",
        [
          .init(
            sequence: 0, tableColumn: 2, name: "filename", isDescending: false,
            collation: "NOCASE", isKey: true),
          .init(
            sequence: 1, tableColumn: -1, name: nil, isDescending: false,
            collation: "BINARY", isKey: false),
        ]
      ),
      "catalog_jobs_updated_ms_index": (
        "CREATE INDEX catalog_jobs_updated_ms_index ON catalog_jobs(updated_ms, created_ms)",
        [
          .init(
            sequence: 0, tableColumn: 2, name: "updated_ms", isDescending: false,
            collation: "BINARY", isKey: true),
          .init(
            sequence: 1, tableColumn: 1, name: "created_ms", isDescending: false,
            collation: "BINARY", isKey: true),
          .init(
            sequence: 2, tableColumn: -1, name: nil, isDescending: false,
            collation: "BINARY", isKey: false),
        ]
      ),
    ]
    for (index, expected) in expectedIndexes {
      try validateSchemaSQL(
        database, object: index, type: "index", expectedSQL: expected.sql)
      guard try indexColumns(database, index: index) == expected.columns else {
        throw schemaError("The index '\(index)' does not have the exact version-1 definition.")
      }
    }
    try validateForeignKey(
      database, table: "edit_recipes", column: "asset_id", referencedTable: "assets")
    try validateForeignKey(
      database, table: "asset_bookmarks", column: "asset_id", referencedTable: "assets")

    let ftsAvailable: Bool
    if shouldUseFTS {
      ftsAvailable = try tableExists(database, name: "asset_search")
      if ftsAvailable {
        try validateSchemaSQL(
          database,
          object: "asset_search",
          type: "table",
          expectedSQL:
            "CREATE VIRTUAL TABLE asset_search USING fts5(asset_id UNINDEXED, filename, type_identifier, source_url)"
        )
      }
    } else {
      ftsAvailable = false
    }
    let queries =
      [
        "SELECT id, source_url, filename, type_identifier, fingerprint_json, import_ms, capture_ms, dimensions_json, rating, color_label, is_missing FROM assets WHERE id = ?;",
        "SELECT recipe_json FROM edit_recipes WHERE asset_id = ? ORDER BY revision DESC, date_ms DESC LIMIT 1;",
        "SELECT job_json FROM catalog_jobs ORDER BY updated_ms DESC, id ASC;",
        "SELECT bookmark FROM asset_bookmarks WHERE asset_id = ?;",
      ]
      + (ftsAvailable
        ? [
          "SELECT assets.id FROM asset_search JOIN assets ON assets.id = asset_search.asset_id WHERE asset_search MATCH ? LIMIT 1;"
        ] : [])
    for query in queries {
      try validateQuery(database, sql: query)
    }
    return ftsAvailable
  }

  private static func indexColumns(_ database: OpaquePointer, index: String) throws
    -> [SQLiteIndexColumn]
  {
    try withStaticStatement(
      database,
      sql: "PRAGMA index_xinfo(\(index));",
      operation: "catalog.validate.indexColumns"
    ) { statement in
      var columns: [SQLiteIndexColumn] = []
      while true {
        let stepCode = sqlite3_step(statement)
        if stepCode == SQLITE_DONE { return columns }
        guard stepCode == SQLITE_ROW else {
          throw sqliteError(
            operation: "catalog.validate.indexColumns.step", database: database, code: stepCode)
        }
        columns.append(
          SQLiteIndexColumn(
            sequence: sqlite3_column_int(statement, 0),
            tableColumn: sqlite3_column_int(statement, 1),
            name: sqlite3_column_text(statement, 2).map { String(cString: $0) },
            isDescending: sqlite3_column_int(statement, 3) != 0,
            collation: sqlite3_column_text(statement, 4).map { String(cString: $0) },
            isKey: sqlite3_column_int(statement, 5) != 0
          ))
      }
    }
  }

  private static func validateSchemaSQL(
    _ database: OpaquePointer,
    object: String,
    type: String,
    expectedSQL: String
  ) throws {
    let sql: String = try withStaticStatement(
      database,
      sql: "SELECT sql FROM sqlite_master WHERE type = ? AND name = ?;",
      operation: "catalog.validate.sql"
    ) { statement in
      guard sqlite3_bind_text(statement, 1, type, -1, sqliteTransient) == SQLITE_OK,
        sqlite3_bind_text(statement, 2, object, -1, sqliteTransient) == SQLITE_OK
      else {
        throw sqliteError(
          operation: "catalog.validate.sql.bind", database: database,
          code: sqlite3_errcode(database))
      }
      guard sqlite3_step(statement) == SQLITE_ROW, let value = sqlite3_column_text(statement, 0)
      else {
        throw schemaError("The SQL definition for '\(object)' is missing.")
      }
      return String(cString: value)
    }
    let normalized = sql.lowercased().filter { !$0.isWhitespace }
    let expectedNormalized = expectedSQL.lowercased().filter { !$0.isWhitespace }
    guard normalized == expectedNormalized else {
      throw schemaError("The SQL definition for '\(object)' is not version-1 compatible.")
    }
  }

  private static func tableColumns(_ database: OpaquePointer, table: String) throws
    -> [SQLiteSchemaColumn]
  {
    try withStaticStatement(
      database, sql: "PRAGMA table_info(\(table));", operation: "catalog.validate.columns"
    ) { statement in
      var columns: [SQLiteSchemaColumn] = []
      while true {
        let stepCode = sqlite3_step(statement)
        if stepCode == SQLITE_DONE { return columns }
        guard stepCode == SQLITE_ROW else {
          throw sqliteError(
            operation: "catalog.validate.columns.step", database: database, code: stepCode)
        }
        guard let name = sqlite3_column_text(statement, 1),
          let type = sqlite3_column_text(statement, 2)
        else {
          throw schemaError("A schema column name or type is NULL.")
        }
        columns.append(
          SQLiteSchemaColumn(
            position: sqlite3_column_int(statement, 0),
            name: String(cString: name),
            type: String(cString: type).uppercased(),
            isNotNull: sqlite3_column_int(statement, 3) != 0,
            defaultValue: sqlite3_column_text(statement, 4).map { String(cString: $0) },
            primaryKeyPosition: sqlite3_column_int(statement, 5)
          ))
      }
    }
  }

  private static func validateForeignKey(
    _ database: OpaquePointer,
    table: String,
    column: String,
    referencedTable: String
  ) throws {
    try withStaticStatement(
      database, sql: "PRAGMA foreign_key_list(\(table));", operation: "catalog.validate.foreignKey"
    ) { statement in
      while true {
        let stepCode = sqlite3_step(statement)
        if stepCode == SQLITE_DONE { break }
        guard stepCode == SQLITE_ROW else {
          throw sqliteError(
            operation: "catalog.validate.foreignKey.step", database: database, code: stepCode)
        }
        let target = sqlite3_column_text(statement, 2).map { String(cString: $0) }
        let source = sqlite3_column_text(statement, 3).map { String(cString: $0) }
        let deleteAction = sqlite3_column_text(statement, 6).map { String(cString: $0) }
        if source == column && target == referencedTable && deleteAction == "CASCADE" { return }
      }
      throw schemaError("The table '\(table)' does not have the required cascading foreign key.")
    }
  }

  private static func validateQuery(_ database: OpaquePointer, sql: String) throws {
    var statement: OpaquePointer?
    let code = sqlite3_prepare_v2(database, sql, -1, &statement, nil)
    guard code == SQLITE_OK, let statement else {
      throw sqliteError(operation: "catalog.validate.query", database: database, code: code)
    }
    let finalizeCode = sqlite3_finalize(statement)
    guard finalizeCode == SQLITE_OK else {
      throw sqliteError(
        operation: "catalog.validate.query.finalize", database: database, code: finalizeCode)
    }
  }

  private static func schemaError(_ message: String) -> CatalogStoreError {
    CatalogStoreError.unsupported(operation: "catalog.validate", message: message)
  }

  private static func scalarInt(_ database: OpaquePointer, sql: String, operation: String) throws
    -> Int64
  {
    try withStaticStatement(database, sql: sql, operation: operation) { statement in
      let stepCode = sqlite3_step(statement)
      guard stepCode == SQLITE_ROW else {
        throw sqliteError(operation: "\(operation).step", database: database, code: stepCode)
      }
      return sqlite3_column_int64(statement, 0)
    }
  }

  private static func scalarString(_ database: OpaquePointer, sql: String, operation: String) throws
    -> String
  {
    try withStaticStatement(database, sql: sql, operation: operation) { statement in
      let stepCode = sqlite3_step(statement)
      guard stepCode == SQLITE_ROW, let value = sqlite3_column_text(statement, 0) else {
        throw sqliteError(operation: "\(operation).step", database: database, code: stepCode)
      }
      return String(cString: value)
    }
  }

  private static func execute(_ sql: String, database: OpaquePointer, operation: String) throws {
    var errorMessage: UnsafeMutablePointer<CChar>?
    let code = sqlite3_exec(database, sql, nil, nil, &errorMessage)
    defer {
      if let errorMessage { sqlite3_free(errorMessage) }
    }
    guard code == SQLITE_OK else {
      let message =
        errorMessage.map { String(cString: $0) } ?? String(cString: sqlite3_errmsg(database))
      throw CatalogStoreError.sqlite(
        operation: operation,
        code: code,
        extendedCode: sqlite3_extended_errcode(database),
        message: message
      )
    }
  }

  private static func sqliteError(
    operation: String,
    database: OpaquePointer?,
    code: Int32
  ) -> CatalogStoreError {
    let message =
      database.map { String(cString: sqlite3_errmsg($0)) }
      ?? "SQLite could not open a database handle."
    let extendedCode = database.map { sqlite3_extended_errcode($0) } ?? code
    return CatalogStoreError.sqlite(
      operation: operation, code: code, extendedCode: extendedCode, message: message)
  }

  private static func makeEncoder() -> JSONEncoder {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .millisecondsSince1970
    encoder.outputFormatting = [.sortedKeys]
    return encoder
  }

  private static func makeDecoder() -> JSONDecoder {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .millisecondsSince1970
    return decoder
  }

  private static let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

  private func milliseconds(_ date: Date) -> Int64 {
    Int64((date.timeIntervalSince1970 * 1_000).rounded())
  }

  private func escapeLike(_ value: String) -> String {
    value
      .replacingOccurrences(of: "\\", with: "\\\\")
      .replacingOccurrences(of: "%", with: "\\%")
      .replacingOccurrences(of: "_", with: "\\_")
  }
}
