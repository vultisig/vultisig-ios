//
//  KeysignReviewPresenterTests.swift
//  VultisigAppTests
//

import XCTest
@testable import VultisigApp

@MainActor
final class KeysignReviewPresenterTests: XCTestCase {
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

    func testPresentShowsTheReview() {
        let presenter = KeysignReviewPresenter()
        let review = KeysignReviewFixture.swapReview()

        presenter.present(review)

        XCTAssertEqual(presenter.presented, review)
        XCTAssertTrue(presenter.isPresenting)
    }

    func testSecondPresentWhileOneIsUpIsIgnored() {
        let presenter = KeysignReviewPresenter()
        let first = KeysignReviewFixture.swapReview()
        let second = KeysignReviewFixture.swapReview()
        XCTAssertNotEqual(first, second)

        presenter.present(first)
        presenter.present(second)

        XCTAssertEqual(presenter.presented, first)
    }

    func testPresentWhileTheHandOffIsPendingIsIgnored() {
        let presenter = KeysignReviewPresenter()
        let router = NavigationRouter()
        presenter.present(KeysignReviewFixture.swapReview())
        presenter.proceed(to: KeysignReviewFixture.fastKeysignRoute(), presentationID: presenter.presentationID)

        presenter.present(KeysignReviewFixture.swapReview())

        XCTAssertNil(presenter.presented)
        XCTAssertTrue(presenter.isPresenting)
        presenter.sheetDidDismiss(router: router)
        XCTAssertFalse(presenter.isPresenting)
    }

    func testProceedPushesOnlyOnceTheSheetHasDismissed() {
        let presenter = KeysignReviewPresenter()
        let router = NavigationRouter()
        router.navigate(to: "form")
        presenter.present(KeysignReviewFixture.swapReview())

        presenter.proceed(to: KeysignReviewFixture.fastKeysignRoute(), presentationID: presenter.presentationID)

        XCTAssertNil(presenter.presented)
        XCTAssertEqual(router.navPath.count, 1)

        presenter.sheetDidDismiss(router: router)

        XCTAssertEqual(router.navPath.count, 2)
        XCTAssertTrue(router.isShowingSigningRoute)
        XCTAssertFalse(presenter.isPresenting)
    }

    func testRouteIsPushedOnce() {
        let presenter = KeysignReviewPresenter()
        let router = NavigationRouter()
        presenter.present(KeysignReviewFixture.swapReview())
        presenter.proceed(to: KeysignReviewFixture.pairRoute(), presentationID: presenter.presentationID)

        presenter.sheetDidDismiss(router: router)
        presenter.sheetDidDismiss(router: router)

        XCTAssertEqual(router.navPath.count, 1)
    }

    func testDismissClosesTheReviewWithoutAPush() {
        let presenter = KeysignReviewPresenter()
        let router = NavigationRouter()
        presenter.present(KeysignReviewFixture.swapReview())

        presenter.dismiss()
        presenter.sheetDidDismiss(router: router)

        XCTAssertNil(presenter.presented)
        XCTAssertTrue(router.navPath.isEmpty)
        XCTAssertFalse(presenter.isPresenting)
    }

    func testDismissWithoutProceedPushesNothing() {
        let presenter = KeysignReviewPresenter()
        let router = NavigationRouter()
        router.navigate(to: "form")
        presenter.present(KeysignReviewFixture.swapReview())

        // What the sheet's binding does when the user swipes it away.
        presenter.presented = nil
        presenter.sheetDidDismiss(router: router)

        XCTAssertEqual(router.navPath.count, 1)
        XCTAssertFalse(presenter.isPresenting)
    }

    func testProceedAfterTheUserDismissedIsIgnored() {
        let presenter = KeysignReviewPresenter()
        let router = NavigationRouter()
        presenter.present(KeysignReviewFixture.swapReview())
        presenter.presented = nil
        presenter.sheetDidDismiss(router: router)

        presenter.proceed(to: KeysignReviewFixture.fastKeysignRoute(), presentationID: presenter.presentationID)
        presenter.sheetDidDismiss(router: router)

        XCTAssertTrue(router.navPath.isEmpty)
        XCTAssertFalse(presenter.isPresenting)
    }

    func testProceedFromAnEarlierPresentationIsIgnored() {
        let presenter = KeysignReviewPresenter()
        let router = NavigationRouter()
        presenter.present(KeysignReviewFixture.swapReview())
        let firstPresentation = presenter.presentationID
        presenter.presented = nil
        presenter.sheetDidDismiss(router: router)
        let second = KeysignReviewFixture.swapReview()
        presenter.present(second)

        presenter.proceed(to: KeysignReviewFixture.fastKeysignRoute(), presentationID: firstPresentation)
        presenter.sheetDidDismiss(router: router)

        XCTAssertEqual(presenter.presented, second)
        XCTAssertTrue(router.navPath.isEmpty)
    }

