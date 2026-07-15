//
//  LimitOrdersTabFilterTests.swift
//  VultisigAppTests
//
//  Pins the Limit Orders tab's filtering.
//
//  The tab exists because nothing else on a row can identify a limit order: a
//  resting `=<` order and a genuine THORChain MARKET swap both carry
//  `swapProvider == "THORChain"`. `TransactionHistoryType.limit` is the only
//  thing that separates them, and these tests are what stop the two collapsing
//  back together.
//
//  The done-screen banner already tells users their orders are "in Transaction
//  History under the Limit Orders tab", so a row that filters into the wrong
//  tab is a promise broken.
//

import XCTest
@testable import VultisigApp

@MainActor
final class LimitOrdersTabFilterTests: XCTestCase {

    // MARK: - Tab presence and order

    func testLimitOrdersTabExistsBetweenSwapsAndSend() {
        // Declaration order drives the segmented control (`allCases`).
        XCTAssertEqual(
            TransactionHistoryTab.allCases,
            [.overview, .swaps, .limitOrders, .send]
        )
    }

    func testLimitOrdersTabTitleMatchesTheBannerThatPromisesIt() {
        // The done screen says "…under the Limit Orders tab" using this same
        // key. If they drift, the app points at a tab by a name it doesn't use.
        XCTAssertEqual(TransactionHistoryTab.limitOrders.title, "limitSwap.done.bannerTitle".localized)
        XCTAssertFalse(TransactionHistoryTab.limitOrders.title.isEmpty)
    }

    // MARK: - Filtering

    func testLimitTabShowsOnlyLimitOrders() {
        let vm = makeViewModel()
        let limit = makeRow(type: .limit, hash: "0xlimit")
        vm.transactions = [
            limit,
            makeRow(type: .swap, hash: "0xswap"),
            makeRow(type: .send, hash: "0xsend"),
            makeRow(type: .approve, hash: "0xapprove")
        ]

        vm.selectedTab = .limitOrders

        XCTAssertEqual(vm.filteredTransactions.map(\.txHash), [limit.txHash])
    }

    /// The regression that motivates the whole type. A THORChain MARKET swap
    /// carries the same provider string as an order.
    func testThorchainMarketSwapDoesNotLeakIntoTheLimitTab() {
        let vm = makeViewModel()
        vm.transactions = [makeRow(type: .swap, hash: "0xmarket", provider: "THORChain")]

        vm.selectedTab = .limitOrders

        XCTAssertTrue(
            vm.filteredTransactions.isEmpty,
            "A THORChain market swap is not a limit order, despite the identical provider"
        )
    }

    func testSwapsTabExcludesLimitOrders() {
        // `.swap` means a swap that executed; `.limit` means an order that may
        // never execute. They are not the same list.
        let vm = makeViewModel()
        let swap = makeRow(type: .swap, hash: "0xswap")
        vm.transactions = [swap, makeRow(type: .limit, hash: "0xlimit")]

        vm.selectedTab = .swaps

        XCTAssertEqual(vm.filteredTransactions.map(\.txHash), [swap.txHash])
    }

    func testSendTabExcludesLimitOrders() {
        // Native-source co-signer orders used to be recorded as send rows —
        // this is what stops them landing back in the Send tab.
        let vm = makeViewModel()
        vm.transactions = [makeRow(type: .limit, hash: "0xlimit")]

        vm.selectedTab = .send

        XCTAssertTrue(vm.filteredTransactions.isEmpty)
    }

    /// The Overview tab is unfiltered — which is the reason an order must exist
    /// as a history row at all, not merely as a `LimitOrder`.
    func testOverviewTabIncludesLimitOrders() {
        let vm = makeViewModel()
        vm.transactions = [makeRow(type: .limit, hash: "0xlimit"), makeRow(type: .swap, hash: "0xswap")]

        vm.selectedTab = .overview

        XCTAssertEqual(vm.filteredTransactions.count, 2)
    }

