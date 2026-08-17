// SPDX-License-Identifier: MPL-2.0

import Foundation
import PhotoDomain
import XCTest

final class MaskServiceContractTests: XCTestCase {
  func testMaskServiceRequestsAndResultAreCodableHashableSendableValues() throws {
    let assetID = UUID(uuidString: "11111111-0000-0000-0000-000000000001")!
    let maskID = UUID(uuidString: "22222222-0000-0000-0000-000000000001")!
    let requestID = UUID(uuidString: "33333333-0000-0000-0000-000000000001")!
    let revision = MaskRevisionIdentity(assetID: assetID, maskID: maskID, revision: 7)
    let requestIdentity = MaskRequestIdentity(revision: revision, requestID: requestID)
    let editRequest = MaskEditRequest(identity: requestIdentity, edit: .invert)
    let duplicate = try XCTUnwrap(
      MaskDuplicateRequest(
        identity: requestIdentity,
        destination: MaskTargetIdentity(
          assetID: assetID,
          maskID: UUID(uuidString: "22222222-0000-0000-0000-000000000002")!
        )
      )
    )
    let sync = try XCTUnwrap(
      MaskSyncRequest(
        identity: requestIdentity,
        destinations: [
          MaskTargetIdentity(
            assetID: UUID(uuidString: "11111111-0000-0000-0000-000000000002")!,
            maskID: UUID(uuidString: "22222222-0000-0000-0000-000000000003")!
          )
        ]
      )
    )
    let record = MaskGraphRecord(
      identity: MaskRevisionIdentity(assetID: assetID, maskID: maskID, revision: 8),
      graph: MaskGraphV1(isInverted: true)
    )
    let result = MaskOperationResult(requestIdentity: requestIdentity, records: [record])

    try assertValueContract(editRequest)
    try assertValueContract(duplicate)
    try assertValueContract(sync)
    try assertValueContract(result)
    assertSendable(editRequest)
    assertSendable(duplicate)
    assertSendable(sync)
    assertSendable(result)
  }

  func testDuplicateAndSyncRejectSourceAndDuplicateTargets() throws {
    let assetID = UUID(uuidString: "11111111-0000-0000-0000-000000000001")!
    let maskID = UUID(uuidString: "22222222-0000-0000-0000-000000000001")!
    let identity = MaskRequestIdentity(
      revision: MaskRevisionIdentity(assetID: assetID, maskID: maskID, revision: 2),
      requestID: UUID()
    )
    let source = MaskTargetIdentity(assetID: assetID, maskID: maskID)
    let destination = MaskTargetIdentity(assetID: UUID(), maskID: UUID())

    XCTAssertNil(MaskDuplicateRequest(identity: identity, destination: source))
    XCTAssertNil(MaskSyncRequest(identity: identity, destinations: []))
    XCTAssertNil(MaskSyncRequest(identity: identity, destinations: [source]))
    XCTAssertNil(
      MaskSyncRequest(identity: identity, destinations: [destination, destination])
    )
  }

  func testMaskServiceProtocolIncludesEditDuplicateAndSynchronizeOperations() async throws {
    let service: any MaskService = EchoMaskService()
    let identity = MaskRequestIdentity(
      revision: MaskRevisionIdentity(assetID: UUID(), maskID: UUID(), revision: 0),
      requestID: UUID()
    )
    let destination = MaskTargetIdentity(assetID: UUID(), maskID: UUID())
    let duplicate = try XCTUnwrap(
      MaskDuplicateRequest(identity: identity, destination: destination)
    )
    let sync = try XCTUnwrap(
      MaskSyncRequest(identity: identity, destinations: [destination])
    )

    let editResult = try await service.apply(
      MaskEditRequest(identity: identity, edit: .invert)
    )
    let duplicateResult = try await service.duplicate(duplicate)
    let syncResult = try await service.synchronize(sync)

    XCTAssertEqual(editResult.requestIdentity, identity)
    XCTAssertEqual(duplicateResult.requestIdentity, identity)
    XCTAssertEqual(syncResult.requestIdentity, identity)
  }

  private func assertValueContract<T: Codable & Hashable & Sendable>(_ value: T) throws {
    let data = try JSONEncoder().encode(value)
    XCTAssertEqual(try JSONDecoder().decode(T.self, from: data), value)
    XCTAssertEqual(Set([value, value]).count, 1)
  }

  private func assertSendable<T: Sendable>(_: T) {}
}

private struct EchoMaskService: MaskService {
  func apply(_ request: MaskEditRequest) async throws -> MaskOperationResult {
    MaskOperationResult(requestIdentity: request.identity, records: [])
  }

  func duplicate(_ request: MaskDuplicateRequest) async throws -> MaskOperationResult {
    MaskOperationResult(requestIdentity: request.identity, records: [])
  }

  func synchronize(_ request: MaskSyncRequest) async throws -> MaskOperationResult {
    MaskOperationResult(requestIdentity: request.identity, records: [])
  }
}
