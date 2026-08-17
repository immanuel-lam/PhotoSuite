// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import PhotoWorkflow

/// User-editable settings for the three native professional output surfaces.
///
/// The draft is deliberately independent from the view. It normalises text and clamps numeric
/// values at the request boundary so a cancelled or interrupted panel cannot create an invalid
/// exporter request.
struct ProfessionalOutputDraft: Equatable, Sendable {
  var title: String
  var author = ""
  var pageSize: PhotoBookPageSize = .a4
  var secondsPerSlide = 4.0
  var framesPerSecond = 30
  var canvasWidth = 1_920
  var canvasHeight = 1_080
  var subtitle = ""
  var galleryMaximumDimension = 2_400
  var galleryMaximumDimensionEnabled = true

  init(tool: ProfessionalTool) {
    switch tool {
    case .book:
      title = "PhotoSuite Book"
    case .slideshow:
      title = "PhotoSuite Slideshow"
    case .webGallery:
      title = "PhotoSuite Gallery"
    default:
      title = "PhotoSuite Output"
    }
  }

  var normalizedTitle: String {
    let value = title.collapsedWhitespace
    return value.isEmpty ? "PhotoSuite Output" : value
  }

  var normalizedAuthor: String? {
    author.collapsedWhitespace.nilIfEmpty
  }

  var normalizedSubtitle: String? {
    subtitle.collapsedWhitespace.nilIfEmpty
  }

  var slideshowDuration: Double {
    guard secondsPerSlide.isFinite else { return 4 }
    return min(max(secondsPerSlide, 0.1), 3_600)
  }

  var slideshowFrameRate: Int {
    min(max(framesPerSecond, 1), 60)
  }

  var slideshowCanvas: PhotoSlideshowCanvas {
    PhotoSlideshowCanvas(
      width: min(max(canvasWidth, 1), 16_384),
      height: min(max(canvasHeight, 1), 16_384)
    )
  }

  var galleryMaximumPixelDimension: Int? {
    guard galleryMaximumDimensionEnabled else { return nil }
    return min(max(galleryMaximumDimension, 1), 32_768)
  }
}

extension String {
  fileprivate var collapsedWhitespace: String {
    split(whereSeparator: \.isWhitespace).joined(separator: " ")
  }

  fileprivate var nilIfEmpty: String? {
    isEmpty ? nil : self
  }
}
