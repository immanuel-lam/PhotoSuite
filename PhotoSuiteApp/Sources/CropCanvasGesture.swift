// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import CoreGraphics
import PhotoDomain
import PhotoWorkflow
import SwiftUI

extension ModernUIAccessibility {
  static let cropCanvasOverlay = "crop-canvas-overlay"
  static let cropCanvasToggle = "crop-canvas-toggle"
  static let cropCanvasApply = "crop-canvas-apply"
  static let cropCanvasCancel = "crop-canvas-cancel"
}

enum CropCanvasHandle: String, CaseIterable, Hashable, Identifiable, Sendable {
  case move
  case topLeading
  case top
  case topTrailing
  case leading
  case trailing
  case bottomLeading
  case bottom
  case bottomTrailing

  var id: Self { self }

  var title: String {
    switch self {
    case .move: "Move crop"
    case .topLeading: "Resize top left"
    case .top: "Resize top"
    case .topTrailing: "Resize top right"
    case .leading: "Resize left"
    case .trailing: "Resize right"
    case .bottomLeading: "Resize bottom left"
    case .bottom: "Resize bottom"
    case .bottomTrailing: "Resize bottom right"
    }
  }
}

/// Pure crop interaction math. Display-space drag translations are converted
/// into normalized image coordinates before a validated rectangle is returned.
/// The source image is never touched by this type; the workspace owns durable
/// recipe commits.
struct CropCanvasInteractionModel: Equatable, Sendable {
  var rect: NormalizedRect
  var aspectRatio: Double?

  init(rect: NormalizedRect? = nil, aspectRatio: Double? = nil) {
    self.rect = rect ?? NormalizedRect(x: 0, y: 0, width: 1, height: 1)!
    self.aspectRatio = Self.validAspectRatio(aspectRatio) ? aspectRatio : nil
  }

  mutating func setAspectRatio(_ ratio: Double?) {
    guard let ratio, Self.validAspectRatio(ratio) else {
      aspectRatio = nil
      return
    }

    aspectRatio = ratio
    let centerX = rect.x + rect.width / 2
    let centerY = rect.y + rect.height / 2
    var width = rect.width
    var height = width / ratio

    if height > rect.height {
      height = rect.height
      width = height * ratio
    }
    if width > 1 {
      width = 1
      height = width / ratio
    }
    if height > 1 {
      height = 1
      width = height * ratio
    }

    let x = min(max(centerX - width / 2, 0), max(0, 1 - width))
    let y = min(max(centerY - height / 2, 0), max(0, 1 - height))
    if let fitted = Self.makeRect(x: x, y: y, width: width, height: height) {
      rect = fitted
    }
  }

  func rect(
    after translation: CGSize,
    handle: CropCanvasHandle,
    in canvasSize: CGSize
  ) -> NormalizedRect? {
    guard canvasSize.width.isFinite, canvasSize.height.isFinite,
      canvasSize.width > 0, canvasSize.height > 0,
      translation.width.isFinite, translation.height.isFinite
    else { return nil }

    let delta = CGSize(
      width: translation.width / canvasSize.width,
      height: translation.height / canvasSize.height
    )

    if handle == .move {
      return Self.makeRect(
        x: clamped(rect.x + delta.width, lowerBound: 0, upperBound: 1 - rect.width),
        y: clamped(rect.y + delta.height, lowerBound: 0, upperBound: 1 - rect.height),
        width: rect.width,
        height: rect.height
      )
    }

    guard let aspectRatio, Self.validAspectRatio(aspectRatio) else {
      return freeResize(after: delta, handle: handle)
    }
    return lockedResize(after: delta, handle: handle, aspectRatio: aspectRatio)
  }

  static func normalizedPoint(_ point: CGPoint, in imageRect: CGRect) -> CGPoint? {
    guard imageRect.width > 0, imageRect.height > 0, imageRect.contains(point) else {
      return nil
    }
    return CGPoint(
      x: (point.x - imageRect.minX) / imageRect.width,
      y: (point.y - imageRect.minY) / imageRect.height
    )
  }

