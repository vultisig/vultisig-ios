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
///
/// `@unchecked Sendable`: everything mutable lives in `state`, which is only
/// touched while holding `lock`.
private final class FakeKeychainItemStore: KeychainItemStore, @unchecked Sendable {

    private struct State {
        var storage: [String: Data] = [:]
        var addCount = 0
        var updateCount = 0
        var deleteCount = 0
        var lastAccessibility: String?
        var addStatus: OSStatus?
        var updateStatus: OSStatus?
        var deleteStatus: OSStatus?

        mutating func recordAccessibility(from attributes: [String: Any]) {
            lastAccessibility = attributes[String(kSecAttrAccessible)] as? String
        }
    }

    private let lock = NSLock()
    private var state = State()

    var addCount: Int { withState { $0.addCount } }
    var updateCount: Int { withState { $0.updateCount } }
    var deleteCount: Int { withState { $0.deleteCount } }
    var lastAccessibility: String? { withState { $0.lastAccessibility } }

    /// Overrides forcing the corresponding call to fail.
    var addStatus: OSStatus? {
        get { withState { $0.addStatus } }
        set { withState { $0.addStatus = newValue } }
    }
    var updateStatus: OSStatus? {
        get { withState { $0.updateStatus } }
        set { withState { $0.updateStatus = newValue } }
    }
    var deleteStatus: OSStatus? {
        get { withState { $0.deleteStatus } }
        set { withState { $0.deleteStatus = newValue } }
    }

    func resetCounts() {
        withState { state in
            state.addCount = 0
            state.updateCount = 0
            state.deleteCount = 0
        }
    }

    func copyMatching(_ query: [String: Any]) -> (status: OSStatus, data: Data?) {
        withState { state in
            guard let account = Self.account(in: query), let data = state.storage[account] else {
                return (errSecItemNotFound, nil)
            }
            return (errSecSuccess, data)
        }
    }

    func add(_ attributes: [String: Any]) -> OSStatus {
        withState { state in
            state.addCount += 1
            if let addStatus = state.addStatus { return addStatus }

            guard let account = Self.account(in: attributes),
                  let data = attributes[String(kSecValueData)] as? Data else {
                return errSecParam
            }
            guard state.storage[account] == nil else { return errSecDuplicateItem }

            state.recordAccessibility(from: attributes)
            state.storage[account] = data
            return errSecSuccess
        }
    }

    func update(_ query: [String: Any], attributes: [String: Any]) -> OSStatus {
        withState { state in
            state.updateCount += 1

            guard let account = Self.account(in: query), state.storage[account] != nil else {
                return errSecItemNotFound
            }
            if let updateStatus = state.updateStatus { return updateStatus }

            guard let data = attributes[String(kSecValueData)] as? Data else {
                return errSecParam
            }

            state.recordAccessibility(from: attributes)
            state.storage[account] = data
            return errSecSuccess
        }
    }

    func delete(_ query: [String: Any]) -> OSStatus {
        withState { state in
            state.deleteCount += 1
            if let deleteStatus = state.deleteStatus { return deleteStatus }

            guard let account = Self.account(in: query), state.storage.removeValue(forKey: account) != nil else {
                return errSecItemNotFound
            }
            return errSecSuccess
        }
    }

    /// The lock is not recursive, so `body` must touch only the state it is
    /// handed, never another member of this fake.
    private func withState<T>(_ body: (inout State) -> T) -> T {
        lock.withLock { body(&state) }
    }

    private static func account(in query: [String: Any]) -> String? {
        query[String(kSecAttrAccount)] as? String
    }
}
