//
//  ForegroundNotificationHandlingTests.swift
//  VultisigAppTests
//

import Combine
import UserNotifications
import XCTest
@testable import VultisigApp

@MainActor
final class ForegroundNotificationHandlingTests: XCTestCase {
    private var cancellables: Set<AnyCancellable> = []
    /// The gate flag is on the shared view model, because that is where the rest
    /// of the app reads it from. Borrowed and put back so a locked test cannot
    /// leak into whatever runs next in the same process.
    private var borrowedPasscodeLock = false

    override func setUp() {
        super.setUp()
        borrowedPasscodeLock = AppViewModel.shared.isPasscodeLocked
        AppViewModel.shared.isPasscodeLocked = false
    }

    override func tearDown() {
        AppViewModel.shared.isPasscodeLocked = borrowedPasscodeLock
        cancellables.removeAll()
        super.tearDown()
    }

    func testDelegateUsesSystemPresentationWhenHandlerIsMissing() {
        let delegate = NotificationDelegate()
        var receivedOptions: UNNotificationPresentationOptions?

        delegate.presentationOptions(for: UNMutableNotificationContent()) {
            receivedOptions = $0
        }

        XCTAssertEqual(
            receivedOptions,
            ForegroundNotificationPresentationPolicy.systemOptions
        )
    }

    func testDelegateUsesSoundOnlyWhenCustomBannerHandlesNotification() {
        let delegate = NotificationDelegate()
        delegate.onForegroundNotification = { _, completion in
            completion(true)
        }
        var receivedOptions: UNNotificationPresentationOptions?

        delegate.presentationOptions(for: UNMutableNotificationContent()) {
            receivedOptions = $0
        }

        XCTAssertEqual(
            receivedOptions,
            ForegroundNotificationPresentationPolicy.customOptions
        )
    }

    func testDelegateUsesSystemPresentationWhenCustomBannerDeclinesNotification() {
        let delegate = NotificationDelegate()
        delegate.onForegroundNotification = { _, completion in
            completion(false)
        }
        var receivedOptions: UNNotificationPresentationOptions?

        delegate.presentationOptions(for: UNMutableNotificationContent()) {
            receivedOptions = $0
        }

        XCTAssertEqual(
            receivedOptions,
            ForegroundNotificationPresentationPolicy.systemOptions
        )
    }

    func testMissingDeeplinkDeclinesCustomPresentation() {
        let manager = makeManager()

        XCTAssertFalse(
            manager.handleForegroundNotification(UNMutableNotificationContent())
        )
        XCTAssertNil(manager.foregroundNotification)
    }

    func testVaultFetchFailureDeclinesCustomPresentation() {
        let manager = makeManager(fetchVaults: { throw TestError.fetchFailed })

        XCTAssertFalse(
            manager.handleForegroundNotification(makeValidContent())
        )
        XCTAssertNil(manager.foregroundNotification)
    }

    func testPresentedModalDeclinesCustomPresentation() {
        let manager = makeManager(canPresentForegroundBanner: { false })

        XCTAssertFalse(
            manager.handleForegroundNotification(makeValidContent())
        )
        XCTAssertNil(manager.foregroundNotification)
    }

    func testValidNotificationUsesCustomPresentation() {
        let manager = makeManager()

        XCTAssertTrue(
            manager.handleForegroundNotification(makeValidContent())
        )
        XCTAssertNotNil(manager.foregroundNotification)
    }

    func testIdenticalNotificationsPublishTwice() {
        let manager = makeManager()
        var received: [ForegroundNotificationData] = []
        manager.$foregroundNotification
            .compactMap { $0 }
            .sink { received.append($0) }
            .store(in: &cancellables)
        let content = makeValidContent()

        XCTAssertTrue(manager.handleForegroundNotification(content))
        XCTAssertTrue(manager.handleForegroundNotification(content))

        XCTAssertEqual(received.count, 2)
        XCTAssertEqual(received[0], received[1])
    }

    // MARK: - Behind the passcode gate

