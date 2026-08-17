// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Testing

@testable import PhotoSuite

struct MetadataEditorViewTests {
  @Test
  func optionalLocationAndRightsFieldsExposeStableAccessibilityContract() {
    #expect(MetadataEditorAccessibility.cityField == "metadata-city-field")
    #expect(MetadataEditorAccessibility.stateProvinceField == "metadata-state-province-field")
    #expect(MetadataEditorAccessibility.countryField == "metadata-country-field")
    #expect(MetadataEditorAccessibility.copyrightNoticeField == "metadata-copyright-field")
    #expect(MetadataEditorAccessibility.rightsUsageTermsField == "metadata-rights-field")

    #expect(MetadataEditorFieldLabel.city == "City")
    #expect(MetadataEditorFieldLabel.stateProvince == "State / Province")
    #expect(MetadataEditorFieldLabel.country == "Country")
    #expect(MetadataEditorFieldLabel.copyrightNotice == "Copyright notice")
    #expect(MetadataEditorFieldLabel.rightsUsageTerms == "Rights / usage terms")
  }
}
