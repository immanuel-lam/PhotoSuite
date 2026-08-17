// SPDX-License-Identifier: MPL-2.0

import Foundation
import PhotoDomain

/// Semantic mask families that are not implemented by the built-in
/// foreground/subject/person provider.
///
/// This type is deliberately separate from `VisionAIMaskKind`. The existing
/// provider only advertises operations that it can execute with a system
/// Vision request. These values are capability requests for future local
/// model packs, not claims that macOS Vision already provides these masks.
public enum VisionSemanticMaskKind: String, Codable, CaseIterable, Hashable, Sendable, Identifiable
{
  case sky
  case object
  case background
  case landscape
  case depth

  public var id: String { rawValue }

  public var displayName: String {
    switch self {
    case .sky: "Sky"
    case .object: "Object"
    case .background: "Background"
    case .landscape: "Landscape"
    case .depth: "Depth"
    }
  }

  public var modelIdentifier: String {
    "com.photosuite.semantic-mask.\(rawValue)"
  }
}

/// The current implementation boundary for a semantic mask family.
public enum VisionSemanticMaskCapabilityStatus: String, Codable, CaseIterable, Hashable, Sendable {
  /// A future implementation may use a native Vision request for this kind.
  case nativeSystem

  /// The built-in system request is not sufficient, but an optional local
  /// model pack may provide the required semantic output.
  case requiresOptionalModelPack

  /// No supported macOS Vision request exists for this semantic mask family.
  case unavailableNativeAPI
}

public struct VisionSemanticMaskCapability: Codable, Hashable, Sendable {
  public let kind: VisionSemanticMaskKind
  public let status: VisionSemanticMaskCapabilityStatus
  public let providerIdentifier: String
  public let providerVersion: String
  public let reason: String

  public init(
    kind: VisionSemanticMaskKind,
    status: VisionSemanticMaskCapabilityStatus,
    providerIdentifier: String = VisionSemanticMaskService.providerIdentifier,
    providerVersion: String = VisionSemanticMaskService.providerVersion,
    reason: String
  ) {
    self.kind = kind
    self.status = status
    self.providerIdentifier = providerIdentifier
    self.providerVersion = providerVersion
    self.reason = reason
  }

  public var isAvailable: Bool {
    status == .nativeSystem
  }
}

/// A request for a semantic mask that is currently outside the built-in
/// Vision provider boundary. The image is retained so a future model-pack
/// provider can adopt the same request without changing the recipe contract.
public struct VisionSemanticMaskRequest: Codable, Hashable, Sendable {
  public let identity: MaskRequestIdentity
  public let image: ImageBuffer
  public let kind: VisionSemanticMaskKind
  public let modelIdentifier: String
  public let modelVersion: String

  public init(
    identity: MaskRequestIdentity,
    image: ImageBuffer,
    kind: VisionSemanticMaskKind,
    modelIdentifier: String? = nil,
    modelVersion: String = VisionSemanticMaskService.providerVersion
  ) {
    self.identity = identity
    self.image = image
    self.kind = kind
    self.modelIdentifier = modelIdentifier ?? kind.modelIdentifier
    self.modelVersion = modelVersion
  }
}

public enum VisionSemanticMaskResultStatus: String, Codable, CaseIterable, Hashable, Sendable {
  /// A capability-aware provider accepted the request but deliberately left
  /// the recipe unchanged because the optional model pack is not installed.
  case noOp

  /// The request cannot run with the current native API boundary.
  case unavailable

  /// Reserved for a future provider that returns a durable mask.
  case applied
}

/// A stable, non-throwing result for semantic mask capability requests.
///
/// Unsupported semantic masks are expected capability states, not processing
/// failures. Returning a result with no mask lets callers keep the current
/// recipe unchanged and present a precise explanation to the user.
public struct VisionSemanticMaskResult: Codable, Hashable, Sendable {
  public let identity: MaskRequestIdentity
  public let kind: VisionSemanticMaskKind
  public let modelIdentifier: String
  public let modelVersion: String
  public let status: VisionSemanticMaskResultStatus
  public let capability: VisionSemanticMaskCapability
  public let mask: MaskDefinition?

