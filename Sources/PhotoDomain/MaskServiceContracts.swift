// SPDX-License-Identifier: MPL-2.0

import Foundation

public struct MaskRevisionIdentity: Codable, Hashable, Sendable {
  public let assetID: UUID
  public let maskID: UUID
  public let revision: UInt64

  public init(assetID: UUID, maskID: UUID, revision: UInt64) {
    self.assetID = assetID
    self.maskID = maskID
    self.revision = revision
  }
}

public struct MaskRequestIdentity: Codable, Hashable, Sendable {
  public let revision: MaskRevisionIdentity
  public let requestID: UUID

  public init(revision: MaskRevisionIdentity, requestID: UUID) {
    self.revision = revision
    self.requestID = requestID
  }
}

public struct MaskTargetIdentity: Codable, Hashable, Sendable {
  public let assetID: UUID
  public let maskID: UUID

  public init(assetID: UUID, maskID: UUID) {
    self.assetID = assetID
    self.maskID = maskID
  }
}

public struct MaskEditRequest: Codable, Hashable, Sendable {
  public let identity: MaskRequestIdentity
  public let edit: MaskGraphEditV1

  public init(identity: MaskRequestIdentity, edit: MaskGraphEditV1) {
    self.identity = identity
    self.edit = edit
  }
}

public struct MaskDuplicateRequest: Codable, Hashable, Sendable {
  public let identity: MaskRequestIdentity
  public let destination: MaskTargetIdentity

  public init?(identity: MaskRequestIdentity, destination: MaskTargetIdentity) {
    guard destination != identity.revision.targetIdentity else { return nil }
    self.identity = identity
    self.destination = destination
  }

  public init(from decoder: any Decoder) throws {
    let values = try PersistedMaskDuplicateRequest(from: decoder)
    guard let validated = Self(identity: values.identity, destination: values.destination) else {
      throw MaskValueValidation.corrupt(decoder, "Duplicate mask destination matches source")
    }
    self = validated
  }
}

public struct MaskSyncRequest: Codable, Hashable, Sendable {
  public let identity: MaskRequestIdentity
  public let destinations: [MaskTargetIdentity]

  public init?(identity: MaskRequestIdentity, destinations: [MaskTargetIdentity]) {
    guard
      !destinations.isEmpty,
      Set(destinations).count == destinations.count,
      !destinations.contains(identity.revision.targetIdentity)
    else { return nil }
    self.identity = identity
    self.destinations = destinations
  }

  public init(from decoder: any Decoder) throws {
    let values = try PersistedMaskSyncRequest(from: decoder)
    guard let validated = Self(identity: values.identity, destinations: values.destinations) else {
      throw MaskValueValidation.corrupt(decoder, "Invalid mask synchronization destinations")
    }
    self = validated
  }
}

public struct MaskGraphRecord: Codable, Hashable, Sendable {
  public let identity: MaskRevisionIdentity
  public let graph: MaskGraphV1

  public init(identity: MaskRevisionIdentity, graph: MaskGraphV1) {
    self.identity = identity
    self.graph = graph
  }
}

public struct MaskOperationResult: Codable, Hashable, Sendable {
  public let requestIdentity: MaskRequestIdentity
  public let records: [MaskGraphRecord]

  public init(requestIdentity: MaskRequestIdentity, records: [MaskGraphRecord]) {
    self.requestIdentity = requestIdentity
    self.records = records
  }
}

public protocol MaskService: Sendable {
  func apply(_ request: MaskEditRequest) async throws -> MaskOperationResult
  func duplicate(_ request: MaskDuplicateRequest) async throws -> MaskOperationResult
  func synchronize(_ request: MaskSyncRequest) async throws -> MaskOperationResult
}

extension MaskRevisionIdentity {
  fileprivate var targetIdentity: MaskTargetIdentity {
    MaskTargetIdentity(assetID: assetID, maskID: maskID)
  }
}

private struct PersistedMaskDuplicateRequest: Decodable {
  let identity: MaskRequestIdentity
  let destination: MaskTargetIdentity
}

private struct PersistedMaskSyncRequest: Decodable {
  let identity: MaskRequestIdentity
  let destinations: [MaskTargetIdentity]
}
