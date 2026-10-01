//
//  WalletConnectSessionsViewModelTests.swift
//  VultisigAppTests
//

import XCTest
@testable import VultisigApp

@MainActor
final class WalletConnectSessionsViewModelTests: XCTestCase {
    private var userDefaults: UserDefaults!
    private var store: WalletConnectSessionBindingStore!

    override func setUp() {
        super.setUp()
        userDefaults = UserDefaults(suiteName: "WalletConnectSessionsViewModelTests")!
        userDefaults.removePersistentDomain(forName: "WalletConnectSessionsViewModelTests")
        store = WalletConnectSessionBindingStore(userDefaults: userDefaults)
    }

    override func tearDown() {
        userDefaults.removePersistentDomain(forName: "WalletConnectSessionsViewModelTests")
        store = nil
        userDefaults = nil
        super.tearDown()
    }

    func testLoadSortsBindingsNewestFirst() {
        let oldest = binding(topic: "topic-a", createdAt: Date(timeIntervalSince1970: 1))
        let newest = binding(topic: "topic-b", createdAt: Date(timeIntervalSince1970: 2))
        store.save(oldest)
        store.save(newest)

        let viewModel = WalletConnectSessionsViewModel(bindingStore: store, disconnectSession: { _ in })

        XCTAssertEqual(viewModel.bindings, [newest, oldest])
    }

    func testLoadKeepsNewestBindingPerDApp() {
        let oldest = binding(topic: "topic-a", createdAt: Date(timeIntervalSince1970: 1))
        let newest = WalletConnectSessionBinding(
            topic: "topic-b",
            vaultPubKeyECDSA: "pubkey-topic-b",
            dappName: "Example topic-b",
            dappURL: "https://topic-a.example.com/path",
            dappIconURL: "https://topic-a.example.com/icon.png",
            approvedChains: ["eip155:1"],
            createdAt: Date(timeIntervalSince1970: 2)
        )
        store.save(oldest)
        store.save(newest)

        let viewModel = WalletConnectSessionsViewModel(bindingStore: store, disconnectSession: { _ in })

        XCTAssertEqual(viewModel.bindings, [newest])
    }

    func testActiveDAppCountDedupesByDAppHost() {
        let oldest = binding(topic: "topic-a", createdAt: Date(timeIntervalSince1970: 1))
        let newestSameHost = WalletConnectSessionBinding(
            topic: "topic-b",
            vaultPubKeyECDSA: "pubkey-topic-b",
            dappName: "Example topic-b",
            dappURL: "https://topic-a.example.com/path",
            dappIconURL: "https://topic-a.example.com/icon.png",
            approvedChains: ["eip155:1"],
            createdAt: Date(timeIntervalSince1970: 2)
        )
        let otherDApp = binding(topic: "topic-c", createdAt: Date(timeIntervalSince1970: 3))
        store.save(oldest)
        store.save(newestSameHost)
        store.save(otherDApp)

        XCTAssertEqual(WalletConnectSessionBindingStore.activeDAppCount(bindingStore: store), 2)
    }

    func testRemoveCallsDisconnectAndReloadsBindings() async {
        let binding = binding(topic: "topic-1")
        store.save(binding)
        var disconnectedTopics: [String] = []
        let viewModel = WalletConnectSessionsViewModel(bindingStore: store, disconnectSession: { topic in
            disconnectedTopics.append(topic)
            self.store.removeBinding(for: topic)
        })

        await viewModel.remove(binding)

        XCTAssertEqual(disconnectedTopics, ["topic-1"])
        XCTAssertTrue(viewModel.bindings.isEmpty)
        XCTAssertNil(viewModel.errorMessage)
    }

    func testRemoveKeepsLocalDeleteWhenDisconnectFailsAndSurfacesError() async {
        let binding = binding(topic: "topic-1")
        store.save(binding)
        let viewModel = WalletConnectSessionsViewModel(bindingStore: store, disconnectSession: { _ in
            throw WalletConnectError.disconnectionFailed("network")
        })

        await viewModel.remove(binding)

        XCTAssertTrue(viewModel.bindings.isEmpty)
        XCTAssertNil(store.binding(for: "topic-1"))
        XCTAssertEqual(
            viewModel.errorMessage,
            String(format: "walletConnectErrorDisconnectionFailed".localized, "network")
        )
    }

    private func binding(
        topic: String,
        createdAt: Date = Date(timeIntervalSince1970: 1)
    ) -> WalletConnectSessionBinding {
        WalletConnectSessionBinding(
            topic: topic,
            vaultPubKeyECDSA: "pubkey-\(topic)",
            dappName: "Example \(topic)",
            dappURL: "https://\(topic).example.com",
            dappIconURL: "https://\(topic).example.com/icon.png",
            approvedChains: ["eip155:1", "eip155:137"],
            createdAt: createdAt
        )
    }
}