  static func imageRect(in bounds: CGRect, imageSize: PixelDimensions?) -> CGRect {
    guard bounds.width > 0, bounds.height > 0,
      let imageSize,
      imageSize.width > 0,
      imageSize.height > 0
    else { return bounds }

    let imageAspect = CGFloat(imageSize.width) / CGFloat(imageSize.height)
    let boundsAspect = bounds.width / bounds.height
    if imageAspect > boundsAspect {
      let height = bounds.width / imageAspect
      return CGRect(
        x: bounds.minX,
        y: bounds.midY - height / 2,
        width: bounds.width,
        height: height
      )
    }

    let width = bounds.height * imageAspect
    return CGRect(
      x: bounds.midX - width / 2,
      y: bounds.minY,
      width: width,
      height: bounds.height
    )
  }

  static func displayRect(for rect: NormalizedRect, in imageRect: CGRect) -> CGRect {
    CGRect(
      x: imageRect.minX + imageRect.width * rect.x,
      y: imageRect.minY + imageRect.height * rect.y,
      width: imageRect.width * rect.width,
      height: imageRect.height * rect.height
    )
  }

  private func freeResize(after delta: CGSize, handle: CropCanvasHandle) -> NormalizedRect? {
    var left = rect.x
    var top = rect.y
    var right = rect.x + rect.width
    var bottom = rect.y + rect.height
    let minimum = 0.01

    switch handle {
    case .topLeading:
      left = clamped(left + delta.width, lowerBound: 0, upperBound: right - minimum)
      top = clamped(top + delta.height, lowerBound: 0, upperBound: bottom - minimum)
    case .top:
      top = clamped(top + delta.height, lowerBound: 0, upperBound: bottom - minimum)
    case .topTrailing:
      right = clamped(right + delta.width, lowerBound: left + minimum, upperBound: 1)
      top = clamped(top + delta.height, lowerBound: 0, upperBound: bottom - minimum)
    case .leading:
      left = clamped(left + delta.width, lowerBound: 0, upperBound: right - minimum)
    case .trailing:
      right = clamped(right + delta.width, lowerBound: left + minimum, upperBound: 1)
    case .bottomLeading:
      left = clamped(left + delta.width, lowerBound: 0, upperBound: right - minimum)
      bottom = clamped(bottom + delta.height, lowerBound: top + minimum, upperBound: 1)
    case .bottom:
      bottom = clamped(bottom + delta.height, lowerBound: top + minimum, upperBound: 1)
    case .bottomTrailing:
      right = clamped(right + delta.width, lowerBound: left + minimum, upperBound: 1)
      bottom = clamped(bottom + delta.height, lowerBound: top + minimum, upperBound: 1)
    case .move:
      break
    }

    return Self.makeRect(x: left, y: top, width: right - left, height: bottom - top)
  }

  private func lockedResize(
    after delta: CGSize,
    handle: CropCanvasHandle,
    aspectRatio: Double
  ) -> NormalizedRect? {
    switch handle {
    case .topLeading, .topTrailing, .bottomLeading, .bottomTrailing:
      return lockedCornerResize(after: delta, handle: handle, aspectRatio: aspectRatio)
    case .top, .bottom:
      return lockedVerticalEdgeResize(after: delta, handle: handle, aspectRatio: aspectRatio)
    case .leading, .trailing:
      return lockedHorizontalEdgeResize(after: delta, handle: handle, aspectRatio: aspectRatio)
    case .move:
      return rect
    }
  }