  public init(
    identity: MaskRequestIdentity,
    kind: VisionSemanticMaskKind,
    modelIdentifier: String? = nil,
    modelVersion: String? = nil,
    status: VisionSemanticMaskResultStatus,
    capability: VisionSemanticMaskCapability,
    mask: MaskDefinition? = nil
  ) {
    self.identity = identity
    self.kind = kind
    self.modelIdentifier = modelIdentifier ?? kind.modelIdentifier
    self.modelVersion = modelVersion ?? capability.providerVersion
    self.status = status
    self.capability = capability
    self.mask = mask
  }

  public var applied: Bool {
    status == .applied && mask != nil
  }

  public static func noOp(
    identity: MaskRequestIdentity,
    kind: VisionSemanticMaskKind,
    capability: VisionSemanticMaskCapability,
    modelIdentifier: String? = nil,
    modelVersion: String? = nil
  ) -> Self {
    Self(
      identity: identity,
      kind: kind,
      modelIdentifier: modelIdentifier,
      modelVersion: modelVersion,
      status: .noOp,
      capability: capability
    )
  }

  public static func unavailable(
    identity: MaskRequestIdentity,
    kind: VisionSemanticMaskKind,
    capability: VisionSemanticMaskCapability,
    modelIdentifier: String? = nil,
    modelVersion: String? = nil
  ) -> Self {
    Self(
      identity: identity,
      kind: kind,
      modelIdentifier: modelIdentifier,
      modelVersion: modelVersion,
      status: .unavailable,
      capability: capability
    )
  }
}

/// Reports the native Vision boundary without attempting unsupported
/// semantic segmentation. It performs no network access and no model-pack
/// discovery.
public actor VisionSemanticMaskService {
  public static let providerIdentifier = "com.photosuite.vision-semantic-capabilities"
  public static let providerVersion = "1"

  public static let capabilities: [VisionSemanticMaskCapability] = [
    VisionSemanticMaskCapability(
      kind: .sky,
      status: .unavailableNativeAPI,
      reason:
        "macOS system Vision has no supported sky-segmentation request. An optional local model pack is required."
    ),
    VisionSemanticMaskCapability(
      kind: .object,
      status: .requiresOptionalModelPack,
      reason:
        "VNGenerateForegroundInstanceMaskRequest does not provide target-aware object semantics. An optional local model pack is required."
    ),
    VisionSemanticMaskCapability(
      kind: .background,
      status: .unavailableNativeAPI,
      reason:
        "macOS system Vision has no supported generic background-segmentation request. An optional local model pack is required."
    ),
    VisionSemanticMaskCapability(
      kind: .landscape,
      status: .unavailableNativeAPI,
      reason:
        "macOS system Vision has no supported landscape-part segmentation request. An optional local model pack is required."
    ),
    VisionSemanticMaskCapability(
      kind: .depth,
      status: .unavailableNativeAPI,
      reason:
        "macOS system Vision has no supported generic depth-mask request. An optional local model pack is required."
    ),
  ]

  public init() {}

  public static func capability(for kind: VisionSemanticMaskKind) -> VisionSemanticMaskCapability {
    // The static catalog is closed over the enum's CaseIterable values. The
    // precondition makes an accidental catalog omission fail during
    // development instead of silently reporting the wrong capability.
    guard let capability = capabilities.first(where: { $0.kind == kind }) else {
      preconditionFailure("No semantic-mask capability is registered for \(kind.rawValue).")
    }
    return capability
  }

  public func generateMask(_ request: VisionSemanticMaskRequest) async -> VisionSemanticMaskResult {
    let capability = Self.capability(for: request.kind)
    switch capability.status {
    case .nativeSystem, .unavailableNativeAPI:
      return .unavailable(
        identity: request.identity,
        kind: request.kind,
        capability: capability,
        modelIdentifier: request.modelIdentifier,
        modelVersion: request.modelVersion
      )
    case .requiresOptionalModelPack:
      return .noOp(
        identity: request.identity,
        kind: request.kind,
        capability: capability,
        modelIdentifier: request.modelIdentifier,
        modelVersion: request.modelVersion
      )
    }
  }
}

extension MaskResultGate {
  /// Identity gate for a capability result, including no-op and unavailable
  /// responses. A late capability response must not be applied to a new edit.
  public static func accepts(
    _ result: VisionSemanticMaskResult,
    for currentIdentity: MaskRequestIdentity
  ) -> Bool {
    result.identity == currentIdentity
  }
}
