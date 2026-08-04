//
//  KeychainTriStateReadTests.swift
//  VultisigAppTests
//
//  `SecItemCopyMatching` reports "no such item" and "could not read the item"
//  as different statuses, and the two license opposite decisions: absence says
//  a value may safely be written, an unreadable keychain says one may already
//  be there. These pin that the distinction survives every layer between
//  `SecItem` and the call site, for every failure a device can actually hand
//  back — because the moment it collapses, a transient failure looks exactly
//  like permission to overwrite whatever is stored.
//

import Security
import XCTest
@testable import VultisigApp

final class KeychainTriStateReadTests: XCTestCase {

    private static let serviceName = "com.vultisig.tests.keychain"

    /// Failures a real device hands back, none of which mean "no such item".
    /// `errSecInteractionNotAllowed` is the everyday one — a read while the
    /// device is locked — and `errSecMissingEntitlement` is what this very test
    /// bundle would get from the real Keychain.
    private static let failureStatuses: [OSStatus] = [
        errSecInteractionNotAllowed,
        errSecNotAvailable,
        errSecAuthFailed,
        errSecMissingEntitlement,
        errSecUserCanceled,
        errSecDecode,
        errSecParam,
        errSecIO
    ]

    // MARK: - Keychain

    func testReadsAStoredStringAsPresent() {
        let keychain = makeKeychain(status: errSecSuccess, data: Data("hunter2".utf8))

        XCTAssertEqual(keychain.getString(for: TestKey()), .present("hunter2"))
    }

    func testReadsAStoredIntegerAsPresent() {
        let keychain = makeKeychain(status: errSecSuccess, data: Data("42".utf8))

        XCTAssertEqual(keychain.getInt(for: TestKey()), .present(42))
    }

    func testReportsAbsentOnlyWhenTheItemIsNotFound() {
        let keychain = makeKeychain(status: errSecItemNotFound, data: nil)

        XCTAssertEqual(keychain.getString(for: TestKey()), .absent)
        XCTAssertEqual(keychain.getInt(for: TestKey()), .absent)
    }

    func testReportsUnavailableForEveryOtherFailingStatus() {
        for status in Self.failureStatuses {
            let keychain = makeKeychain(status: status, data: nil)

            XCTAssertEqual(
                keychain.getString(for: TestKey()),
                .unavailable(status),
                "status \(status) is a failed read, not an absent item"
            )
            XCTAssertEqual(
                keychain.getInt(for: TestKey()),
                .unavailable(status),
                "status \(status) is a failed read, not an absent item"
            )
        }
    }

    func testReportsUnavailableWhenTheKeychainSucceedsWithoutData() {
        let keychain = makeKeychain(status: errSecSuccess, data: nil)

        XCTAssertEqual(keychain.getString(for: TestKey()), .unavailable(errSecDecode))
    }

    /// An item that exists but cannot be decoded is still an item. Reporting it
    /// as absent would invite the caller to write over it.
    func testReportsUnavailableWhenTheStoredBytesAreNotUTF8() {
        let keychain = makeKeychain(status: errSecSuccess, data: Data([0xFF, 0xFE, 0xFD]))

        XCTAssertEqual(keychain.getString(for: TestKey()), .unavailable(errSecDecode))
    }

    func testReportsUnavailableWhenTheStoredStringIsNotAnInteger() {
        let keychain = makeKeychain(status: errSecSuccess, data: Data("not-a-number".utf8))

        XCTAssertEqual(keychain.getInt(for: TestKey()), .unavailable(errSecDecode))
    }

    // MARK: - KeychainService

    func testEveryServiceReadReportsUnavailableRatherThanAbsent() {
        for status in Self.failureStatuses {
            let service = makeService(status: status, data: nil)

            XCTAssertEqual(
                service.getFastPassword(pubKeyECDSA: "pub"),
                .unavailable(status),
                "the fast-vault password read must not pass a failure off as an absent item (status \(status))"
            )
            XCTAssertEqual(
                service.getFastHint(pubKeyECDSA: "pub"),
                .unavailable(status),
                "the fast-vault hint read must not pass a failure off as an absent item (status \(status))"
            )
            XCTAssertEqual(
                service.getDeviceToken(),
                .unavailable(status),
                "the device-token read must not pass a failure off as an absent item (status \(status))"
            )
            XCTAssertEqual(
                service.getLastMigratedVersion(),
                .unavailable(status),
                "the migration-version read must not pass a failure off as an absent item (status \(status))"
            )
        }
    }

    func testEveryServiceReadReportsAbsentWhenTheItemIsNotFound() {
        let service = makeService(status: errSecItemNotFound, data: nil)

        XCTAssertEqual(service.getFastPassword(pubKeyECDSA: "pub"), .absent)
        XCTAssertEqual(service.getFastHint(pubKeyECDSA: "pub"), .absent)
        XCTAssertEqual(service.getDeviceToken(), .absent)
        XCTAssertEqual(service.getLastMigratedVersion(), .absent)
    }

    func testEveryServiceReadReturnsTheStoredValue() {
        let service = makeService(status: errSecSuccess, data: Data("7".utf8))

        XCTAssertEqual(service.getFastPassword(pubKeyECDSA: "pub"), .present("7"))
        XCTAssertEqual(service.getFastHint(pubKeyECDSA: "pub"), .present("7"))
        XCTAssertEqual(service.getDeviceToken(), .present("7"))
        XCTAssertEqual(service.getLastMigratedVersion(), .present(7))
    }

    // MARK: - The deliberate collapse

    func testCollapsingToAnOptionalKeepsOnlyThePresentValue() {
        XCTAssertEqual(KeychainReadResult.present("value").valueTreatingUnavailableAsAbsent, "value")
        XCTAssertNil(KeychainReadResult<String>.absent.valueTreatingUnavailableAsAbsent)

        for status in Self.failureStatuses {
            XCTAssertNil(KeychainReadResult<String>.unavailable(status).valueTreatingUnavailableAsAbsent)
        }
    }

    // MARK: - Helpers

    private func makeKeychain(status: OSStatus, data: Data?) -> Keychain {
        Keychain(serviceName: Self.serviceName, itemStore: FakeItemStore(status: status, data: data))
    }

    private func makeService(status: OSStatus, data: Data?) -> KeychainService {
        DefaultKeychainService(keychain: makeKeychain(status: status, data: data))
    }
}

/// Answers every read with the status and payload the test asked for, so a
/// failure the test host could never provoke against the real Keychain can be
/// injected directly.
private struct FakeItemStore: KeychainItemStore {

    let status: OSStatus
    let data: Data?

    func copyMatching(_: [String: Any]) -> (status: OSStatus, data: Data?) {
        (status, data)
    }

    func add(_: [String: Any]) -> OSStatus { errSecSuccess }

    func delete(_: [String: Any]) -> OSStatus { errSecSuccess }
}

private struct TestKey: KeychainIdentifier {
    let identifier = "com.vultisig.tests.keychain.item"
}