  private func lockedCornerResize(
    after delta: CGSize,
    handle: CropCanvasHandle,
    aspectRatio: Double
  ) -> NormalizedRect? {
    let startLeft = rect.x
    let startTop = rect.y
    let startRight = rect.x + rect.width
    let startBottom = rect.y + rect.height

    let anchor: CGPoint
    let target: CGPoint
    switch handle {
    case .topLeading:
      anchor = CGPoint(x: startRight, y: startBottom)
      target = CGPoint(x: startLeft + delta.width, y: startTop + delta.height)
    case .topTrailing:
      anchor = CGPoint(x: startLeft, y: startBottom)
      target = CGPoint(x: startRight + delta.width, y: startTop + delta.height)
    case .bottomLeading:
      anchor = CGPoint(x: startRight, y: startTop)
      target = CGPoint(x: startLeft + delta.width, y: startBottom + delta.height)
    case .bottomTrailing:
      anchor = CGPoint(x: startLeft, y: startTop)
      target = CGPoint(x: startRight + delta.width, y: startBottom + delta.height)
    default:
      return nil
    }

    let candidateWidth = abs(target.x - anchor.x)
    let candidateHeight = abs(target.y - anchor.y)
    let widthDriven = candidateHeight <= 0 || candidateWidth / candidateHeight >= aspectRatio
    let maxWidth = anchor.x <= target.x ? 1 - anchor.x : anchor.x
    let maxHeight = anchor.y <= target.y ? 1 - anchor.y : anchor.y
    let minimum = 0.01

    var width: Double
    var height: Double
    if widthDriven {
      width = min(max(candidateWidth, minimum), min(maxWidth, maxHeight * aspectRatio))
      height = width / aspectRatio
    } else {
      height = min(max(candidateHeight, minimum), min(maxHeight, maxWidth / aspectRatio))
      width = height * aspectRatio
    }

    let x = anchor.x <= target.x ? anchor.x : anchor.x - width
    let y = anchor.y <= target.y ? anchor.y : anchor.y - height
    return Self.makeRect(x: x, y: y, width: width, height: height)
  }

  private func lockedVerticalEdgeResize(
    after delta: CGSize,
    handle: CropCanvasHandle,
    aspectRatio: Double
  ) -> NormalizedRect? {
    let centerX = rect.x + rect.width / 2
    let minimum = 0.01
    let height: Double
    let y: Double
    if handle == .top {
      let bottom = rect.y + rect.height
      height = min(max(rect.height - delta.height, minimum), min(bottom, 1) * 2)
      y = bottom - height
    } else {
      height = min(max(rect.height + delta.height, minimum), 1 - rect.y)
      y = rect.y
    }
    let width = min(height * aspectRatio, 1)
    let x = clamped(centerX - width / 2, lowerBound: 0, upperBound: 1 - width)
    return Self.makeRect(x: x, y: y, width: width, height: height)
  }

  private func lockedHorizontalEdgeResize(
    after delta: CGSize,
    handle: CropCanvasHandle,
    aspectRatio: Double
  ) -> NormalizedRect? {
    let centerY = rect.y + rect.height / 2
    let minimum = 0.01
    let width: Double
    let x: Double
    if handle == .leading {
      let right = rect.x + rect.width
      width = min(max(rect.width - delta.width, minimum), min(right, 1) * 2)
      x = right - width
    } else {
      width = min(max(rect.width + delta.width, minimum), 1 - rect.x)
      x = rect.x
    }
    let height = min(width / aspectRatio, 1)
    let y = clamped(centerY - height / 2, lowerBound: 0, upperBound: 1 - height)
    return Self.makeRect(x: x, y: y, width: width, height: height)
  }

  private static func validAspectRatio(_ ratio: Double?) -> Bool {
    guard let ratio else { return false }
    return ratio.isFinite && ratio > 0
  }

  private static func makeRect(
    x: Double,
    y: Double,
    width: Double,
    height: Double
  ) -> NormalizedRect? {
    NormalizedRect(
      x: max(0, min(x, 1)),
      y: max(0, min(y, 1)),
      width: max(0, min(width, 1)),
      height: max(0, min(height, 1))
    )
  }

  private func clamped(_ value: Double, lowerBound: Double, upperBound: Double) -> Double {
    min(max(value, lowerBound), max(lowerBound, upperBound))
  }
}

@MainActor
struct CropCanvasOverlay: View {
  @Bindable var workspace: PhotoWorkspace
  @Binding var isEditing: Bool
  let previewDimensions: PixelDimensions?
  @State private var model: CropCanvasInteractionModel
  @State private var aspectPreset: CropAspectPreset = .free
  @State private var activeHandle: CropCanvasHandle?
  @State private var dragStartRect: NormalizedRect?

