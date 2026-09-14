import XCTest
import UIKit
import SwiftUI
import VultisigUIResources

final class SharedImageResourceTests: XCTestCase {
    func testEveryCatalogImageLoadsFromTheSharedBundle() {
        XCTAssertFalse(VultisigResources.imageNames.isEmpty)
        for name in VultisigResources.imageNames.sorted() {
            XCTAssertNotNil(VultisigResources.platformImage(named: name), "Missing compiled shared image: \(name)")
        }
    }

    func testRuneAndChainBadgeUseSharedBundle() {
        XCTAssertNotNil(VultisigResources.platformImage(named: "rune"))
        XCTAssertNotNil(VultisigResources.platformImage(named: "chain-rune"))
        XCTAssertFalse(VultisigResources.containsImage(named: "RUNE"))
        XCTAssertFalse(VultisigResources.containsImage(named: "https://example.com/rune.png"))
        XCTAssertNil(VultisigResources.platformImage(named: "../rune"))
    }

    func testTypedResourcesResolveTheSharedCatalog() {
        XCTAssertEqual(ImageResource.rune, ImageResource(name: "rune", bundle: VultisigResources.bundle))
        XCTAssertEqual(ImageResource.arrowToCornerTopRight,
                       ImageResource(name: "arrow-to-corner-top-right", bundle: VultisigResources.bundle))
    }
}
