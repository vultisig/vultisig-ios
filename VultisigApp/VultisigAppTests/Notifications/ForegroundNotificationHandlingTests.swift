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

    override func tearDown() {
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