    /// The banner draws the vault name and a decoded transaction summary —
    /// "Send 1.2 ETH to 0x…" — and holds it for thirty seconds. Behind the lock
    /// screen that is precisely the disclosure the lock is there to prevent, and
    /// the banner's own check cannot see it: it asks whether a UIKit view
    /// controller is presented, and the gate is a SwiftUI overlay, which is not
    /// one.
    ///
    /// The unlocked assertion comes first on purpose. Every earlier decline in
    /// this file is also a `false`, so without it a change that broke the banner
    /// outright would pass this test.
    func testALockedAppRaisesNoForegroundBanner() {
        let manager = makeManager()
        XCTAssertTrue(
            manager.handleForegroundNotification(makeValidContent()),
            "precondition: unlocked, this notification does raise a banner"
        )
        manager.foregroundNotification = nil

        AppViewModel.shared.isPasscodeLocked = true

        XCTAssertFalse(manager.handleForegroundNotification(makeValidContent()))
        XCTAssertNil(manager.foregroundNotification)
    }

    /// Declining the custom banner is only half of it. The decline falls through
    /// to the *system* presentation, which the OS draws above every window the
    /// app owns and which carries the same payload — so a lock that only
    /// suppressed the custom banner would have swapped one banner for another.
    func testALockedAppSuppressesTheSystemBannerToo() {
        AppViewModel.shared.isPasscodeLocked = true
        let delegate = NotificationDelegate()
        delegate.onForegroundNotification = { _, completion in
            completion(false)
        }
        var receivedOptions: UNNotificationPresentationOptions?

        delegate.presentationOptions(for: makeValidContent()) {
            receivedOptions = $0
        }

        // Spelled out rather than compared against the policy's own constant:
        // asserting `lockedOptions == lockedOptions` would keep passing if that
        // constant were widened back to include the banner.
        XCTAssertEqual(receivedOptions, [.sound])
        XCTAssertFalse(receivedOptions?.contains(.banner) ?? true)
        XCTAssertFalse(receivedOptions?.contains(.list) ?? true)
    }

    /// Including the path where no handler is installed at all — the app has not
    /// finished launching, so nothing has declined anything, and the fall-through
    /// is the only decision made.
    func testALockedAppSuppressesTheSystemBannerWithNoHandlerInstalled() {
        AppViewModel.shared.isPasscodeLocked = true
        let delegate = NotificationDelegate()
        var receivedOptions: UNNotificationPresentationOptions?

        delegate.presentationOptions(for: makeValidContent()) {
            receivedOptions = $0
        }

        XCTAssertEqual(receivedOptions, [.sound])
    }

    /// And the gate coming down gives the banner back, so this is a suppression
    /// while locked rather than a suppression.
    func testAnUnlockedAppStillRaisesTheForegroundBanner() {
        AppViewModel.shared.isPasscodeLocked = true
        let manager = makeManager()
        XCTAssertFalse(manager.handleForegroundNotification(makeValidContent()))

        AppViewModel.shared.isPasscodeLocked = false

        XCTAssertTrue(manager.handleForegroundNotification(makeValidContent()))
        XCTAssertNotNil(manager.foregroundNotification)
    }

    private func makeManager(
        fetchVaults: @escaping () throws -> [Vault] = { [] },
        canPresentForegroundBanner: @escaping () -> Bool = { true }
    ) -> PushNotificationManager {
        PushNotificationManager(
            notificationService: StubNotificationService(),
            keychainService: MockKeychainService(),
            fetchVaults: fetchVaults,
            canPresentForegroundBanner: canPresentForegroundBanner
        )
    }

    private func makeValidContent() -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.body = "Transaction ready"
        content.userInfo = [
            "deeplink": "vultisig://keysign?vault=test-vault"
        ]
        return content
    }
}

private enum TestError: Error {
    case fetchFailed
}

private struct StubNotificationService: NotificationServicing {
    func registerDevice(request _: DeviceRegistrationRequest) async throws {
        await Task.yield()
    }

    func unregisterDevice(vaultId _: String, partyName _: String) async throws {
        await Task.yield()
    }

    func sendNotification(request _: NotifyRequest) async throws {
        await Task.yield()
    }
}
