//
//  MergeTransactionViewModelTests.swift
//  VultisigAppTests
//
//  The MERGE form makes two decisions — which catalog token and how much of it
//  — and the token carries both the destination contract and the balance the
//  amount is bounded by. These pin the intersection that builds the picker and
//  the gate that stops an unfunded or unaddressed merge, carrying the
//  form-validity assertions from the deleted `FunctionCallCosmosMergeTests`.
//

import Combine
@testable import VultisigApp
import XCTest

@MainActor
final class MergeTransactionViewModelTests: XCTestCase {

    private static let kujiContract = "thor14hj2tavq8fpesdwxxcu44rty3hh90vhujrvcmstl4zr3txmfvw9s3p2nzy"
    private static let lvnContract = "thor1ltd0maxmte3xf4zshta9j5djrq9cl692ctsp9u5q0p9wss0f5lms7us4yf"

    /// 10 KUJI at 8 dp.
    private static let tenTokens = "1000000000"
    /// 1 LVN at 8 dp.
    private static let oneToken = "100000000"

    private static func makeThorToken(_ ticker: String, rawBalance: String = tenTokens) -> Coin {
        FunctionCallFixture.makeCoin(
            .thorChain,
            ticker: ticker,
            decimals: 8,
            isNative: false,
            rawBalance: rawBalance,
            address: FunctionCallFixture.thorAddress
        )
    }

    private func makeViewModel(
        holdings: [Coin],
        initialDenom: String? = nil
    ) -> MergeTransactionViewModel {
        let rune = FunctionCallFixture.makeRUNE()
        return MergeTransactionViewModel(
            coin: rune,
            vault: FunctionCallFixture.makeVault(coins: [rune] + holdings),
            initialDenom: initialDenom
        )
    }

    /// `setupForm()` publishes validity on the main run loop, so a typed value
    /// settles a turn late. A selection does not — it re-runs the predicate
    /// itself, because it changes the validators rather than the value.
    private func awaitValidForm(_ viewModel: MergeTransactionViewModel, is expected: Bool) async {
        guard viewModel.validForm != expected else { return }
        let settled = XCTestExpectation(description: "validForm becomes \(expected)")
        var cancellable: AnyCancellable?
        cancellable = viewModel.$validForm
            .first(where: { $0 == expected })
            .sink { _ in settled.fulfill() }
        await fulfillment(of: [settled], timeout: 2)
        cancellable?.cancel()
    }

    // MARK: - The token list (catalog ∩ holdings)

    /// Legacy `loadTokens()` walked the catalog in order and kept the entries
    /// the vault held, matching on the denom with `thor.` stripped.
    func testTokenListIsTheCatalogIntersectedWithHoldingsInCatalogOrder() {
        let viewModel = makeViewModel(holdings: [
            Self.makeThorToken("LVN"),
            Self.makeThorToken("KUJI")
        ])

        XCTAssertEqual(viewModel.mergeableAssets.map { $0.token.denom }, ["thor.kuji", "thor.lvn"])
    }

    func testHoldingsOutsideTheCatalogAreNotOffered() {
        let viewModel = makeViewModel(holdings: [
            FunctionCallFixture.makeTCY(),
            FunctionCallFixture.makeRUJI(),
            Self.makeThorToken("KUJI")
        ])

        XCTAssertEqual(viewModel.mergeableAssets.map { $0.token.denom }, ["thor.kuji"])
    }

    /// The intersection is per chain: a KUJI held on Kujira is not a THORChain
    /// merge token, and merging it would address a contract that chain has
    /// never heard of.
    func testACatalogTickerOnAnotherChainIsNotOffered() {
        let viewModel = makeViewModel(holdings: [FunctionCallFixture.makeKUJI()])
        XCTAssertTrue(viewModel.mergeableAssets.isEmpty)
    }

    func testAVaultHoldingNoMergeableTokenOffersNothing() {
        let viewModel = makeViewModel(holdings: [])
        XCTAssertTrue(viewModel.mergeableAssets.isEmpty)
        XCTAssertNil(viewModel.selectedAsset)
    }

    // MARK: - The gate

    func testPristineFormStartsEmptyAndBlocked() {
        let viewModel = makeViewModel(holdings: [Self.makeThorToken("KUJI")])

        // Legacy started at zero for a native source coin; the field starts
        // empty and the label asks for a token.
        XCTAssertEqual(viewModel.amountField.value, "")
        XCTAssertEqual(viewModel.amountLabel, "amountSelectToken".localized)
        XCTAssertFalse(viewModel.validForm)
        XCTAssertNil(viewModel.transactionBuilder)
    }

    /// With no token there is no contract to deposit into, so the gate stays
    /// shut — and Continue has to say why rather than silently no-op.
    func testNoSelectionBlocksTheBuilderAndSurfacesTheReason() async {
        let viewModel = makeViewModel(holdings: [Self.makeThorToken("KUJI")])
        viewModel.onLoad()
        await awaitValidForm(viewModel, is: false)

        XCTAssertNil(viewModel.transactionBuilder)
        XCTAssertNotEqual("selectTokenToMerge".localized, "selectTokenToMerge", "Key must ship in the bundle")
        XCTAssertEqual(viewModel.amountField.error, "selectTokenToMerge".localized)
    }

