//
//  UnbondMayaTransactionViewModelTests.swift
//  VultisigAppTests
//
//  ⚠️ These tests exist for the UNBOND CEILING — the bonded-unit figure the
//  form validates the typed LP units against.
//
//  The ceiling belongs to one (node, pool) pair. The units it vouches for
//  travel in the signed memo's LPUNITS field, so a ceiling left over from a
//  pool the user has moved off is not a stale label: it is the only thing
//  standing between a typed figure and a memo that spends against a position
//  it was never measured for.
//

@testable import VultisigApp
import SwiftData
import XCTest

@MainActor
final class UnbondMayaTransactionViewModelTests: XCTestCase {
    /// A real MayaChain bech32 address, because `AddressValidator` decodes it
    /// for real — a placeholder would leave the address field invalid and every
    /// assertion below would pass for the wrong reason.
    private static let nodeAddress = "maya18altpx2gwt4c4ejr5uzda4kyzsudyn9q5dhl9c"

    private static let poolA = THORChainAsset(
        thorchainAsset: "MAYA.CACAO",
        asset: CoinMeta.make(chain: .mayaChain, ticker: "CACAO", decimals: 10)
    )
    private static let poolB = THORChainAsset(
        thorchainAsset: "BTC.BTC",
        asset: CoinMeta.make(chain: .bitcoin, ticker: "BTC")
    )

    private var storeToken: TestContextToken!
    private var vault: Vault!

    override func setUp() async throws {
        try await super.setUp()
        storeToken = try TestStore.installInMemoryContainer()
        vault = TestStore.makeVault()
    }

    override func tearDown() async throws {
        vault = nil
        TestStore.restore(storeToken)
        storeToken = nil
        try await super.tearDown()
    }

    // MARK: - The asset switch

    /// The regression: pool A's ceiling surviving a switch to pool B.
    ///
    /// Nothing is typed into the address field, so no request goes out and the
    /// view model sits in exactly the window the bug lives in — B selected, B's
    /// figure not back yet. A's limit must already be gone by then, not merely
    /// overwritten whenever B answers.
    func testAssetSwitchDropsThePreviousAssetsCeiling() {
        let viewModel = makeViewModel()
        viewModel.onLoad()

        selectAndPretendCeilingLanded(viewModel, asset: Self.poolA, units: "1000")
        viewModel.lpUnitsField.value = "900"

        viewModel.selectedAsset = Self.poolB

        XCTAssertNil(
            viewModel.bondedLPUnits,
            "B's ceiling is unknown; A's figure must not stand in for it"
        )
        XCTAssertFalse(
            viewModel.lpUnitsField.validators.contains { $0 is LPUnitsValidator },
            "A's limit must not still be the thing 900 is measured against"
        )
    }

    /// The consequence that actually reaches the chain: with A's ceiling gone
    /// and B's not yet known, no memo may be built at all. 900 is within A's
    /// 1000 and would otherwise sail through the generic validators.
    func testAssetSwitchCannotBuildAgainstThePreviousAssetsLimit() {
        let viewModel = makeViewModel()
        viewModel.onLoad()

        selectAndPretendCeilingLanded(viewModel, asset: Self.poolA, units: "1000")
        viewModel.lpUnitsField.value = "900"

        viewModel.selectedAsset = Self.poolB
        // Filled after the switch on purpose: a valid address here would send
        // B's request, and this is the "continue before it lands" case.
        viewModel.addressViewModel.field.value = Self.nodeAddress

        XCTAssertNil(
            viewModel.transactionBuilder,
            "UNBOND:BTC.BTC:900 was only ever valid for CACAO's position"
        )
    }

    /// And the other side of it, so the guard is not simply "never build":
    /// once B's own ceiling lands, B's own limit is what applies.
    func testBuilderSignsAgainstTheNewAssetsOwnCeiling() {
        let viewModel = makeViewModel()
        viewModel.onLoad()

        selectAndPretendCeilingLanded(viewModel, asset: Self.poolA, units: "1000")
        viewModel.selectedAsset = Self.poolB
        viewModel.addressViewModel.field.value = Self.nodeAddress

        pretendCeilingLanded(viewModel, units: "500")

        viewModel.lpUnitsField.value = "900"
        XCTAssertNil(viewModel.transactionBuilder, "900 exceeds B's 500 and must be refused")

        viewModel.lpUnitsField.value = "400"
        let builder = viewModel.transactionBuilder as? BondMayaTransactionBuilder
        XCTAssertEqual(builder?.memo, "UNBOND:BTC.BTC:400:\(Self.nodeAddress)")
    }

    // MARK: - The ceiling as a precondition

    /// A form that never learned a ceiling has only `RequiredValidator` and
    /// `IntValidator` on the field, both of which any integer satisfies. The
    /// builder has to ask for the ceiling itself.
    func testBuilderRefusesWhenNoCeilingWasEverLearned() {
        let viewModel = makeViewModel()
        viewModel.onLoad()

        viewModel.selectedAsset = Self.poolB
        viewModel.addressViewModel.field.value = Self.nodeAddress
        viewModel.lpUnitsField.value = "900"

        XCTAssertNil(viewModel.bondedLPUnits)
        XCTAssertNil(
            viewModel.transactionBuilder,
            "no memo may be signed for units nothing has vouched for"
        )
    }

    // MARK: - Helpers

    private func makeViewModel() -> UnbondMayaTransactionViewModel {
        UnbondMayaTransactionViewModel(
            coin: Coin(asset: TokensStore.cacao, address: "maya1sender", hexPublicKey: "HexPublicKeyExample"),
            vault: vault,
            initialBondAddress: nil
        )
    }

    /// Selects `asset` and then puts the state a successful bonded-unit fetch
    /// would leave behind. The order matters: selecting publishes, and the
    /// publication is what clears the ceiling, so a figure installed first
    /// would be wiped by the very selection it is meant to describe.
    private func selectAndPretendCeilingLanded(
        _ viewModel: UnbondMayaTransactionViewModel,
        asset: THORChainAsset,
        units: String
    ) {
        viewModel.selectedAsset = asset
        pretendCeilingLanded(viewModel, units: units)
    }

    /// Stands in for the network round trip, which the view model reaches
    /// through a non-injectable `MayaChainAPIService`. Mirrors what the success
    /// branch publishes: the figure and the validator that enforces it.
    private func pretendCeilingLanded(_ viewModel: UnbondMayaTransactionViewModel, units: String) {
        viewModel.bondedLPUnits = units
        viewModel.lpUnitsField.validators += [LPUnitsValidator(availableUnits: units)]
    }
}
