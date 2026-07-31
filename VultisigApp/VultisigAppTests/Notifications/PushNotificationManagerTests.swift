//
//  PushNotificationManagerTests.swift
//  VultisigAppTests
//

import CryptoKit
import Foundation
import XCTest
@testable import VultisigApp

@MainActor
final class PushNotificationManagerTests: XCTestCase {

    private var contextToken: TestContextToken?

    override func setUp() async throws {
        try await super.setUp()
        contextToken = try TestStore.installInMemoryContainer()
    }

    override func tearDown() async throws {
        TestStore.restore(contextToken)
        contextToken = nil
        try await super.tearDown()
    }

    func test_initHydratesDeviceTokenFromKeychain() {
        let keychain = MockKeychainService()
        keychain.setDeviceToken("cached-token")

        let manager = PushNotificationManager(
            notificationService: NotificationServiceSpy(),
            keychainService: keychain
        )

        XCTAssertEqual(manager.deviceToken, "cached-token")
    }

    func test_unchangedTokenReRegistersOptedInVault() async throws {
        let tokenData = Data([0x01, 0xAB, 0xFF])
        let tokenString = "01abff"
        let keychain = MockKeychainService()
        keychain.setDeviceToken(tokenString)
        let service = NotificationServiceSpy()
        let manager = PushNotificationManager(
            notificationService: service,
            keychainService: keychain
        )
        let vault = TestStore.makeVault()
        let settings = VaultSettings(vault: vault)
        settings.notificationsEnabled = true
        Storage.shared.insert(settings)
        vault.settings = settings
        try Storage.shared.save()

        manager.setDeviceToken(tokenData)

        try await waitUntil { service.registerRequests.count == 1 }
        let request = try XCTUnwrap(service.registerRequests.first)
        XCTAssertEqual(request.vaultId, notificationVaultId(for: vault))
        XCTAssertEqual(request.partyName, vault.localPartyID)
        XCTAssertEqual(request.token, tokenString)
        XCTAssertEqual(request.deviceType, "apple")
    }

    func test_reRegisterOptedInVaultsSkipsOptedOutVaults() async {
        let keychain = MockKeychainService()
        keychain.setDeviceToken("cached-token")
        let service = NotificationServiceSpy()
        let manager = PushNotificationManager(
            notificationService: service,
            keychainService: keychain
        )
        let optedInVault = TestStore.makeVault(pubKey: "opted-in")
        let optedInSettings = VaultSettings(vault: optedInVault)
        optedInSettings.notificationsEnabled = true
        optedInVault.settings = optedInSettings
        let optedOutVault = TestStore.makeVault(pubKey: "opted-out")

        await manager.reRegisterOptedInVaults([optedInVault, optedOutVault])

        XCTAssertEqual(service.registerRequests.count, 1)
        XCTAssertEqual(service.registerRequests.first?.partyName, optedInVault.localPartyID)
    }

    private func waitUntil(
        timeout: TimeInterval = 1,
        _ condition: () -> Bool,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            if Date() > deadline {
                XCTFail("Timed out waiting for condition", file: file, line: line)
                return
            }
            try await Task.sleep(nanoseconds: 5_000_000)
        }
    }

    private func notificationVaultId(for vault: Vault) -> String {
        let data = Data((vault.pubKeyECDSA + vault.hexChainCode).utf8)
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

private final class NotificationServiceSpy: NotificationServicing, @unchecked Sendable {
    private let lock = NSLock()
    private var requests: [DeviceRegistrationRequest] = []

    var registerRequests: [DeviceRegistrationRequest] {
        lock.withLock { requests }
    }

    // `async` comes from `NotificationServicing`, not from this body.
    // swiftlint:disable:next async_without_await
    func registerDevice(request: DeviceRegistrationRequest) async throws {
        lock.withLock { requests.append(request) }
    }

    // `async` comes from `NotificationServicing`, not from this body.
    // swiftlint:disable:next async_without_await
    func unregisterDevice(vaultId _: String, partyName _: String) async throws {}

    // `async` comes from `NotificationServicing`, not from this body.
    // swiftlint:disable:next async_without_await
    func sendNotification(request _: NotifyRequest) async throws {}
}
