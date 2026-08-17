// SPDX-License-Identifier: MPL-2.0

import Foundation
import XCTest

@testable import PhotoDomain

final class AIModelPackTests: XCTestCase {
  func testDefaultModelCardsHavePermittedLicencesAndStableChecksums() throws {
    let cards = AIModelCatalog.defaultCards

    XCTAssertFalse(cards.isEmpty)
    for card in cards {
      XCTAssertTrue(card.license == .apache2 || card.license == .ccBy4)
      XCTAssertEqual(card.sha256.count, 64)
      XCTAssertTrue(card.sha256.allSatisfy { $0.isHexDigit })
      XCTAssertFalse(card.provenanceURL.absoluteString.isEmpty)
      XCTAssertGreaterThan(card.minimumMemoryMB, 0)
    }
  }

  func testRegistryRejectsNetworkOnlyOrUnverifiedPacks() throws {
    let registry = LocalAIModelRegistry(cards: AIModelCatalog.defaultCards)
    let card = try XCTUnwrap(AIModelCatalog.defaultCards.first)

    XCTAssertTrue(registry.isAvailable(card.id, installed: false) == false)
    XCTAssertThrowsError(
      try registry.validateInstallation(
        cardID: card.id,
        sha256: String(repeating: "0", count: 64),
        hasModelCard: false
      )
    ) { error in
      XCTAssertEqual(error as? AIModelPackError, .unverifiedPack)
    }
  }

  func testModelRequestCarriesRevisionAndRequestIdentityForStaleResultSuppression() throws {
    let requestID = UUID()
    let assetID = UUID()
    let request = AIModelExecutionRequest(
      requestID: requestID,
      assetID: assetID,
      recipeRevision: 12,
      modelID: "photosuite.subject.default",
      modelVersion: "1.0.0"
    )
    let result = AIModelExecutionResult(
      requestID: requestID,
      assetID: assetID,
      recipeRevision: 12,
      modelID: request.modelID,
      modelVersion: request.modelVersion,
      output: Data([1, 2, 3])
    )

    XCTAssertTrue(request.accepts(result))
    XCTAssertFalse(
      request.accepts(
        AIModelExecutionResult(
          requestID: UUID(),
          assetID: assetID,
          recipeRevision: 12,
          modelID: request.modelID,
          modelVersion: request.modelVersion,
          output: Data([1])
        )
      )
    )
  }
}
