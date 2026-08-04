//
//  AppMigrationServiceKeychainReadTests.swift
//  VultisigAppTests
//
//  The migration service is the one shipping consumer that reads a Keychain
//  item on every launch and acts on its absence. It folds an unreadable
//  Keychain into "nothing has been migrated" on purpose — the migrations are
//  idempotent, so repeating them costs a little work while skipping them would
//  leave the store half-converted. These pin that choice so it stays a decision
//  rather than a side effect of an optional.
//

import Security
import XCTest
@testable import VultisigApp

@MainActor
final class AppMigrationServiceKeychainReadTests: XCTestCase {

    /// The two `UserDefaults` keys the real migration list reads and writes.
    /// These tests drive every registered migration, and the promo-banner one
    /// seeds a process-wide store from app-wide defaults — so both are cleared
    /// for the duration and put back afterwards, or this class would leak state
    /// into whatever runs next in the same host.
    private static let legacyBannersKey = "appClosedBanners"
    private static let bannerDismissalsKey = "promoBannerDismissals"

    private var token: TestContextToken?
    private var savedDefaults: [String: Any] = [:]

    override func setUpWithError() throws {
        token = try TestStore.installInMemoryContainer()
        savedDefaults = [:]
        for key in [Self.legacyBannersKey, Self.bannerDismissalsKey] {
            if let value = UserDefaults.standard.object(forKey: key) {
                savedDefaults[key] = value
            }
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    override func tearDownWithError() throws {
        for key in [Self.legacyBannersKey, Self.bannerDismissalsKey] {
            if let value = savedDefaults[key] {
                UserDefaults.standard.set(value, forKey: key)
            } else {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }
        savedDefaults = [:]
        TestStore.restore(token)
        token = nil
    }

    func testAnAbsentRecordRunsTheMigrations() {
        let keychain = MockKeychainService()
        keychain.lastMigratedVersionResult = .absent

        AppMigrationService(keychainService: keychain).performMigrationsIfNeeded()

        XCTAssertNotNil(
            keychain.lastMigratedVersion,
            "a fresh install has no record, so every migration should run and ratchet the version forward"
        )
    }

    func testAnUnreadableKeychainRunsTheMigrationsInsteadOfSkippingThem() {
        let keychain = MockKeychainService()
        keychain.lastMigratedVersionResult = .unavailable(errSecInteractionNotAllowed)

        AppMigrationService(keychainService: keychain).performMigrationsIfNeeded()

        XCTAssertNotNil(
            keychain.lastMigratedVersion,
            "a failed read must not be mistaken for 'already migrated' - the migrations are idempotent, so re-running them is the safe answer"
        )
    }

    func testARecordAtOrBeyondTheLatestVersionSkipsTheMigrations() {
        let keychain = MockKeychainService(lastMigratedVersion: .max)

        AppMigrationService(keychainService: keychain).performMigrationsIfNeeded()

        XCTAssertEqual(
            keychain.lastMigratedVersion,
            .max,
            "nothing should run, and nothing should be written back"
        )
    }
}