    /// Carried from the legacy `isFormValid(for:)`: `amount <= balance`.
    func testAmountOverTheSelectedBalanceBlocksTheBuilder() async {
        let viewModel = makeViewModel(holdings: [Self.makeThorToken("KUJI")])
        viewModel.onLoad()
        viewModel.select(asset: viewModel.mergeableAssets[0])

        viewModel.amountField.value = "11"
        await awaitValidForm(viewModel, is: false)

        XCTAssertNil(viewModel.transactionBuilder)
    }

    /// Carried from the legacy `isFormValid(for:)`: `amount > 0`.
    func testZeroAmountBlocksTheBuilder() async {
        let viewModel = makeViewModel(holdings: [Self.makeThorToken("KUJI")])
        viewModel.onLoad()
        viewModel.select(asset: viewModel.mergeableAssets[0])

        viewModel.amountField.value = "0"
        await awaitValidForm(viewModel, is: false)

        XCTAssertNil(viewModel.transactionBuilder)
    }

    /// The validator's ceiling is a copy taken when the token was picked;
    /// legacy compared against the balance read at submit. A balance that drops
    /// while the form is open has to fail closed.
    func testABalanceThatDroppedBelowTheEnteredAmountBlocksTheBuilder() {
        let kuji = Self.makeThorToken("KUJI", rawBalance: Self.tenTokens)
        let viewModel = makeViewModel(holdings: [kuji])
        viewModel.onLoad()
        viewModel.select(asset: viewModel.mergeableAssets[0])
        XCTAssertNotNil(viewModel.transactionBuilder)

        kuji.rawBalance = Self.oneToken

        XCTAssertNil(viewModel.transactionBuilder, "10 KUJI can no longer be merged from a 1 KUJI balance")
    }

    /// The mirror image: legacy read the balance at submit in both directions,
    /// so a balance that grew must stop rejecting an affordable amount.
    func testABalanceThatGrewAboveTheEnteredAmountUnblocksTheBuilder() {
        let kuji = Self.makeThorToken("KUJI", rawBalance: Self.oneToken)
        let viewModel = makeViewModel(holdings: [kuji])
        viewModel.onLoad()
        viewModel.select(asset: viewModel.mergeableAssets[0])

        viewModel.amountField.value = "5"
        XCTAssertNil(viewModel.transactionBuilder, "5 exceeds the 1 KUJI balance the form opened with")

        kuji.rawBalance = Self.tenTokens

        XCTAssertEqual((viewModel.transactionBuilder as? MergeTransactionBuilder)?.amount, "5")
    }

    /// A catalog entry with no contract has nowhere to deposit — legacy's gate
    /// required a non-empty destination for the same reason.
    func testADescriptorWithoutAContractBlocksTheBuilder() {
        let kuji = Self.makeThorToken("KUJI")
        let viewModel = makeViewModel(holdings: [kuji])
        viewModel.onLoad()

        viewModel.select(asset: ThorchainMergeAsset(
            token: TokenMergeInfo(denom: "thor.kuji", wasmContractAddress: ""),
            coin: kuji
        ))

        XCTAssertNil(viewModel.transactionBuilder)
    }

    // MARK: - Selection

    func testSelectingATokenPrefillsTheBalanceAndResolvesTheContract() {
        let viewModel = makeViewModel(holdings: [Self.makeThorToken("KUJI")])
        viewModel.onLoad()
        viewModel.select(asset: viewModel.mergeableAssets[0])

        // Legacy pre-filled the selected token's whole balance. Asserted by
        // parsing it back rather than by string, since the field is written
        // through the same locale-aware formatter the legacy amount used.
        let prefilled = viewModel.amountField.value.parseInput() ?? .zero
        XCTAssertEqual(prefilled, viewModel.mergeableAssets[0].coin.balanceDecimal)
        XCTAssertTrue(viewModel.validForm)

        let builder = viewModel.transactionBuilder as? MergeTransactionBuilder
        XCTAssertEqual(builder?.memo, "merge:THOR.KUJI")
        XCTAssertEqual(builder?.contractAddress, Self.kujiContract)
        XCTAssertEqual(builder?.coin.ticker, "KUJI")
    }

    /// The transaction is built against the picked token, not the intent's
    /// anchor coin — and it carries the legacy memo dictionary.
    func testBuiltTransactionSpendsThePickedTokenNotTheAnchorCoin() {
        let kuji = Self.makeThorToken("KUJI")
        let rune = FunctionCallFixture.makeRUNE()
        let vault = FunctionCallFixture.makeVault(coins: [rune, kuji])
        let viewModel = MergeTransactionViewModel(coin: rune, vault: vault, initialDenom: nil)
        viewModel.onLoad()
        viewModel.select(asset: viewModel.mergeableAssets[0])

        guard let builder = viewModel.transactionBuilder else {
            return XCTFail("A funded selection must produce a builder")
        }
        let tx = builder.buildSendTransaction(vault: vault)

        XCTAssertEqual(tx.coin.ticker, "KUJI")
        XCTAssertEqual(tx.transactionType, .thorMerge)
        XCTAssertEqual(tx.toAddress, Self.kujiContract)
        XCTAssertEqual(tx.memoFunctionDictionary["destinationAddress"], Self.kujiContract)
        XCTAssertEqual(tx.memoFunctionDictionary["memo"], "merge:THOR.KUJI")
    }

