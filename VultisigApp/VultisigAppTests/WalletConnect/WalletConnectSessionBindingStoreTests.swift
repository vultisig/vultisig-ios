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
}