  init(
    workspace: PhotoWorkspace,
    isEditing: Binding<Bool>,
    previewDimensions: PixelDimensions?
  ) {
    self.workspace = workspace
    self._isEditing = isEditing
    self.previewDimensions = previewDimensions
    self._model = State(
      initialValue: CropCanvasInteractionModel(rect: Self.currentCrop(in: workspace.currentRecipe))
    )
  }

  var body: some View {
    GeometryReader { proxy in
      let imageRect = CropCanvasInteractionModel.imageRect(
        in: CGRect(origin: .zero, size: proxy.size),
        imageSize: previewDimensions
      )
      let displayRect = CropCanvasInteractionModel.displayRect(for: model.rect, in: imageRect)

      ZStack {
        Path { path in
          path.addRect(CGRect(origin: .zero, size: proxy.size))
          path.addRect(displayRect)
        }
        .fill(.black.opacity(0.58), style: FillStyle(eoFill: true))
        .allowsHitTesting(false)

        cropFrame(displayRect: displayRect)
          .gesture(moveGesture(imageRect: imageRect))

        ForEach(CropCanvasHandle.allCases.filter { $0 != .move }) { handle in
          handleView(handle, displayRect: displayRect)
            .gesture(resizeGesture(handle: handle, imageRect: imageRect))
        }

        VStack {
          Spacer()
          GlassControlGroup {
            HStack(spacing: 8) {
              Menu {
                ForEach(CropAspectPreset.allCases) { preset in
                  Button(preset.title) { apply(preset) }
                }
              } label: {
                Label("Aspect \(aspectPreset.title)", systemImage: "rectangle.ratio.3.to.4")
              }
              .accessibilityIdentifier("crop-canvas-aspect-menu")

              Button {
                apply(.original)
              } label: {
                Label("Reset", systemImage: "arrow.counterclockwise")
              }

              Button {
                let rect = model.rect
                isEditing = false
                Task { await workspace.commitCrop(rect) }
              } label: {
                Label("Apply", systemImage: "checkmark")
              }
              .modifier(GlassButtonWhenAvailable(prominent: true))
              .accessibilityIdentifier(ModernUIAccessibility.cropCanvasApply)

              Button {
                isEditing = false
              } label: {
                Label("Cancel", systemImage: "xmark")
              }
              .accessibilityIdentifier(ModernUIAccessibility.cropCanvasCancel)
            }
          }
          .padding(.bottom, 24)
        }
      }
      .accessibilityIdentifier(ModernUIAccessibility.cropCanvasOverlay)
      .onChange(of: workspace.currentRecipe?.revision) { _, _ in
        guard activeHandle == nil else { return }
        model.rect =
          Self.currentCrop(in: workspace.currentRecipe)
          ?? NormalizedRect(x: 0, y: 0, width: 1, height: 1)!
      }
      .onChange(of: workspace.selectedAssetID) { _, _ in
        model.rect =
          Self.currentCrop(in: workspace.currentRecipe)
          ?? NormalizedRect(x: 0, y: 0, width: 1, height: 1)!
        aspectPreset = .free
      }
    }
    .allowsHitTesting(isEditing)
  }

  @ViewBuilder
  private func cropFrame(displayRect: CGRect) -> some View {
    ZStack {
      Rectangle()
        .stroke(.white, lineWidth: 1.5)
        .frame(width: displayRect.width, height: displayRect.height)

      Path { path in
        for fraction in [1.0 / 3.0, 2.0 / 3.0] {
          let x = displayRect.minX + displayRect.width * fraction
          path.move(to: CGPoint(x: x, y: displayRect.minY))
          path.addLine(to: CGPoint(x: x, y: displayRect.maxY))
          let y = displayRect.minY + displayRect.height * fraction
          path.move(to: CGPoint(x: displayRect.minX, y: y))
          path.addLine(to: CGPoint(x: displayRect.maxX, y: y))
        }
      }
      .stroke(.white.opacity(0.68), lineWidth: 0.75)
    }
    .frame(width: displayRect.width, height: displayRect.height)
    .position(x: displayRect.midX, y: displayRect.midY)
    .contentShape(Rectangle())
    .accessibilityElement()
    .accessibilityLabel("Crop rectangle")
    .accessibilityValue(
      "\(model.rect.width.formatted(.number.precision(.fractionLength(2)))) by "
        + "\(model.rect.height.formatted(.number.precision(.fractionLength(2))))"
    )
  }

