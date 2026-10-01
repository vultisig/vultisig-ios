//
//  WalletConnectSessionBindingStoreTests.swift
//  VultisigAppTests
//

import XCTest
@testable import VultisigApp

final class WalletConnectSessionBindingStoreTests: XCTestCase {
    private var userDefaults: UserDefaults!
    private var store: WalletConnectSessionBindingStore!

    override func setUp() {
        super.setUp()
        userDefaults = UserDefaults(suiteName: "WalletConnectSessionBindingStoreTests")!
        userDefaults.removePersistentDomain(forName: "WalletConnectSessionBindingStoreTests")
        store = WalletConnectSessionBindingStore(userDefaults: userDefaults)
    }

    override func tearDown() {
        userDefaults.removePersistentDomain(forName: "WalletConnectSessionBindingStoreTests")
        store = nil
        userDefaults = nil
        super.tearDown()
    }

    func testSavesAndReadsBindingByTopic() {
        let binding = WalletConnectSessionBinding(
            topic: "topic-1",
            vaultPubKeyECDSA: "pubkey-1",
            dappName: "Example",
            dappURL: "https://example.com",
            createdAt: Date(timeIntervalSince1970: 1)
        )

        store.save(binding)

        XCTAssertEqual(store.binding(for: "topic-1"), binding)
        XCTAssertEqual(store.allBindings(), [binding])
    }

    func testSaveReplacesExistingTopicBinding() {
        store.save(WalletConnectSessionBinding(
            topic: "topic-1",
            vaultPubKeyECDSA: "old-pubkey",
            dappName: "Example",
            dappURL: "https://example.com",
            createdAt: Date(timeIntervalSince1970: 1)
        ))
        let replacement = WalletConnectSessionBinding(
            topic: "topic-1",
            vaultPubKeyECDSA: "new-pubkey",
            dappName: "Example",
            dappURL: "https://example.com",
            createdAt: Date(timeIntervalSince1970: 2)
        )

        store.save(replacement)

        XCTAssertEqual(store.allBindings(), [replacement])
    }

    func testRemoveBindingDeletesOnlyMatchingTopic() {
        let first = WalletConnectSessionBinding(
            topic: "topic-1",
            vaultPubKeyECDSA: "pubkey-1",
            dappName: "First",
            dappURL: "https://first.example",
            createdAt: Date(timeIntervalSince1970: 1)
        )
        let second = WalletConnectSessionBinding(
            topic: "topic-2",
            vaultPubKeyECDSA: "pubkey-2",
            dappName: "Second",
            dappURL: "https://second.example",
            createdAt: Date(timeIntervalSince1970: 2)
        )
        store.save(first)
        store.save(second)

        store.removeBinding(for: "topic-1")

        XCTAssertNil(store.binding(for: "topic-1"))
        XCTAssertEqual(store.allBindings(), [second])
    }

    func testRemoveBindingIgnoresUnknownTopic() {
        let binding = WalletConnectSessionBinding(
            topic: "topic-1",
            vaultPubKeyECDSA: "pubkey-1",
            dappName: "Example",
            dappURL: "https://example.com",
            createdAt: Date(timeIntervalSince1970: 1)
        )
        store.save(binding)

        store.removeBinding(for: "missing-topic")

        XCTAssertEqual(store.allBindings(), [binding])
    }
}