    func testPreparationFinishingDuringOverlayDismissalCannotSign() async {
        let presenter = KeysignReviewPresenter()
        let router = NavigationRouter()
        presenter.present(KeysignReviewFixture.swapReview())
        let presentationID = presenter.presentationID
        let preparation = Task { @MainActor in
            await Task.yield()
            presenter.proceed(to: KeysignReviewFixture.fastKeysignRoute(), presentationID: presentationID)
        }

        // Escape/backdrop dismissal clears the binding immediately; the
        // host's dismissal callback arrives only after its fade completes.
        presenter.presented = nil
        await preparation.value
        XCTAssertFalse(presenter.isPresenting)
        XCTAssertTrue(router.navPath.isEmpty)

        presenter.sheetDidDismiss(router: router)
        XCTAssertTrue(router.navPath.isEmpty)
    }

    func testReopenStartsANewPresentation() {
        let presenter = KeysignReviewPresenter()
        let router = NavigationRouter()
        presenter.present(KeysignReviewFixture.swapReview())
        let firstPresentation = presenter.presentationID
        presenter.proceed(to: KeysignReviewFixture.pairRoute(), presentationID: firstPresentation)
        presenter.sheetDidDismiss(router: router)

        router.navigateBackOutOfSigning()
        presenter.reopenForRetry()
        presenter.completeReopen(isShowingSigningRoute: router.isShowingSigningRoute)

        XCTAssertNotNil(presenter.presented)
        XCTAssertNotEqual(presenter.presentationID, firstPresentation)
    }

    func testRetryReopensTheLastReviewOnceOutOfSigning() {
        let presenter = KeysignReviewPresenter()
        let router = NavigationRouter()
        let review = KeysignReviewFixture.swapReview()
        router.navigate(to: "form")
        presenter.present(review)
        presenter.proceed(to: KeysignReviewFixture.pairRoute(), presentationID: presenter.presentationID)
        presenter.sheetDidDismiss(router: router)
        router.navigate(to: KeysignReviewFixture.fastKeysignRoute())

        presenter.reopenForRetry()
        XCTAssertTrue(presenter.isReopenPending)

        presenter.completeReopen(isShowingSigningRoute: router.isShowingSigningRoute)
        XCTAssertNil(presenter.presented, "The review must wait for the signing screens to pop")
        XCTAssertTrue(presenter.isReopenPending)

        router.navigateBackOutOfSigning()
        presenter.completeReopen(isShowingSigningRoute: router.isShowingSigningRoute)

        XCTAssertEqual(presenter.presented, review)
        XCTAssertFalse(presenter.isReopenPending)
        XCTAssertEqual(router.navPath.count, 1)
    }

    func testCompleteReopenWithoutARetryDoesNothing() {
        let presenter = KeysignReviewPresenter()
        presenter.present(KeysignReviewFixture.swapReview())
        presenter.presented = nil

        presenter.completeReopen(isShowingSigningRoute: false)

        XCTAssertNil(presenter.presented)
    }

    func testRetryWithNoReviewDoesNothing() {
        let presenter = KeysignReviewPresenter()

        presenter.reopenForRetry()
        presenter.completeReopen(isShowingSigningRoute: false)

        XCTAssertFalse(presenter.isReopenPending)
        XCTAssertNil(presenter.presented)
    }

    func testFlowFinishedClearsTheReviewForRetry() {
        let presenter = KeysignReviewPresenter()
        let router = NavigationRouter()
        presenter.present(KeysignReviewFixture.swapReview())
        presenter.proceed(to: KeysignReviewFixture.fastKeysignRoute(), presentationID: presenter.presentationID)
        presenter.sheetDidDismiss(router: router)

        presenter.flowFinished()
        presenter.reopenForRetry()
        presenter.completeReopen(isShowingSigningRoute: false)

        XCTAssertFalse(presenter.isReopenPending)
        XCTAssertNil(presenter.presented)
    }

    func testFlowFinishedCancelsAPendingReopen() {
        let presenter = KeysignReviewPresenter()
        let router = NavigationRouter()
        presenter.present(KeysignReviewFixture.swapReview())
        presenter.proceed(to: KeysignReviewFixture.fastKeysignRoute(), presentationID: presenter.presentationID)
        presenter.sheetDidDismiss(router: router)
        presenter.reopenForRetry()

        presenter.flowFinished()
        presenter.completeReopen(isShowingSigningRoute: false)

        XCTAssertFalse(presenter.isReopenPending)
        XCTAssertNil(presenter.presented)
    }

    func testNewReviewReplacesAPendingReopen() {
        let presenter = KeysignReviewPresenter()
        let router = NavigationRouter()
        presenter.present(KeysignReviewFixture.swapReview())
        presenter.proceed(to: KeysignReviewFixture.fastKeysignRoute(), presentationID: presenter.presentationID)
        presenter.sheetDidDismiss(router: router)
        presenter.reopenForRetry()
        let newReview = KeysignReviewFixture.swapReview()

        presenter.present(newReview)

        XCTAssertFalse(presenter.isReopenPending)
        XCTAssertEqual(presenter.presented, newReview)
    }
}
