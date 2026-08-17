// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import CoreGraphics
import ImageIO
import Metal
import MetalKit
import PhotoWorkflow
import QuartzCore
import SwiftUI

@MainActor
struct MetalPreviewCanvas: NSViewRepresentable {
  let frame: PreviewFrame?

  func makeCoordinator() -> Coordinator { Coordinator() }

  func makeNSView(context: Context) -> MTKView {
    let view = MTKView(frame: .zero, device: context.coordinator.device)
    view.wantsLayer = true
    view.framebufferOnly = false
    view.colorPixelFormat = .rgba16Float
    view.colorspace = CGColorSpace(name: CGColorSpace.extendedLinearDisplayP3)
    view.autoResizeDrawable = true
    view.enableSetNeedsDisplay = true
    view.isPaused = true
    view.clearColor = MTLClearColor(red: 0.18, green: 0.18, blue: 0.18, alpha: 1)
    view.delegate = context.coordinator
    if #available(macOS 26.0, *) {
      view.layer?.preferredDynamicRange = .high
    } else {
      view.layer?.wantsExtendedDynamicRangeContent = true
    }
    context.coordinator.configure(for: view)
    return view
  }

  func updateNSView(_ view: MTKView, context: Context) {
    context.coordinator.update(frame: frame)
    view.setNeedsDisplay(view.bounds)
  }

  final class Coordinator: NSObject, MTKViewDelegate {
    let device: any MTLDevice
    private let commandQueue: any MTLCommandQueue
    private var pipeline: (any MTLRenderPipelineState)?
    private var texture: (any MTLTexture)?
    private var lastImageData: Data?
    private var imageSize = SIMD2<Float>(1, 1)

    override init() {
      guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue()
      else {
        fatalError("PhotoSuite requires a Metal device.")
      }
      self.device = device
      self.commandQueue = queue
      super.init()
    }

    @MainActor
    func configure(for view: MTKView) {
      guard
        let library = device.makeDefaultLibrary(),
        let vertex = library.makeFunction(name: "photoPreviewVertex"),
        let fragment = library.makeFunction(name: "photoPreviewFragment")
      else { return }
      let descriptor = MTLRenderPipelineDescriptor()
      descriptor.vertexFunction = vertex
      descriptor.fragmentFunction = fragment
      descriptor.colorAttachments[0].pixelFormat = view.colorPixelFormat
      pipeline = try? device.makeRenderPipelineState(descriptor: descriptor)
    }

    func update(frame: PreviewFrame?) {
      guard frame?.imageData != lastImageData else { return }
      lastImageData = frame?.imageData
      texture = nil
      guard
        let data = frame?.imageData as CFData?,
        let source = CGImageSourceCreateWithData(data, nil),
        let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
      else { return }
      imageSize = SIMD2(Float(image.width), Float(image.height))
      texture = try? MTKTextureLoader(device: device).newTexture(
        cgImage: image,
        options: [.origin: MTKTextureLoader.Origin.topLeft, .SRGB: false]
      )
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
      view.setNeedsDisplay(view.bounds)
    }

    func draw(in view: MTKView) {
      guard
        let descriptor = view.currentRenderPassDescriptor,
        let drawable = view.currentDrawable,
        let commandBuffer = commandQueue.makeCommandBuffer(),
        let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor)
      else { return }

      if let pipeline, let texture {
        let vertices = aspectFitVertices(drawableSize: view.drawableSize)
        encoder.setRenderPipelineState(pipeline)
        encoder.setVertexBytes(
          vertices,
          length: MemoryLayout<PreviewVertex>.stride * vertices.count,
          index: 0
        )
        encoder.setFragmentTexture(texture, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: vertices.count)
      }
      encoder.endEncoding()
      commandBuffer.present(drawable)
      commandBuffer.commit()
    }

    private func aspectFitVertices(drawableSize: CGSize) -> [PreviewVertex] {
      let viewAspect = Float(drawableSize.width / max(drawableSize.height, 1))
      let imageAspect = imageSize.x / max(imageSize.y, 1)
      let scaleX = imageAspect > viewAspect ? 1 : imageAspect / viewAspect
      let scaleY = imageAspect > viewAspect ? viewAspect / imageAspect : 1
      return [
        PreviewVertex(position: [-scaleX, -scaleY], textureCoordinate: [0, 1]),
        PreviewVertex(position: [scaleX, -scaleY], textureCoordinate: [1, 1]),
        PreviewVertex(position: [-scaleX, scaleY], textureCoordinate: [0, 0]),
        PreviewVertex(position: [-scaleX, scaleY], textureCoordinate: [0, 0]),
        PreviewVertex(position: [scaleX, -scaleY], textureCoordinate: [1, 1]),
        PreviewVertex(position: [scaleX, scaleY], textureCoordinate: [1, 0]),
      ]
    }
  }
}

private struct PreviewVertex {
  let position: SIMD2<Float>
  let textureCoordinate: SIMD2<Float>
}
