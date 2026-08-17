// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import PhotoDomain

enum MaskAuthoringAvailability: String, Codable, Hashable, Sendable {
  case available
  case unavailable

  var isAvailable: Bool { self == .available }
}

enum MaskAuthoringTool: String, CaseIterable, Hashable, Identifiable, Sendable {
  case brush
  case linearGradient
  case radialGradient
  case colorRange
  case luminanceRange
  case depthRange
  case subject
  case sky
  case background
  case object

  var id: String { rawValue }

  static var manualTools: [Self] {
    [.brush, .linearGradient, .radialGradient, .colorRange, .luminanceRange, .depthRange]
  }

  static var smartTools: [Self] {
    [.subject, .sky, .background, .object]
  }

  var kind: MaskKind {
    switch self {
    case .brush: .brush
    case .linearGradient: .linearGradient
    case .radialGradient: .radialGradient
    case .colorRange: .colorRange
    case .luminanceRange: .luminanceRange
    case .depthRange: .depthRange
    case .subject: .subject
    case .sky: .sky
    case .background: .background
    case .object: .object
    }
  }

  var title: String {
    switch self {
    case .brush: "Brush"
    case .linearGradient: "Linear"
    case .radialGradient: "Radial"
    case .colorRange: "Colour"
    case .luminanceRange: "Luminance"
    case .depthRange: "Depth"
    case .subject: "Subject"
    case .sky: "Sky"
    case .background: "Background"
    case .object: "Object"
    }
  }

  var subtitle: String {
    switch self {
    case .brush: "Paint"
    case .linearGradient: "Fade"
    case .radialGradient: "Spotlight"
    case .colorRange: "Sample colour"
    case .luminanceRange: "Brightness"
    case .depthRange: "Depth map"
    case .subject, .sky, .background, .object: "Smart selection"
    }
  }

  var systemImage: String {
    switch self {
    case .brush: "paintbrush.pointed"
    case .linearGradient: "rectangle.lefthalf.inset.filled"
    case .radialGradient: "circle.dashed"
    case .colorRange: "eyedropper"
    case .luminanceRange: "sun.max"
    case .depthRange: "square.3.layers.3d"
    case .subject: "person.crop.rectangle"
    case .sky: "cloud.sun"
    case .background: "photo.on.rectangle"
    case .object: "cube"
    }
  }

  var availability: MaskAuthoringAvailability {
    switch self {
    case .depthRange, .subject, .sky, .background, .object: .unavailable
    case .brush, .linearGradient, .radialGradient, .colorRange, .luminanceRange: .available
    }
  }

  var unavailableReason: String? {
    switch self {
    case .depthRange:
      "Depth range needs a depth map. The current image contract does not provide one."
    case .subject:
      "Subject selection needs a local model result. It is not inferred by this inspector."
    case .sky:
      "Sky selection needs an optional local model pack. No model is installed."
    case .background:
      "Background selection needs an optional local model pack. No model is installed."
    case .object:
      "Object selection needs an optional local model pack. No model is installed."
    default: nil
    }
  }
}

enum MaskAuthoringModel {
  static func makeMask(
    kind: MaskKind,
    operation: MaskCombinationOperation,
    id: UUID = UUID()
  ) -> MaskDefinition? {
    guard isAvailable(kind) else { return nil }
    guard let primitive = primitive(for: kind) else { return nil }
    let graph = MaskGraphV1(
      components: [
        MaskGraphComponentV1(id: id, operation: operation, primitive: primitive)
      ]
    )
    return try? MaskDefinition(id: id, kind: kind, name: title(for: kind), graph: graph)
  }

