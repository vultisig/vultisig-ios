import Combine
import SwiftUI
import XCTest
@testable import VultisigApp

@MainActor
final class NavigationRouterTests: XCTestCase {
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

}
