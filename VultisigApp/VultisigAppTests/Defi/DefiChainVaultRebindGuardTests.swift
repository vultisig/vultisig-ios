//
//  DefiChainVaultRebindGuardTests.swift
//  VultisigAppTests
//
//  A DeFi refresh must apply nothing once the screen has switched vault under it.
//
//  `DefiChainMainScreen` builds its view models once and rebinds them through
//  `update(vault:)` when the user switches vault, so a `refresh()` already
//  suspended on a network `await` resumes into a view model bound to a different
//  vault. Without a guard at the apply site it publishes — and, for stake and
//  LPs, writes into SwiftData against — the vault it did NOT fetch for.
//
//  Each test holds the interactor's fetch open on a `InteractorCallGate`, rebinds the view
//  model while the fetch is provably in flight, then lets the fetch return the
//  FIRST vault's results. The assertions are that the second vault received none
//  of it: nothing published, and nothing persisted under its identity. Asserting
//  only on the published properties would miss the worse half — a wrong row in
//  the store outlives the screen, while a wrong label is repainted by the next
//  refresh.
//

@testable import VultisigApp
import SwiftData
import XCTest

@MainActor
final class DefiChainVaultRebindGuardTests: XCTestCase {
    private var storeToken: TestContextToken!
    private var first: Vault!
    private var second: Vault!

    override func setUp() async throws {
        try await super.setUp()
        storeToken = try TestStore.installInMemoryContainer()
        first = TestStore.makeVault(pubKey: "rebind-guard-one")
        second = TestStore.makeVault(pubKey: "rebind-guard-two")
    }

    override func tearDown() async throws {
        first = nil
        second = nil
        TestStore.restore(storeToken)
        storeToken = nil
        try await super.tearDown()
    }

    // MARK: - Stake

    /// The stake refresh persists its DTOs, so a superseded pass writes one
    /// vault's positions onto another vault's row — the failure that survives a
    /// repaint. It also publishes `actionAvailabilities`, which is what gates the
    /// stake/unstake buttons, so a stale one can offer an action the new vault's
    /// chain has halted.
    func testStakeRefreshAfterVaultSwitchLeavesTheNewVaultUntouched() async {
        let cacao = CoinMeta.make(chain: .mayaChain, ticker: "CACAO")
        first.defiPositions = [DefiPositions(chain: .mayaChain, bonds: [], staking: [cacao], lps: [])]
        second.defiPositions = [DefiPositions(chain: .mayaChain, bonds: [], staking: [cacao], lps: [])]

        let interactor = MockStakeInteractor()
        let gate = InteractorCallGate()
        interactor.gate = gate
        interactor.stub = [
            StakePositionData(coin: cacao, type: .stake, amount: 42, availableToUnstake: 42, apr: 0.05)
        ]
        interactor.actionAvailabilitiesStub = [cacao: .halted]

        let viewModel = DefiChainStakeViewModel(vault: first, chain: .mayaChain, interactor: interactor)
        let refresh = Task { await viewModel.refresh() }

        await gate.waitForArrival()
        viewModel.update(vault: second)
        await gate.open()
        await refresh.value

        XCTAssertTrue(
            second.stakePositions.isEmpty,
            "The DTOs were fetched for the first vault; persisting them here puts one vault's stake on another's row."
        )
        XCTAssertTrue(viewModel.stakePositions.isEmpty)
        XCTAssertEqual(
            viewModel.actionAvailabilities[cacao],
            .checking,
            "Maya availability starts at .checking; the superseded pass must not resolve it to the first vault's answer."
        )
        XCTAssertFalse(
            viewModel.initialLoadingDone,
            "The second vault has not loaded, so the skeleton must stay up rather than reveal an empty list."
        )
    }

    // MARK: - LPs

    /// Same shape as stake: the LP refresh persists, so the wrong-vault write
    /// outlives the screen.
    func testLPRefreshAfterVaultSwitchLeavesTheNewVaultUntouched() async {
        let btc = CoinMeta.make(chain: .bitcoin, ticker: "BTC")
        let rune = CoinMeta.make(chain: .thorChain, ticker: "RUNE")
        first.defiPositions = [DefiPositions(chain: .thorChain, bonds: [], staking: [], lps: [btc])]
        second.defiPositions = [DefiPositions(chain: .thorChain, bonds: [], staking: [], lps: [btc])]

        let interactor = MockLPsInteractor()
        let gate = InteractorCallGate()
        interactor.gate = gate
        interactor.stub = [
            LPPositionData(
                coin1: rune,
                coin1Amount: 100,
                coin2: btc,
                coin2Amount: 1,
                poolName: "BTC.BTC",
                poolUnits: "10",
                apr: 0.05
            )
        ]

        let viewModel = DefiChainLPsViewModel(vault: first, chain: .thorChain, interactor: interactor)
        let refresh = Task { await viewModel.refresh() }

        await gate.waitForArrival()
        viewModel.update(vault: second)
        await gate.open()
        await refresh.value

        XCTAssertTrue(
            second.lpPositions.isEmpty,
            "The DTOs were fetched for the first vault; persisting them here puts one vault's pool share on another's row."
        )
        XCTAssertTrue(viewModel.lpPositions.isEmpty)
        XCTAssertFalse(viewModel.initialLoadingDone)
    }

    // MARK: - Bond