  private func handleView(_ handle: CropCanvasHandle, displayRect: CGRect) -> some View {
    let point = handlePoint(handle, in: displayRect)
    return RoundedRectangle(cornerRadius: 2, style: .continuous)
      .fill(.white)
      .frame(width: handle.isCorner ? 12 : 8, height: handle.isCorner ? 12 : 8)
      .shadow(color: .black.opacity(0.45), radius: 2)
      .position(point)
      .accessibilityElement()
      .accessibilityLabel(handle.title)
      .accessibilityIdentifier("crop-canvas-handle-\(handle.rawValue)")
  }

  private func moveGesture(imageRect: CGRect) -> some Gesture {
    DragGesture(minimumDistance: 1)
      .onChanged { value in
        update(handle: .move, translation: value.translation, canvasSize: imageRect.size)
      }
      .onEnded { _ in endDrag() }
  }

  private func resizeGesture(handle: CropCanvasHandle, imageRect: CGRect) -> some Gesture {
    DragGesture(minimumDistance: 1)
      .onChanged { value in
        update(handle: handle, translation: value.translation, canvasSize: imageRect.size)
      }
      .onEnded { _ in endDrag() }
  }

  private func update(handle: CropCanvasHandle, translation: CGSize, canvasSize: CGSize) {
    if activeHandle != handle {
      activeHandle = handle
      dragStartRect = model.rect
    }
    guard let dragStartRect else { return }
    let startingModel = CropCanvasInteractionModel(
      rect: dragStartRect,
      aspectRatio: model.aspectRatio
    )
    if let next = startingModel.rect(after: translation, handle: handle, in: canvasSize) {
      model.rect = next
    }
  }

  private func endDrag() {
    activeHandle = nil
    dragStartRect = nil
  }

  private func apply(_ preset: CropAspectPreset) {
    aspectPreset = preset
    if preset == .original {
      model.rect = NormalizedRect(x: 0, y: 0, width: 1, height: 1)!
      model.aspectRatio = nil
      return
    }

    guard let ratio = preset.ratio else {
      model.aspectRatio = nil
      return
    }
    let imageAspect = previewDimensions.map { Double($0.width) / Double($0.height) } ?? 1
    model.setAspectRatio(ratio / imageAspect)
  }

  private func handlePoint(_ handle: CropCanvasHandle, in rect: CGRect) -> CGPoint {
    switch handle {
    case .topLeading: CGPoint(x: rect.minX, y: rect.minY)
    case .top: CGPoint(x: rect.midX, y: rect.minY)
    case .topTrailing: CGPoint(x: rect.maxX, y: rect.minY)
    case .leading: CGPoint(x: rect.minX, y: rect.midY)
    case .trailing: CGPoint(x: rect.maxX, y: rect.midY)
    case .bottomLeading: CGPoint(x: rect.minX, y: rect.maxY)
    case .bottom: CGPoint(x: rect.midX, y: rect.maxY)
    case .bottomTrailing: CGPoint(x: rect.maxX, y: rect.maxY)
    case .move: rect.center
    }
  }

  private static func currentCrop(in recipe: EditRecipe?) -> NormalizedRect? {
    recipe?.operations.reversed().compactMap { operation in
      if case .normalizedCrop(let rect) = operation { return rect }
      return nil
    }.first
  }
}

extension CropCanvasHandle {
  fileprivate var isCorner: Bool {
    switch self {
    case .topLeading, .topTrailing, .bottomLeading, .bottomTrailing: true
    default: false
    }
  }
}

extension CGRect {
  fileprivate var center: CGPoint { CGPoint(x: midX, y: midY) }
}
