//
//  KeychainWriteSeamTests.swift
//  VultisigAppTests
//
//  Making reads tri-state moved `Keychain`'s `SecItem` calls behind
//  `KeychainItemStore`. The write path is supposed to come through that move
//  untouched — precisely the sort of claim nothing was checking, since a unit
//  test bundle has no keychain entitlement and could never observe a real
//  write. These pin the query, the attributes and the delete-then-add order the
//  Keychain has always used.
//

import Security
import XCTest
@testable import VultisigApp

final class KeychainWriteSeamTests: XCTestCase {

    private static let serviceName = "com.vultisig.tests.keychain"

    func testWritingAValueDeletesTheExistingItemBeforeAddingTheNewOne() {
        let store = RecordingItemStore()

        Keychain(serviceName: Self.serviceName, itemStore: store).setString("hunter2", for: TestKey())

        XCTAssertEqual(store.calls, ["delete", "add"])
    }

    func testTheDeleteCarriesTheGeneratedQuery() throws {
        let store = RecordingItemStore()

        Keychain(serviceName: Self.serviceName, itemStore: store).setString("hunter2", for: TestKey())

        let query = try XCTUnwrap(store.deletedQueries.first)
        XCTAssertEqual(query[kSecClass as String] as? String, kSecClassGenericPassword as String)
        XCTAssertEqual(query[kSecAttrService as String] as? String, Self.serviceName)
        XCTAssertEqual(query[kSecAttrAccount as String] as? String, TestKey().identifier)
        XCTAssertNotNil(query[kSecReturnData as String])
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

    func testWritingNilDeletesWithoutAdding() {
        let store = RecordingItemStore()

        Keychain(serviceName: Self.serviceName, itemStore: store).setString(nil, for: TestKey())

        XCTAssertEqual(store.calls, ["delete"])
    }

    func testDeletingIssuesASingleDelete() {
        let store = RecordingItemStore()

        Keychain(serviceName: Self.serviceName, itemStore: store).delete(for: TestKey())

        XCTAssertEqual(store.calls, ["delete"])
    }

    /// A failing write has always been swallowed here. Pinned so the seam is not
    /// blamed if that ever needs to change.
    func testAFailedAddIsIgnoredWithoutRetrying() {
        let store = RecordingItemStore(addStatus: errSecDuplicateItem)

        Keychain(serviceName: Self.serviceName, itemStore: store).setString("hunter2", for: TestKey())

        XCTAssertEqual(store.calls, ["delete", "add"])
    }
}

/// Records what the write path hands to `SecItem`, and answers reads as if the
/// item were absent.
private final class RecordingItemStore: KeychainItemStore {

    private(set) var calls: [String] = []
    private(set) var deletedQueries: [[String: Any]] = []
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

    func delete(_ query: [String: Any]) -> OSStatus {
        calls.append("delete")
        deletedQueries.append(query)
        return errSecSuccess
    }
}

private struct TestKey: KeychainIdentifier {
    let identifier = "com.vultisig.tests.keychain.item"
}
