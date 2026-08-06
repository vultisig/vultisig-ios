//
//  KeychainWriteSeamTests.swift
//  VultisigAppTests
//
//  What `Keychain` hands to `SecItem` on a write — the query, the attributes and
//  the call order — pinned through the `KeychainItemStore` seam, since a unit
//  test bundle has no keychain entitlement and could never observe a real write.
//
//  `KeychainWriteTests` covers the same seam from the other side: this file
//  pins the payloads, that one pins the add-versus-update state machine and what
//  a failed write leaves behind.
//

import Security
import XCTest
@testable import VultisigApp

final class KeychainWriteSeamTests: XCTestCase {

    private static let serviceName = "com.vultisig.tests.keychain"

    /// Update first, add only when there is nothing to update — never
    /// delete-then-add, which would destroy the stored value before knowing the
    /// replacement landed.
    func testWritingAValueUpdatesFirstAndAddsOnlyWhenNoItemExists() {
        let store = RecordingItemStore()

        Keychain(serviceName: Self.serviceName, itemStore: store).setString("hunter2", for: TestKey())

        XCTAssertEqual(store.calls, ["update", "add"])
    }

    func testTheUpdateCarriesTheGeneratedQueryWithoutTheReturnFlag() throws {
        let store = RecordingItemStore()

        Keychain(serviceName: Self.serviceName, itemStore: store).setString("hunter2", for: TestKey())

        let query = try XCTUnwrap(store.updatedQueries.first)
        XCTAssertEqual(query[kSecClass as String] as? String, kSecClassGenericPassword as String)
        XCTAssertEqual(query[kSecAttrService as String] as? String, Self.serviceName)
        XCTAssertEqual(query[kSecAttrAccount as String] as? String, TestKey().identifier)
        XCTAssertNil(query[kSecReturnData as String], "the return flag belongs to reads, not to a write query")
    }

    func testTheUpdateCarriesOnlyTheValueAndAccessibility() throws {
        let store = RecordingItemStore()

        Keychain(serviceName: Self.serviceName, itemStore: store).setString("hunter2", for: TestKey())

        let attributes = try XCTUnwrap(store.updatedAttributes.first)
        XCTAssertEqual(attributes[kSecValueData as String] as? Data, Data("hunter2".utf8))
        XCTAssertEqual(
            attributes[kSecAttrAccessible as String] as? String,
            kSecAttrAccessibleWhenUnlockedThisDeviceOnly as String
        )
        XCTAssertNil(attributes[kSecAttrService as String], "an update must not restate the item's identity")
    }

    func testTheAddCarriesTheValueAndAccessibilityWithoutTheReturnFlag() throws {
        let store = RecordingItemStore()

        Keychain(serviceName: Self.serviceName, itemStore: store).setString("hunter2", for: TestKey())

        let attributes = try XCTUnwrap(store.addedAttributes.first)
        XCTAssertEqual(
            attributes[kSecClass as String] as? String,
            kSecClassGenericPassword as String,
            "the class survives the query being reused as the added item's attributes"
        )
        XCTAssertEqual(attributes[kSecValueData as String] as? Data, Data("hunter2".utf8))
        XCTAssertEqual(
            attributes[kSecAttrAccessible as String] as? String,
            kSecAttrAccessibleWhenUnlockedThisDeviceOnly as String
        )
        XCTAssertEqual(attributes[kSecAttrService as String] as? String, Self.serviceName)
        XCTAssertEqual(attributes[kSecAttrAccount as String] as? String, TestKey().identifier)
        XCTAssertNil(attributes[kSecReturnData as String], "the return flag belongs to reads, not to the added item")
    }

    func testWritingAnIntegerStoresItsDecimalText() throws {
        let store = RecordingItemStore()

        Keychain(serviceName: Self.serviceName, itemStore: store).setInt(42, for: TestKey())

        let attributes = try XCTUnwrap(store.addedAttributes.first)
        XCTAssertEqual(attributes[kSecValueData as String] as? Data, Data("42".utf8))
    }

    func testWritingNilDeletesWithoutAddingOrUpdating() {
        let store = RecordingItemStore()

        Keychain(serviceName: Self.serviceName, itemStore: store).setString(nil, for: TestKey())

        XCTAssertEqual(store.calls, ["delete"])
    }

    func testDeletingIssuesASingleDelete() {
        let store = RecordingItemStore()

        Keychain(serviceName: Self.serviceName, itemStore: store).delete(for: TestKey())

        XCTAssertEqual(store.calls, ["delete"])
    }

    /// A failing add is not retried, and — the property that matters — nothing
    /// is deleted on the way, so whatever was stored is still stored.
    func testAFailedAddIsNotRetriedAndDeletesNothing() {
        let store = RecordingItemStore(addStatus: errSecDuplicateItem)

        Keychain(serviceName: Self.serviceName, itemStore: store).setString("hunter2", for: TestKey())

        XCTAssertEqual(store.calls, ["update", "add"])
    }
}

/// Records what the write path hands to `SecItem`, and answers reads and updates
/// as if the item were absent.
private final class RecordingItemStore: KeychainItemStore {

    private(set) var calls: [String] = []
    private(set) var updatedQueries: [[String: Any]] = []
    private(set) var updatedAttributes: [[String: Any]] = []
    private(set) var addedAttributes: [[String: Any]] = []

    private let addStatus: OSStatus

    init(addStatus: OSStatus = errSecSuccess) {
        self.addStatus = addStatus
    }

    func copyMatching(_: [String: Any]) -> (status: OSStatus, data: Data?) {
        (errSecItemNotFound, nil)
    }

    func add(_ attributes: [String: Any]) -> OSStatus {
        calls.append("add")
        addedAttributes.append(attributes)
        return addStatus
    }

    func update(_ query: [String: Any], attributes: [String: Any]) -> OSStatus {
        calls.append("update")
        updatedQueries.append(query)
        updatedAttributes.append(attributes)
        return errSecItemNotFound
    }

    func delete(_: [String: Any]) -> OSStatus {
        calls.append("delete")
        return errSecSuccess
    }
}

private struct TestKey: KeychainIdentifier {
    let identifier = "com.vultisig.tests.keychain.item"
}
