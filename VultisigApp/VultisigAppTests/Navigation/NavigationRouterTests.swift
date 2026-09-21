import Combine
import SwiftUI
import XCTest
@testable import VultisigApp

@MainActor
final class NavigationRouterTests: XCTestCase {
    private var storeToken: TestContextToken?

    override func setUpWithError() throws {
        try super.setUpWithError()
        storeToken = try TestStore.installInMemoryContainer()
    }

    override func tearDown() {
        TestStore.restore(storeToken)
        storeToken = nil
        super.tearDown()
    }

    func testReturningToEmptyRootDoesNotPublish() {
        let router = NavigationRouter()
        var updates = 0
        let subscription = router.$navPath.dropFirst().sink { _ in updates += 1 }
        defer { subscription.cancel() }

        router.navigateToRoot()
        router.navigateToRoot()

        XCTAssertTrue(router.navPath.isEmpty)
        XCTAssertEqual(updates, 0)
    }

    func testReturningToRootPublishesOnceAndClearsThePath() {
        let router = NavigationRouter()
        router.navigate(to: "first")
        router.navigate(to: "second")
        var updates = 0
        let subscription = router.$navPath.dropFirst().sink { _ in updates += 1 }
        defer { subscription.cancel() }

        router.navigateToRoot()
        router.navigateToRoot()

        XCTAssertTrue(router.navPath.isEmpty)
        XCTAssertEqual(updates, 1)
    }

    func testReturningToRootClearsMatchingNavigationHistory() {
        let router = NavigationRouter()
        router.navigate(to: "oldRoute")
        router.navigate(to: "oldDetail")
        router.navigateToRoot()
        router.navigate(to: "newRoute")
        router.navigate(to: "newDetail")

        // A retired route must use the no-match fallback, going back one step.
        // Stale history would calculate a removal count larger than the path.
        router.navigateBack { ($0 as? String) == "oldRoute" }

        XCTAssertEqual(router.navPath.count, 1)
        router.navigateBack()
        XCTAssertTrue(router.navPath.isEmpty)
    }

    // MARK: - Pops through the stack's own binding

    func testStackBindingPopTrimsHistory() {
        let router = NavigationRouter()
        router.navigate(to: "first")
        router.navigate(to: "second")

        // The back button writes the path directly, bypassing the router.
        router.navPath.removeLast()

        XCTAssertEqual(router.topDestination as? String, "first")
    }

    func testMatchingPopAfterAStackBindingPopLandsOnTheMatch() {
        let router = NavigationRouter()
        router.navigate(to: "form")
        router.navigate(to: "verify")
        router.navigate(to: "pair")
        router.navPath.removeLast()
        router.navigate(to: "pair")
        router.navigate(to: "keysign")

        router.navigateBack { ($0 as? String) == "verify" }

        XCTAssertEqual(router.navPath.count, 2)
        XCTAssertEqual(router.topDestination as? String, "verify")
    }

    // MARK: - Leaving the signing screens

    func testNavigateBackOutOfSigningPopsEveryTrailingSigningRoute() {
        let router = NavigationRouter()
        router.navigate(to: "form")
        router.navigate(to: KeysignReviewFixture.pairRoute())
        router.navigate(to: KeysignReviewFixture.fastKeysignRoute())
        XCTAssertTrue(router.isShowingSigningRoute)

        router.navigateBackOutOfSigning()

        XCTAssertEqual(router.navPath.count, 1)
        XCTAssertEqual(router.topDestination as? String, "form")
        XCTAssertFalse(router.isShowingSigningRoute)
    }

    func testNavigateBackOutOfSigningPopsNothingWhenTheTopIsNotSigning() {
        let router = NavigationRouter()
        router.navigate(to: "form")
        router.navigate(to: KeysignReviewFixture.fastKeysignRoute())
        router.navigate(to: "details")
        var updates = 0
        let subscription = router.$navPath.dropFirst().sink { _ in updates += 1 }
        defer { subscription.cancel() }

        router.navigateBackOutOfSigning()

        XCTAssertEqual(router.navPath.count, 3)
        XCTAssertEqual(router.topDestination as? String, "details")
        XCTAssertEqual(updates, 0)
    }

    func testNavigateBackOutOfSigningStopsAtTheFirstOtherRoute() {
        let router = NavigationRouter()
        router.navigate(to: KeysignReviewFixture.fastKeysignRoute())
        router.navigate(to: "form")
        router.navigate(to: KeysignReviewFixture.pairRoute())
        router.navigate(to: KeysignReviewFixture.fastKeysignRoute())

        router.navigateBackOutOfSigning()

        XCTAssertEqual(router.navPath.count, 2)
        XCTAssertEqual(router.topDestination as? String, "form")
    }

    func testNavigateBackOutOfSigningAtTheRootDoesNothing() {
        let router = NavigationRouter()

        router.navigateBackOutOfSigning()

        XCTAssertTrue(router.navPath.isEmpty)
        XCTAssertNil(router.topDestination)
    }

    func testNavigateBackOutOfSigningKeepsTheFormAfterBackingOutOfPairing() {
        let router = NavigationRouter()
        router.navigate(to: "form")
        router.navigate(to: KeysignReviewFixture.pairRoute())
        // Back out of pairing with the stack's own button, then sign again.
        router.navPath.removeLast()
        router.navigate(to: KeysignReviewFixture.pairRoute())
        router.navigate(to: KeysignReviewFixture.fastKeysignRoute())

        router.navigateBackOutOfSigning()

        XCTAssertEqual(router.navPath.count, 1)
        XCTAssertEqual(router.topDestination as? String, "form")
    }
}
