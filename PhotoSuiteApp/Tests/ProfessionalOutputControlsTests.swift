// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import PhotoWorkflow
import Testing

@testable import PhotoSuite

struct ProfessionalOutputControlsTests {
  @Test
  func draftDefaultsMatchEachProfessionalOutput() {
    let book = ProfessionalOutputDraft(tool: .book)
    #expect(book.title == "PhotoSuite Book")
    #expect(book.pageSize == .a4)

    let slideshow = ProfessionalOutputDraft(tool: .slideshow)
    #expect(slideshow.title == "PhotoSuite Slideshow")
    #expect(slideshow.slideshowDuration == 4)
    #expect(slideshow.slideshowFrameRate == 30)
    #expect(slideshow.slideshowCanvas == PhotoSlideshowCanvas(width: 1_920, height: 1_080))

    let gallery = ProfessionalOutputDraft(tool: .webGallery)
    #expect(gallery.title == "PhotoSuite Gallery")
    #expect(gallery.galleryMaximumPixelDimension == 2_400)
  }

  @Test
  func draftNormalizesUserInputBeforeBuildingRequests() {
    var draft = ProfessionalOutputDraft(tool: .book)
    draft.title = "  A   Field   Book  "
    draft.author = "  Photo   Suite  "
    draft.secondsPerSlide = -2
    draft.framesPerSecond = 99
    draft.canvasWidth = 0
    draft.canvasHeight = 3_000

    #expect(draft.normalizedTitle == "A Field Book")
    #expect(draft.normalizedAuthor == "Photo Suite")
    #expect(draft.slideshowDuration == 0.1)
    #expect(draft.slideshowFrameRate == 60)
    #expect(draft.slideshowCanvas == PhotoSlideshowCanvas(width: 1, height: 3_000))
  }

  @Test
  func outputControlsExposeStableAccessibilityIdentifiers() {
    #expect(ModernUIAccessibility.professionalOutputSettings == "professional-output-settings")
    #expect(ModernUIAccessibility.professionalOutputTitle == "professional-output-title")
    #expect(ModernUIAccessibility.professionalOutputAuthor == "professional-output-author")
    #expect(ModernUIAccessibility.professionalOutputPageSize == "professional-output-page-size")
    #expect(ModernUIAccessibility.professionalOutputDuration == "professional-output-duration")
    #expect(ModernUIAccessibility.professionalOutputFrameRate == "professional-output-frame-rate")
    #expect(ModernUIAccessibility.professionalOutputCanvas == "professional-output-canvas")
    #expect(ModernUIAccessibility.professionalOutputSubtitle == "professional-output-subtitle")
    #expect(
      ModernUIAccessibility.professionalOutputMaximumDimension
        == "professional-output-maximum-dimension"
    )
    #expect(ModernUIAccessibility.professionalOutputStart == "professional-output-start")
    #expect(ModernUIAccessibility.professionalOutputCancel == "professional-output-cancel")
    #expect(ModernUIAccessibility.professionalOutputError == "professional-output-error")
    #expect(ModernUIAccessibility.professionalOutputResult == "professional-output-result")
  }
}