    /// Switching tokens has to move the contract **and** the balance ceiling
    /// together; leaving the previous token's ceiling in place would let a
    /// 10-KUJI amount through on a 1-LVN balance.
    func testSwitchingTokensRepointsTheContractAndTheBalanceBound() async {
        let viewModel = makeViewModel(holdings: [
            Self.makeThorToken("KUJI", rawBalance: Self.tenTokens),
            Self.makeThorToken("LVN", rawBalance: Self.oneToken)
        ])
        viewModel.onLoad()

        viewModel.select(asset: viewModel.mergeableAssets[0])
        XCTAssertEqual((viewModel.transactionBuilder as? MergeTransactionBuilder)?.contractAddress, Self.kujiContract)

        viewModel.select(asset: viewModel.mergeableAssets[1])
        let builder = viewModel.transactionBuilder as? MergeTransactionBuilder
        XCTAssertEqual(builder?.memo, "merge:THOR.LVN")
        XCTAssertEqual(builder?.contractAddress, Self.lvnContract)

        viewModel.amountField.value = "5"
        await awaitValidForm(viewModel, is: false)
        XCTAssertNil(viewModel.transactionBuilder, "5 exceeds the LVN balance the form just switched to")
    }

    func testAmountLabelShowsTheSelectedTokensBalance() {
        let viewModel = makeViewModel(holdings: [Self.makeThorToken("KUJI")])
        viewModel.onLoad()
        viewModel.select(asset: viewModel.mergeableAssets[0])

        XCTAssertTrue(viewModel.amountLabel.contains("KUJI"))
        XCTAssertNotEqual(viewModel.amountLabel, "amountSelectToken".localized)
    }

    // MARK: - Pre-selection

    func testInitialDenomPreselectsItsTokenCaseInsensitively() {
        let viewModel = makeViewModel(
            holdings: [Self.makeThorToken("KUJI"), Self.makeThorToken("LVN")],
            initialDenom: "THOR.LVN"
        )
        viewModel.onLoad()

        XCTAssertEqual(viewModel.selectedAsset?.token.denom, "thor.lvn")
        XCTAssertEqual((viewModel.transactionBuilder as? MergeTransactionBuilder)?.memo, "merge:THOR.LVN")
    }

    func testInitialDenomTheVaultDoesNotHoldIsIgnored() {
        let viewModel = makeViewModel(
            holdings: [Self.makeThorToken("KUJI")],
            initialDenom: "thor.fuzn"
        )
        viewModel.onLoad()

        XCTAssertNil(viewModel.selectedAsset, "The picker only offers holdings, so there is nothing to open on")
        XCTAssertNil(viewModel.transactionBuilder)
    }

    func testNoInitialDenomLeavesTheFormUnselected() {
        let viewModel = makeViewModel(holdings: [Self.makeThorToken("KUJI")])
        viewModel.onLoad()

        XCTAssertNil(viewModel.selectedAsset)
        XCTAssertEqual(viewModel.amountField.value, "")
    }

    // MARK: - Picker plumbing

    /// The screen hands back the picker's value type; resolving it to the
    /// descriptor that carries the contract is the view model's job.
    func testSelectingByPickerAssetResolvesTheDescriptor() {
        let viewModel = makeViewModel(holdings: [Self.makeThorToken("KUJI"), Self.makeThorToken("LVN")])
        viewModel.onLoad()

        viewModel.select(pickerAsset: viewModel.mergeableAssets[1].pickerAsset)

        XCTAssertEqual(viewModel.selectedAsset?.token.denom, "thor.lvn")
        XCTAssertEqual(viewModel.selectedAsset?.contractAddress, Self.lvnContract)
    }

    func testSelectingAnUnknownPickerAssetIsIgnored() {
        let viewModel = makeViewModel(holdings: [Self.makeThorToken("KUJI")])
        viewModel.onLoad()

        viewModel.select(pickerAsset: THORChainAsset(thorchainAsset: "THOR.FUZN", asset: .example))

        XCTAssertNil(viewModel.selectedAsset)
    }

    func testPickerAssetsMirrorTheMergeableList() async throws {
        let viewModel = makeViewModel(holdings: [Self.makeThorToken("KUJI"), Self.makeThorToken("LVN")])
        // `fetchAssets()` is throwing so the Maya forms can tell a failed fetch
        // from an empty one; the merge catalog is local and cannot fail.
        let assets = try await viewModel.assetsDataSource.fetchAssets()

        XCTAssertEqual(assets.map { $0.thorchainAsset }, ["THOR.KUJI", "THOR.LVN"])
        XCTAssertEqual(assets.map { $0.asset.ticker }, ["KUJI", "LVN"])
    }
}
