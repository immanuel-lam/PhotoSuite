// SPDX-License-Identifier: MPL-2.0

import Foundation
import PhotoDomain
import XCTest

final class LibraryFolderTests: XCTestCase {
  func testFolderNormalizesDisplayNameAndComparisonName() throws {
    let folder = try XCTUnwrap(LibraryFolder(name: "  Café  "))
    XCTAssertEqual(folder.name, "Café")
    XCTAssertEqual(folder.normalizedName, "cafe")
    XCTAssertNil(LibraryFolder(id: folder.id, name: "Nested", parentID: folder.id))
  }

  func testFolderRoundTripsCodable() throws {
    let folder = try XCTUnwrap(
      LibraryFolder(
        id: UUID(uuidString: "11111111-2222-3333-4444-555555555555")!,
        name: "Sydney",
        parentID: UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!,
        createdAt: Date(timeIntervalSince1970: 10),
        updatedAt: Date(timeIntervalSince1970: 11)
      )
    )
    let data = try JSONEncoder().encode(folder)
    XCTAssertEqual(try JSONDecoder().decode(LibraryFolder.self, from: data), folder)
  }

  func testFolderRejectsEmptyAndOversizedNames() {
    XCTAssertNil(LibraryFolder(name: "   "))
    XCTAssertNil(LibraryFolder(name: String(repeating: "x", count: 256)))
  }
}
