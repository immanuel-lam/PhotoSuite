// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import PhotoDomain
import SQLite3

private final class SQLiteConnection: @unchecked Sendable {
  let database: OpaquePointer

  init(database: OpaquePointer) {
    self.database = database
  }

  deinit {
    _ = sqlite3_close_v2(database)
  }
}

public actor SQLiteCatalogStore: CatalogStore, JobEngine {
  private static let schemaVersion: Int64 = 1
  private let connection: SQLiteConnection
  private let ftsAvailable: Bool
  private let encoder: JSONEncoder
  private let decoder: JSONDecoder

  private var database: OpaquePointer { connection.database }

  public init(catalogURL: URL) throws {
    try self.init(catalogURL: catalogURL, ftsAvailabilityOverride: nil)
  }

  init(catalogURL: URL, ftsAvailabilityOverride: Bool?) throws {
    guard catalogURL.isFileURL else {
      throw CatalogStoreError.invalidRequest(
        operation: "catalog.open",
        message: "The catalog URL must be a file URL."
      )
    }

    let database = try Self.openDatabase(at: catalogURL)
    do {
      try Self.configure(database)
      let ftsAvailable = try Self.migrate(
        database, ftsAvailabilityOverride: ftsAvailabilityOverride)
      self.connection = SQLiteConnection(database: database)
      self.ftsAvailable = ftsAvailable
      self.encoder = Self.makeEncoder()
      self.decoder = Self.makeDecoder()
    } catch {
      _ = sqlite3_close_v2(database)
      throw error
    }
  }

  public func upsertAsset(
    _ request: CatalogAssetUpsertRequest
  ) async throws -> CatalogAssetUpsertResult {
    try storeAsset(request.asset)
    return CatalogAssetUpsertResult(asset: request.asset)
  }

  private func storeAsset(_ asset: PhotoAsset) throws {
    let assetJSON = try encode(asset, operation: "asset.upsert.encode")
    try withTransaction(operation: "asset.upsert") {
      try withStatement(
        """
        INSERT INTO assets (
          id, source_url, filename, type_identifier, fingerprint_json, import_ms,
          capture_ms, dimensions_json, rating, color_label, is_missing, asset_json
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
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
          is_missing=excluded.is_missing,
          asset_json=excluded.asset_json;
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
          asset.colorLabel?.rawValue, to: statement, index: 10, operation: "asset.upsert")
        try bind(
          asset.isMissing ? Int64(1) : Int64(0), to: statement, index: 11,
          operation: "asset.upsert")
        try bind(assetJSON, to: statement, index: 12, operation: "asset.upsert")
        try stepDone(statement, operation: "asset.upsert")
      }
      try updateSearchIndex(for: asset)
    }
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
        sql: "SELECT asset_json FROM assets ORDER BY \(order) LIMIT ? OFFSET ?;",
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

    if ftsAvailable, query.allSatisfy({ $0.isLetter || $0.isNumber || $0.isWhitespace }) {
      return CatalogAssetSearchResult(
        assets: try assets(
          sql: """
            SELECT assets.asset_json
            FROM asset_search
            JOIN assets ON assets.id = asset_search.asset_id
            WHERE asset_search MATCH ?
            ORDER BY assets.import_ms DESC, assets.id ASC
            LIMIT ?;
            """,
          operation: "asset.search.fts",
          bindValues: { statement in
            try bind(query, to: statement, index: 1, operation: "asset.search.fts")
            try bind(limit, to: statement, index: 2, operation: "asset.search.fts")
          }
        )
      )
    }

    let pattern = "%\(escapeLike(query))%"
    return CatalogAssetSearchResult(
      assets: try assets(
        sql: """
          SELECT asset_json FROM assets
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
    try storeAsset(relinked)
    return CatalogRelinkAssetResult(asset: relinked)
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
    guard request.destinationURL.isFileURL else {
      throw CatalogStoreError.invalidRequest(
        operation: "catalog.backup", message: "The destination must be a file URL.")
    }
    var destination: OpaquePointer?
    let openCode = sqlite3_open_v2(
      request.destinationURL.path,
      &destination,
      SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX,
      nil
    )
    guard openCode == SQLITE_OK, let destination else {
      let error = Self.sqliteError(
        operation: "catalog.backup.open", database: destination, code: openCode)
      if let destination { _ = sqlite3_close_v2(destination) }
      throw error
    }
    defer { _ = sqlite3_close_v2(destination) }

    guard let backup = sqlite3_backup_init(destination, "main", database, "main") else {
      throw Self.sqliteError(
        operation: "catalog.backup.init", database: destination, code: sqlite3_errcode(destination))
    }
    let start = Date()
    var stepCode: Int32 = SQLITE_OK
    repeat {
      stepCode = sqlite3_backup_step(backup, -1)
      if stepCode == SQLITE_BUSY || stepCode == SQLITE_LOCKED {
        _ = sqlite3_sleep(50)
      }
    } while (stepCode == SQLITE_BUSY || stepCode == SQLITE_LOCKED)
      && Date().timeIntervalSince(start) < 5
    let finishCode = sqlite3_backup_finish(backup)
    guard stepCode == SQLITE_DONE else {
      throw Self.sqliteError(
        operation: "catalog.backup.step", database: destination, code: stepCode)
    }
    guard finishCode == SQLITE_OK else {
      throw Self.sqliteError(
        operation: "catalog.backup.finish", database: destination, code: finishCode)
    }
    return CatalogBackupResult(destinationURL: request.destinationURL)
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
    try withStatement("SELECT asset_json FROM assets WHERE id = ?;", operation: operation) {
      statement in
      try bind(assetID: id, to: statement, index: 1, operation: operation)
      let code = sqlite3_step(statement)
      if code == SQLITE_DONE { return nil }
      guard code == SQLITE_ROW else { throw sqliteError(operation: operation, code: code) }
      return try decode(
        PhotoAsset.self, from: columnData(statement, column: 0, operation: operation),
        operation: operation)
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
        results.append(
          try decode(
            PhotoAsset.self, from: columnData(statement, column: 0, operation: operation),
            operation: operation))
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
    try execute("BEGIN IMMEDIATE;", operation: "\(operation).begin")
    do {
      let result = try body()
      try execute("COMMIT;", operation: "\(operation).commit")
      return result
    } catch {
      _ = try? execute("ROLLBACK;", operation: "\(operation).rollback")
      throw error
    }
  }

  private func withStatement<T>(
    _ sql: String,
    operation: String,
    _ body: (OpaquePointer) throws -> T
  ) throws -> T {
    var statement: OpaquePointer?
    let prepareCode = sqlite3_prepare_v2(database, sql, -1, &statement, nil)
    guard prepareCode == SQLITE_OK, let statement else {
      throw sqliteError(operation: "\(operation).prepare", code: prepareCode)
    }
    let result: T
    do {
      result = try body(statement)
    } catch {
      _ = sqlite3_finalize(statement)
      throw error
    }
    let finalizeCode = sqlite3_finalize(statement)
    guard finalizeCode == SQLITE_OK else {
      throw sqliteError(operation: "\(operation).finalize", code: finalizeCode)
    }
    return result
  }

  private func execute(_ sql: String, operation: String) throws {
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
      let error = sqliteError(operation: "catalog.open", database: database, code: code)
      if let database { _ = sqlite3_close_v2(database) }
      throw error
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
  }

  private static func migrate(_ database: OpaquePointer, ftsAvailabilityOverride: Bool?) throws
    -> Bool
  {
    let version = try scalarInt(
      database, sql: "PRAGMA user_version;", operation: "catalog.migrate.version")
    guard version <= schemaVersion else {
      throw CatalogStoreError.unsupported(
        operation: "catalog.migrate",
        message:
          "Catalog schema version \(version) is newer than supported version \(schemaVersion)."
      )
    }
    let shouldUseFTS = ftsAvailabilityOverride ?? (sqlite3_compileoption_used("ENABLE_FTS5") != 0)
    if version == schemaVersion {
      if !shouldUseFTS { return false }
      return try tableExists(database, name: "asset_search")
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
          color_label TEXT,
          is_missing INTEGER NOT NULL CHECK (is_missing IN (0, 1)),
          asset_json BLOB NOT NULL
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
    } catch {
      _ = try? execute("ROLLBACK;", database: database, operation: "catalog.migrate.rollback")
      throw error
    }
  }

  private static func tableExists(_ database: OpaquePointer, name: String) throws -> Bool {
    var statement: OpaquePointer?
    let code = sqlite3_prepare_v2(
      database,
      "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ? LIMIT 1;",
      -1,
      &statement,
      nil
    )
    guard code == SQLITE_OK, let statement else {
      throw sqliteError(
        operation: "catalog.migrate.tableExists.prepare", database: database, code: code)
    }
    defer { _ = sqlite3_finalize(statement) }
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

  private static func scalarInt(_ database: OpaquePointer, sql: String, operation: String) throws
    -> Int64
  {
    var statement: OpaquePointer?
    let code = sqlite3_prepare_v2(database, sql, -1, &statement, nil)
    guard code == SQLITE_OK, let statement else {
      throw sqliteError(operation: "\(operation).prepare", database: database, code: code)
    }
    defer { _ = sqlite3_finalize(statement) }
    let stepCode = sqlite3_step(statement)
    guard stepCode == SQLITE_ROW else {
      throw sqliteError(operation: "\(operation).step", database: database, code: stepCode)
    }
    return sqlite3_column_int64(statement, 0)
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
