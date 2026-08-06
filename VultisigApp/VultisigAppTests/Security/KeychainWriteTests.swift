//
//  KeychainWriteTests.swift
//  VultisigAppTests
//

import XCTest
@testable import VultisigApp

/// Drives `Keychain`'s write path through a fake `KeychainItemStore`.
///
/// The real `SecItem` calls are unreachable from a test bundle — no keychain
/// entitlement, so every one returns `errSecMissingEntitlement` — which is why
/// the seam exists. What is being pinned here is the property that a write which
/// fails must leave the previously stored value alone: for the key that opens
/// the vault key shares, destroying the old value on a failed write would leave
/// every share encrypted under a key that no longer exists.
final class KeychainWriteTests: XCTestCase {

    private struct TestKey: KeychainIdentifier {
        let identifier = "com.vultisig.wallet.tests.item"
    }

    private var itemStore: FakeKeychainItemStore!
    private var sut: Keychain!
    private let key = TestKey()

    override func setUp() {
        super.setUp()
        itemStore = FakeKeychainItemStore()
        sut = Keychain(serviceName: "com.vultisig.wallet.tests", itemStore: itemStore)
    }

    override func tearDown() {
        sut = nil
        itemStore = nil
        super.tearDown()
    }

    // MARK: - Add vs update

    func testWritingWhenNoItemExistsAddsIt() {
        let value = Data(repeating: 0x01, count: 32)

        XCTAssertTrue(sut.setData(value, for: key))

        XCTAssertEqual(itemStore.addCount, 1)
        XCTAssertEqual(itemStore.updateCount, 1, "Update is attempted first and reports not-found")
        XCTAssertEqual(sut.getData(for: key), .present(value))
    }

    func testWritingOverAnExistingItemUpdatesInPlace() {
        let original = Data(repeating: 0x01, count: 32)
        let replacement = Data(repeating: 0x02, count: 32)
        XCTAssertTrue(sut.setData(original, for: key))
        itemStore.resetCounts()

        XCTAssertTrue(sut.setData(replacement, for: key))

        XCTAssertEqual(itemStore.updateCount, 1)
        XCTAssertEqual(itemStore.addCount, 0, "An existing item must not be re-added")
        XCTAssertEqual(sut.getData(for: key), .present(replacement))
    }

    /// The regression this whole seam exists for.
    func testFailedOverwriteLeavesThePreviousValueIntact() {
        let original = Data(repeating: 0x01, count: 32)
        XCTAssertTrue(sut.setData(original, for: key))
        itemStore.resetCounts()
        itemStore.updateStatus = errSecIO

        XCTAssertFalse(sut.setData(Data(repeating: 0x02, count: 32), for: key))

        XCTAssertEqual(sut.getData(for: key), .present(original), "A failed write must not destroy the stored value")
        XCTAssertEqual(itemStore.deleteCount, 0, "A failed write must never delete")
    }

    func testFailedAddReportsFailure() {
        itemStore.addStatus = errSecIO

        XCTAssertFalse(sut.setData(Data(repeating: 0x01, count: 32), for: key))

        XCTAssertEqual(sut.getData(for: key), .absent)
    }

    func testWriteNeverDeletesBeforeAdding() {
        XCTAssertTrue(sut.setData(Data(repeating: 0x01, count: 32), for: key))

        XCTAssertEqual(itemStore.deleteCount, 0)
    }

    // MARK: - Accessibility

    func testAccessibilityDefaultsToThisDeviceOnly() {
        sut.setData(Data(repeating: 0x01, count: 32), for: key)

        XCTAssertEqual(itemStore.lastAccessibility, kSecAttrAccessibleWhenUnlockedThisDeviceOnly as String)
    }

    func testAccessibilityOverrideIsApplied() {
        sut.setData(Data(repeating: 0x01, count: 32), for: key, accessibility: kSecAttrAccessibleWhenUnlocked)

        XCTAssertEqual(itemStore.lastAccessibility, kSecAttrAccessibleWhenUnlocked as String)
    }

    func testAccessibilityOverrideIsAppliedOnUpdateToo() {
        sut.setData(Data(repeating: 0x01, count: 32), for: key)

        sut.setData(Data(repeating: 0x02, count: 32), for: key, accessibility: kSecAttrAccessibleWhenUnlocked)

        XCTAssertEqual(itemStore.lastAccessibility, kSecAttrAccessibleWhenUnlocked as String)
    }

    // MARK: - Delete

    func testWritingNilDeletesTheItem() {
        XCTAssertTrue(sut.setData(Data(repeating: 0x01, count: 32), for: key))

        XCTAssertTrue(sut.setData(nil, for: key))

        XCTAssertEqual(sut.getData(for: key), .absent)
        XCTAssertEqual(itemStore.deleteCount, 1)
    }

    func testDeletingAnAbsentItemIsNotAFailure() {
        XCTAssertTrue(sut.delete(for: key))
    }

    func testFailedDeleteReportsFailure() {
        itemStore.deleteStatus = errSecIO

        XCTAssertFalse(sut.delete(for: key))
    }
}

/// In-memory stand-in keyed by account, mirroring the `SecItem` status codes
/// `Keychain` branches on.
private final class FakeKeychainItemStore: KeychainItemStore {

    private var storage: [String: Data] = [:]

    private(set) var addCount = 0
    private(set) var updateCount = 0
    private(set) var deleteCount = 0
    private(set) var lastAccessibility: String?

    /// Overrides forcing the corresponding call to fail.
    var addStatus: OSStatus?
    var updateStatus: OSStatus?
    var deleteStatus: OSStatus?

    func resetCounts() {
        addCount = 0
        updateCount = 0
        deleteCount = 0
    }

    func copyMatching(_ query: [String: Any]) -> (status: OSStatus, data: Data?) {
        guard let account = account(in: query), let data = storage[account] else {
            return (errSecItemNotFound, nil)
        }
        return (errSecSuccess, data)
    }

    func add(_ attributes: [String: Any]) -> OSStatus {
        addCount += 1
        if let addStatus { return addStatus }

        guard let account = account(in: attributes),
              let data = attributes[String(kSecValueData)] as? Data else {
            return errSecParam
        }
        guard storage[account] == nil else { return errSecDuplicateItem }

        recordAccessibility(from: attributes)
        storage[account] = data
        return errSecSuccess
    }

    func update(_ query: [String: Any], attributes: [String: Any]) -> OSStatus {
        updateCount += 1

        guard let account = account(in: query), storage[account] != nil else {
            return errSecItemNotFound
        }
        if let updateStatus { return updateStatus }

        guard let data = attributes[String(kSecValueData)] as? Data else {
            return errSecParam
        }

        recordAccessibility(from: attributes)
        storage[account] = data
        return errSecSuccess
    }

    func delete(_ query: [String: Any]) -> OSStatus {
        deleteCount += 1
        if let deleteStatus { return deleteStatus }

        guard let account = account(in: query), storage.removeValue(forKey: account) != nil else {
            return errSecItemNotFound
        }
        return errSecSuccess
    }

    private func account(in query: [String: Any]) -> String? {
        query[String(kSecAttrAccount)] as? String
    }

    private func recordAccessibility(from attributes: [String: Any]) {
        lastAccessibility = attributes[String(kSecAttrAccessible)] as? String
    }
}
