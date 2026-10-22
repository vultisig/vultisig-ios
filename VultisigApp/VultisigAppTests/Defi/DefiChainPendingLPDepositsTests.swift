//
//  DefiChainPendingLPDepositsTests.swift
//  VultisigAppTests
//
//  The Maya LP tab loads half-finished paired adds beside the positions. A
//  failed rescan keeps the cards a previous scan found, since their refund
//  timer is still running, but withdraws Complete: nothing confirms MayaChain
//  has not refunded them since.
//

@testable import VultisigApp
import XCTest

@MainActor
final class DefiChainPendingLPDepositsTests: XCTestCase {
    private var storeToken: TestContextToken!
    private var vault: Vault!

    override func setUp() async throws {
        try await super.setUp()
        storeToken = try TestStore.installInMemoryContainer()
        vault = TestStore.makeVault()
        vault.coins = [AddLPFixture.cacao(), AddLPFixture.ether()]
    }

    override func tearDown() async throws {
        vault = nil
        TestStore.restore(storeToken)
        storeToken = nil
        try await super.tearDown()
    }

    private func pending() -> MayaPendingLPDeposit {
        MayaPendingLPDeposit(
            pool: "ETH.ETH",
            pendingCacao: 0,
            pendingAsset: 100_000,
            pendingTxId: "TX",
            pairedAddress: AddLPFixture.mayaAddress,
            blocksUntilRefund: 1000
        )
    }

    private func makeViewModel(_ interactor: StubPendingInteractor) -> DefiChainLPsViewModel {
        DefiChainLPsViewModel(vault: vault, chain: .mayaChain, interactor: interactor)
    }

    func testRefreshPublishesThePendingDeposits() async {
        let interactor = StubPendingInteractor(result: .success(MayaPendingLPScan(deposits: [pending()], isComplete: true)))
        let viewModel = makeViewModel(interactor)

        await viewModel.refresh()

        XCTAssertEqual(viewModel.pendingDeposits.map(\.pool), ["ETH.ETH"])
        XCTAssertTrue(viewModel.canCompletePendingDeposits)
    }

    func testAFailedRescanKeepsTheCardsButWithdrawsComplete() async {
        let interactor = StubPendingInteractor(result: .success(MayaPendingLPScan(deposits: [pending()], isComplete: true)))
        let viewModel = makeViewModel(interactor)
        await viewModel.refresh()

        interactor.result = .failure(StubPendingInteractor.Outage())
        await viewModel.refresh()

        XCTAssertEqual(viewModel.pendingDeposits.count, 1)
        XCTAssertFalse(viewModel.canCompletePendingDeposits)
    }

    func testARescanThatFindsNothingClearsTheCards() async {
        let interactor = StubPendingInteractor(result: .success(MayaPendingLPScan(deposits: [pending()], isComplete: true)))
        let viewModel = makeViewModel(interactor)
        await viewModel.refresh()

        interactor.result = .success(MayaPendingLPScan(deposits: [], isComplete: true))
        await viewModel.refresh()

        XCTAssertTrue(viewModel.pendingDeposits.isEmpty)
    }

    /// A scan that could not read every pool cannot say nothing is pending.
    func testAnIncompleteScanThatFindsNothingKeepsTheEarlierCards() async {
        let interactor = StubPendingInteractor(result: .success(MayaPendingLPScan(deposits: [pending()], isComplete: true)))
        let viewModel = makeViewModel(interactor)
        await viewModel.refresh()

        interactor.result = .success(MayaPendingLPScan(deposits: [], isComplete: false))
        await viewModel.refresh()

        XCTAssertEqual(viewModel.pendingDeposits.count, 1)
        XCTAssertFalse(viewModel.canCompletePendingDeposits)
    }

    func testAnIncompleteScanKeepsCardsForPoolsItDidNotRereadAndRefreshesTheRest() async {
        var other = pending()
        other = MayaPendingLPDeposit(
            pool: "BTC.BTC", pendingCacao: 5, pendingAsset: 0, pendingTxId: "T2",
            pairedAddress: "bc1q", blocksUntilRefund: 10
        )
        let interactor = StubPendingInteractor(result: .success(MayaPendingLPScan(deposits: [pending(), other], isComplete: true)))
        let viewModel = makeViewModel(interactor)
        await viewModel.refresh()

        var refreshed = pending()
        refreshed.blocksUntilRefund = 5
        interactor.result = .success(MayaPendingLPScan(deposits: [refreshed], isComplete: false))
        await viewModel.refresh()

        XCTAssertEqual(viewModel.pendingDeposits.map(\.pool), ["ETH.ETH", "BTC.BTC"])
        XCTAssertEqual(viewModel.pendingDeposits.first?.blocksUntilRefund, 5)
        XCTAssertFalse(viewModel.canCompletePendingDeposits)
    }

    func testAnotherVaultDoesNotInheritThePendingCards() async {
        let interactor = StubPendingInteractor(result: .success(MayaPendingLPScan(deposits: [pending()], isComplete: true)))
        let viewModel = makeViewModel(interactor)
        await viewModel.refresh()

        let other = TestStore.makeVault(pubKey: "another-vault")
        viewModel.update(vault: other)

        XCTAssertTrue(viewModel.pendingDeposits.isEmpty)
    }

    func testAnInteractorWithNoPendingSupportLeavesTheListEmpty() async {
        let viewModel = DefiChainLPsViewModel(vault: vault, chain: .thorChain, interactor: MockLPsInteractor())
        await viewModel.refresh()
        XCTAssertTrue(viewModel.pendingDeposits.isEmpty)
    }
}

final class StubPendingInteractor: LPsInteractor, PendingLPDepositsProviding, @unchecked Sendable {
    struct Outage: Error {}

    var result: Result<MayaPendingLPScan, Error>

    init(result: Result<MayaPendingLPScan, Error>) {
        self.result = result
    }

    func fetchLPPositions(vault _: Vault) async -> [LPPositionData] { [] } // swiftlint:disable:this async_without_await

    func fetchPendingLPDeposits(vault _: Vault) async throws -> MayaPendingLPScan { // swiftlint:disable:this async_without_await
        try result.get()
    }
}
