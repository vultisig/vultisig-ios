//
//  UnbondMayaTransactionViewModelTests.swift
//  VultisigAppTests
//
//  ⚠️ These tests exist for the UNBOND CEILING — the bonded-unit figure the
//  form validates the typed LP units against.
//
//  The ceiling belongs to one (node, pool) pair. The units it vouches for
//  travel in the signed memo's LPUNITS field, so a ceiling left over from a
//  position the user has moved off is not a stale label: it is the only thing
//  standing between a typed figure and a memo that spends against a position
//  it was never measured for.
//

@testable import VultisigApp
import SwiftData
import XCTest

@MainActor
final class UnbondMayaTransactionViewModelTests: XCTestCase {
    /// Real MayaChain bech32 addresses, because `AddressValidator` decodes them
    /// for real — placeholders would leave the address field invalid and the
    /// assertions below would pass for the wrong reason.
    private static let nodeAddress = "maya18altpx2gwt4c4ejr5uzda4kyzsudyn9q5dhl9c"
    private static let otherNodeAddress = "maya1v4ltpx2gwt4c4ejr5uzda4kyzsudyn9qfdm5wx"

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

    /// Guards the fixtures themselves. Every "must refuse" assertion below
    /// would also hold if these addresses simply failed to parse.
    func testBothFixtureAddressesAreRealMayaAddresses() {
        XCTAssertTrue(AddressService.validateAddress(address: Self.nodeAddress, chain: .mayaChain))
        XCTAssertTrue(AddressService.validateAddress(address: Self.otherNodeAddress, chain: .mayaChain))
        XCTAssertNotEqual(Self.nodeAddress, Self.otherNodeAddress)
    }

    // MARK: - The asset switch

    /// The regression: pool A's ceiling surviving a switch to pool B.
    ///
    /// The address is never validated, so no request goes out and the view
    /// model sits in exactly the window the bug lives in — B selected, B's
    /// figure not back yet. A's limit must already be gone by then, not merely
    /// overwritten whenever B answers.
    func testAssetSwitchDropsThePreviousAssetsCeiling() {
        let viewModel = makeViewModel()
        viewModel.onLoad()

        viewModel.addressViewModel.field.value = Self.nodeAddress
        viewModel.selectedAsset = Self.poolA
        pretendCeilingLanded(viewModel, node: Self.nodeAddress, asset: Self.poolA, units: "1000")
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
    /// and B's not yet known, no memo may be built. 900 is within A's 1000 and
    /// would otherwise sail through the generic validators.
    func testAssetSwitchCannotBuildAgainstThePreviousAssetsLimit() {
        let viewModel = makeViewModel()
        viewModel.onLoad()

        viewModel.addressViewModel.field.value = Self.nodeAddress
        viewModel.selectedAsset = Self.poolA
        pretendCeilingLanded(viewModel, node: Self.nodeAddress, asset: Self.poolA, units: "1000")
        viewModel.lpUnitsField.value = "900"

        viewModel.selectedAsset = Self.poolB

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

        viewModel.addressViewModel.field.value = Self.nodeAddress
        viewModel.selectedAsset = Self.poolA
        pretendCeilingLanded(viewModel, node: Self.nodeAddress, asset: Self.poolA, units: "1000")

        viewModel.selectedAsset = Self.poolB
        pretendCeilingLanded(viewModel, node: Self.nodeAddress, asset: Self.poolB, units: "500")

        viewModel.lpUnitsField.value = "900"
        XCTAssertNil(viewModel.transactionBuilder, "900 exceeds B's 500 and must be refused")

        viewModel.lpUnitsField.value = "400"
        let builder = viewModel.transactionBuilder as? BondMayaTransactionBuilder
        XCTAssertEqual(builder?.memo, "UNBOND:BTC.BTC:400:\(Self.nodeAddress)")
    }

    // MARK: - The node switch

    /// The node reaches the fetch through a debounce, so for the length of it
    /// the address field already reads the pasted node while the ceiling still
    /// describes the previous one — and the memo is assembled from the field.
    /// Continuing in that window must not sign the new node's memo against the
    /// old node's limit.
    func testNodeSwitchCannotBuildAgainstThePreviousNodesCeiling() {
        let viewModel = makeViewModel()
        viewModel.onLoad()

        viewModel.addressViewModel.field.value = Self.nodeAddress
        viewModel.selectedAsset = Self.poolA
        pretendCeilingLanded(viewModel, node: Self.nodeAddress, asset: Self.poolA, units: "1000")
        viewModel.lpUnitsField.value = "900"

        XCTAssertNotNil(
            viewModel.transactionBuilder,
            "baseline: 900 is a valid unbond on the node the ceiling was measured on"
        )

        viewModel.addressViewModel.field.value = Self.otherNodeAddress

        XCTAssertNil(
            viewModel.transactionBuilder,
            "the memo would name the pasted node while 900 was measured on the previous one"
        )
    }

    // MARK: - The ceiling carries its own scope

    /// The guard asks the ceiling which node it describes rather than trusting
    /// that a fetch must have run for the current one.
    func testBuilderRefusesACeilingMeasuredOnAnotherNode() {
        let viewModel = makeViewModel()
        viewModel.onLoad()

        viewModel.addressViewModel.field.value = Self.nodeAddress
        viewModel.selectedAsset = Self.poolA
        pretendCeilingLanded(viewModel, node: Self.otherNodeAddress, asset: Self.poolA, units: "1000")
        viewModel.lpUnitsField.value = "900"

        XCTAssertNil(viewModel.transactionBuilder, "that 1000 belongs to a different node")
    }

    /// Same question for the pool.
    func testBuilderRefusesACeilingMeasuredOnAnotherPool() {
        let viewModel = makeViewModel()
        viewModel.onLoad()

        viewModel.addressViewModel.field.value = Self.nodeAddress
        viewModel.selectedAsset = Self.poolB
        pretendCeilingLanded(viewModel, node: Self.nodeAddress, asset: Self.poolA, units: "1000")
        viewModel.lpUnitsField.value = "900"

        XCTAssertNil(viewModel.transactionBuilder, "that 1000 belongs to a different pool")
    }

    /// A form that never learned a ceiling has only `RequiredValidator` and
    /// `IntValidator` on the field, both of which any integer satisfies. The
    /// builder has to ask for the ceiling itself.
    func testBuilderRefusesWhenNoCeilingWasEverLearned() {
        let viewModel = makeViewModel()
        viewModel.onLoad()

        viewModel.addressViewModel.field.value = Self.nodeAddress
        viewModel.selectedAsset = Self.poolB
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

    /// Stands in for the network round trip, which the view model reaches
    /// through a non-injectable `MayaChainAPIService`. Mirrors what the success
    /// branch publishes: the scoped ceiling and the validator enforcing it.
    ///
    /// Call it AFTER the address and the asset are in place — both of those
    /// publish, and the publication is what clears the ceiling, so a figure
    /// installed first would be wiped by the very selection it describes.
    private func pretendCeilingLanded(
        _ viewModel: UnbondMayaTransactionViewModel,
        node: String,
        asset: THORChainAsset,
        units: String
    ) {
        viewModel.bondedUnitsCeiling = UnbondMayaTransactionViewModel.BondedUnitsCeiling(
            nodeAddress: node,
            asset: asset,
            units: units
        )
        viewModel.lpUnitsField.validators += [LPUnitsValidator(availableUnits: units)]
    }
}