  static func append(
    to mask: MaskDefinition,
    kind: MaskKind,
    operation: MaskCombinationOperation,
    componentID: UUID = UUID()
  ) -> MaskDefinition? {
    guard let primitive = primitive(for: kind), let graph = graph(from: mask) else {
      return nil
    }
    let updatedGraph = graph.applying(.add(id: componentID, primitive: primitive))
      .replacingLastOperation(operation, componentID: componentID)
    return try? MaskDefinition(
      id: mask.id,
      kind: mask.kind,
      name: mask.name,
      graph: updatedGraph
    )
  }

  static func inverted(_ mask: MaskDefinition) -> MaskDefinition? {
    guard let graph = graph(from: mask) else { return nil }
    return try? MaskDefinition(
      id: mask.id,
      kind: mask.kind,
      name: mask.name,
      graph: graph.applying(.invert)
    )
  }

  static func graph(from mask: MaskDefinition) -> MaskGraphV1? {
    guard case .version1(let graph) = try? mask.decodeGraphPayload() else { return nil }
    return graph
  }

  private static func primitive(for kind: MaskKind) -> MaskPrimitiveV1? {
    switch kind {
    case .brush:
      guard
        let point = MaskPointV1(x: 0.5, y: 0.5),
        let sample = MaskBrushSampleV1(point: point, pressure: 1),
        let brush = BrushMaskV1(samples: [sample], radius: 0.2, feather: 0.5, flow: 1)
      else { return nil }
      return .brush(brush)
    case .linearGradient:
      guard
        let start = MaskPointV1(x: 0.5, y: 0.1),
        let end = MaskPointV1(x: 0.5, y: 0.9),
        let gradient = LinearGradientMaskV1(start: start, end: end, feather: 0.5)
      else { return nil }
      return .linearGradient(gradient)
    case .radialGradient:
      guard
        let center = MaskPointV1(x: 0.5, y: 0.5),
        let gradient = RadialGradientMaskV1(
          center: center,
          radiusX: 0.3,
          radiusY: 0.3,
          rotationDegrees: 0,
          feather: 0.5
        )
      else { return nil }
      return .radialGradient(gradient)
    case .colorRange:
      guard
        let sample = MaskColorSampleV1(red: 0.5, green: 0.5, blue: 0.5),
        let range = ColorRangeMaskV1(samples: [sample], tolerance: 0.2, feather: 0.5)
      else { return nil }
      return .colorRange(range)
    case .luminanceRange:
      guard let range = LuminanceRangeMaskV1(lowerBound: 0.25, upperBound: 0.75, feather: 0.2)
      else { return nil }
      return .luminanceRange(range)
    case .depthRange:
      guard let range = DepthRangeMaskV1(nearBound: 0.25, farBound: 0.75, feather: 0.2)
      else { return nil }
      return .depthRange(range)
    case .subject, .sky, .background, .object, .unknown:
      return nil
    }
  }

  private static func isAvailable(_ kind: MaskKind) -> Bool {
    switch kind {
    case .brush, .linearGradient, .radialGradient, .colorRange, .luminanceRange: true
    case .depthRange, .subject, .sky, .background, .object, .unknown: false
    }
  }

  private static func title(for kind: MaskKind) -> String {
    switch kind {
    case .brush: "Brush"
    case .linearGradient: "Linear gradient"
    case .radialGradient: "Radial gradient"
    case .colorRange: "Colour range"
    case .luminanceRange: "Luminance range"
    case .depthRange: "Depth range"
    case .subject: "Subject"
    case .sky: "Sky"
    case .background: "Background"
    case .object: "Object"
    case .unknown(let value): value
    }
  }
}

extension MaskGraphV1 {
  fileprivate func replacingLastOperation(
    _ operation: MaskCombinationOperation,
    componentID: UUID
  ) -> Self {
    var updated = components
    guard let index = updated.lastIndex(where: { $0.id == componentID }) else { return self }
    let component = updated[index]
    updated[index] = MaskGraphComponentV1(
      id: component.id,
      operation: operation,
      primitive: component.primitive
    )
    return Self(components: updated, isInverted: isInverted)
  }
}