    /// Bond publishes rather than persists. The node lists are the vault-derived
    /// half and must be discarded; `canUnbond` / `canAddBond` are the chain-derived
    /// half — neither interactor call takes a vault, and `chain` is fixed for this
    /// view model's lifetime — so they stay published across the switch. Asserted
    /// both ways here, because a guard drawn around the flags too would withhold
    /// them behind a slow position fetch for every ordinary refresh.
    func testBondRefreshAfterVaultSwitchDiscardsTheFirstVaultsNodesOnly() async {
        let rune = CoinMeta.make(chain: .thorChain, ticker: "RUNE")
        let node = BondNode(coin: rune, address: "thor1node", state: .active)
        // Related to `first`, but the first vault has no `defiPositions` bond
        // entry, so `hasBondPositions` is false and nothing is published before
        // the fetch suspends. Anything published is therefore the superseded pass.
        let position = BondPosition(node: node, amount: 100, apy: 0.1, nextReward: 1, vault: first)

        let interactor = MockBondInteractor()
        let gate = InteractorCallGate()
        interactor.gate = gate
        interactor.stub = (active: [position], available: [node])

        let viewModel = DefiChainBondViewModel(vault: first, chain: .thorChain, interactor: interactor)
        let refresh = Task { await viewModel.refresh() }

        await gate.waitForArrival()
        viewModel.update(vault: second)
        await gate.open()
        await refresh.value

        XCTAssertTrue(
            viewModel.activeBondedNodes.isEmpty,
            "These bonds belong to the first vault; showing them under the second misreports what it holds."
        )
        XCTAssertTrue(viewModel.availableNodes.isEmpty)
        XCTAssertTrue(
            viewModel.canUnbond,
            "A chain capability is not vault state — withholding it would gate the form on an unrelated fetch."
        )
        XCTAssertTrue(viewModel.canAddBond)
    }

    /// The failure path publishes too. `refreshError` drives a user-visible
    /// banner, and the fetch it describes was made for the vault the user has
    /// already left — so a switch must swallow it like any other result.
    func testBondRefreshFailureAfterVaultSwitchPublishesNoError() async {
        let interactor = MockBondInteractor()
        let gate = InteractorCallGate()
        interactor.gate = gate
        interactor.error = MockBondInteractor.StubError.unreachable

        let viewModel = DefiChainBondViewModel(vault: first, chain: .thorChain, interactor: interactor)
        let refresh = Task { await viewModel.refresh() }

        await gate.waitForArrival()
        viewModel.update(vault: second)
        await gate.open()
        await refresh.value

        XCTAssertNil(
            viewModel.refreshError,
            "The failed fetch was the first vault's; the second vault must not inherit its error banner."
        )
    }

    /// The apply guard is not sufficient on its own for bond, because its node
    /// lists are published caches rather than arrays computed off the vault (which
    /// is what makes the stake and LP view models self-correct on a rebind). With
    /// a warm cache and no refresh in flight at all, the switch alone must clear
    /// them — otherwise the new vault renders the previous vault's bonds, and the
    /// `totalBondedBalance` derived from them.
    func testBondRebindReseedsTheNodeListsFromTheNewVault() async {
        let rune = CoinMeta.make(chain: .thorChain, ticker: "RUNE")
        first.defiPositions = [DefiPositions(chain: .thorChain, bonds: [rune], staking: [], lps: [])]
        let node = BondNode(coin: rune, address: "thor1node", state: .active)
        let position = BondPosition(node: node, amount: 100, apy: 0.1, nextReward: 1, vault: first)

        let interactor = MockBondInteractor()
        interactor.stub = (active: [position], available: [node])

        let viewModel = DefiChainBondViewModel(vault: first, chain: .thorChain, interactor: interactor)
        await viewModel.refresh()
        XCTAssertEqual(viewModel.activeBondedNodes.count, 1, "precondition: the first vault's cache is warm")
        XCTAssertEqual(viewModel.availableNodes.count, 1, "precondition: the first vault's cache is warm")

        viewModel.update(vault: second)

        XCTAssertTrue(
            viewModel.activeBondedNodes.isEmpty,
            "The second vault has no bonds; carrying the first vault's over misstates what it holds."
        )
        XCTAssertTrue(
            viewModel.availableNodes.isEmpty,
            "The node list was fetched for the vault the user just left."
        )
    }

    // MARK: - The guard must not block a normal refresh

    /// The other half of the guard: a refresh with no vault switch has to apply
    /// exactly as before. A guard that compared the wrong thing — object identity
    /// across a re-fetched `Vault` instance, say — would pass every test above by
    /// discarding everything, always.
    func testRefreshWithNoVaultSwitchStillAppliesItsResults() async {
        let btc = CoinMeta.make(chain: .bitcoin, ticker: "BTC")
        let rune = CoinMeta.make(chain: .thorChain, ticker: "RUNE")
        first.defiPositions = [DefiPositions(chain: .thorChain, bonds: [], staking: [], lps: [btc])]

        let interactor = MockLPsInteractor()
        let gate = InteractorCallGate()
        interactor.gate = gate
        interactor.stub = [
            LPPositionData(
                coin1: rune,
                coin1Amount: 100,
                coin2: btc,
                coin2Amount: 1,
                poolName: "BTC.BTC",
                poolUnits: "10",
                apr: 0.05
            )
        ]

        let viewModel = DefiChainLPsViewModel(vault: first, chain: .thorChain, interactor: interactor)
        let refresh = Task { await viewModel.refresh() }

        await gate.waitForArrival()
        // Rebound to the same vault — the screen does this on any `vault` change
        // SwiftUI observes, including ones that are not a switch.
        viewModel.update(vault: first)
        await gate.open()
        await refresh.value

        XCTAssertEqual(viewModel.lpPositions.count, 1)
        XCTAssertEqual(viewModel.lpPositions.first?.apr, 0.05)
        XCTAssertTrue(viewModel.initialLoadingDone)
    }
}