    // MARK: - All states share the one tab

    /// No status sectioning and no "Active" header: resting, filled, expired
    /// and cancelled orders all live here together, with the existing date
    /// grouping and the status on the card.
    func testLimitTabShowsOrdersInEveryState() {
        let vm = makeViewModel()
        vm.transactions = [
            makeRow(type: .limit, hash: "0xresting", status: .inProgress),
            makeRow(type: .limit, hash: "0xfilled", status: .successful),
            makeRow(type: .limit, hash: "0xclosed", status: .error)
        ]

        vm.selectedTab = .limitOrders

        XCTAssertEqual(vm.filteredTransactions.count, 3, "Every order belongs in the tab, whatever its state")
    }

    // MARK: - Joining rows to orders

    func testLimitOrderLookupIsCaseInsensitiveOnTheHash() {
        // Hex case is not semantic, and the casing a row was broadcast under
        // needn't match what the order table stored.
        let vm = makeViewModel()
        vm.limitOrdersByTxHash = ["0XABC": makeDetails()]

        XCTAssertNotNil(vm.limitOrder(for: makeRow(type: .limit, hash: "0xabc")))
    }

    func testNonLimitRowsNeverResolveAnOrder() {
        let vm = makeViewModel()
        vm.limitOrdersByTxHash = ["0XABC": makeDetails()]

        XCTAssertNil(vm.limitOrder(for: makeRow(type: .swap, hash: "0xabc")))
        XCTAssertNil(vm.limitOrder(for: makeRow(type: .send, hash: "0xabc")))
    }

    /// A co-signer never persists a `LimitOrder`, so the row must render
    /// without one rather than failing to resolve.
    func testLimitRowWithoutAnOrderRecordResolvesToNil() {
        let vm = makeViewModel()
        XCTAssertNil(vm.limitOrder(for: makeRow(type: .limit, hash: "0xunknown")))
    }

    // MARK: - Fixtures

    private func makeViewModel() -> TransactionHistoryViewModel {
        TransactionHistoryViewModel(pubKeyECDSA: "vault-pub", vaultName: "Test Vault", chainFilter: nil)
    }

    private func makeDetails() -> LimitOrderDetails {
        LimitOrderDetails(
            id: "0xabc_vault-pub",
            inboundTxHash: "0xabc",
            sourceAsset: "THOR.RUNE",
            targetAsset: "BTC.BTC",
            targetPrice: 15,
            expiryBlocks: 7200,
            createdAt: Date(),
            status: .pending,
            minOutputOverride: nil,
            fill: .unobserved,
            expiry: nil
        )
    }

    private func makeRow(
        type: TransactionHistoryType,
        hash: String,
        status: TransactionHistoryStatus = .inProgress,
        provider: String? = "THORChain"
    ) -> TransactionHistoryData {
        TransactionHistoryData(
            id: UUID(),
            txHash: hash,
            approveTxHash: nil,
            pubKeyECDSA: "vault-pub",
            type: type,
            status: status,
            chainRawValue: "THORChain",
            coinTicker: "RUNE",
            coinLogo: "rune",
            coinChainLogo: nil,
            amountCrypto: "1000",
            amountFiat: "1200",
            fromAddress: "thor1from",
            toAddress: "thor1to",
            toCoinTicker: "BTC",
            toCoinLogo: "btc",
            toCoinChainLogo: nil,
            toAmountCrypto: "0.0125",
            toAmountFiat: "1200",
            swapProvider: provider,
            feeCrypto: "0.02",
            feeFiat: "0.05",
            network: "THORChain",
            explorerLink: "https://runescan.io/tx/\(hash)",
            createdAt: Date(),
            completedAt: nil,
            estimatedTime: nil,
            errorMessage: nil,
            swapTracking: type == .limit
                ? THORChainLimitTrackingService.metadata(broadcastHash: hash, sourceChain: .thorChain)
                : nil
        )
    }
}
