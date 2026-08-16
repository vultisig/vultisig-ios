//
//  SecuredWithdrawTransactionViewModelTests.swift
//  VultisigAppTests
//
//  Validation gate for the THORChain `SECURE-` form. `transactionBuilder`
//  returning nil is the enforcement — `FormScreen` does not disable Continue on
//  `validForm` — so every rejection is asserted through the builder, not
//  through a flag.
//
//  Three properties here are the reason this migration exists: the destination
//  is validated against the secured asset's own L1 chain (legacy accepted any
//  string over ten characters), the outbound-fee floor actually blocks, and a
//  slow threshold reply for a previously selected asset can no longer land on
//  the current one.
//

import Combine
@testable import VultisigApp
import XCTest

@MainActor
final class SecuredWithdrawTransactionViewModelTests: XCTestCase {

    // Real addresses: the validators run WalletCore, so fixtures have to be
    // genuinely valid on their chain or every assertion below passes for the
    // wrong reason.
    private static let btcAddress = "bc1qxy2kgdygjrsqtzq2n0yrf2493p83kkfjhx0wlh"
    private static let otherBtcAddress = "bc1qar0srrr7xfkvy5l643lydnw9re59gtzzwf5mdq"
    private static let ethAddress = "0x742d35cc6634c0532925a3b844bc454e4438f44e"
    private static let thorAddress = "thor1prxy0sufdqfve6ygkwu9gswe60cle8gy02ex2w"

    private static let btcDenom = "btc-btc"
    private static let ethDenom = "eth-eth"

    /// `(0.0001 BTC × 100_000) × 1.2 ÷ 100_000` — the legacy formula, worked
    /// through in the fiat unit the two sides of the comparison share.
    private static let btcMinimum = Decimal(string: "0.00012")!
    /// `(0.002 ETH × 2_000) × 1.2 ÷ 2_000`.
    private static let ethMinimum = Decimal(string: "0.0024")!

    // MARK: - Fixtures

    private static func makeSecuredCoin(denom: String, rawBalance: String) -> Coin {
        let meta = SecuredAssetMapper.coinMeta(forDenom: denom)
        let coin = Coin(asset: meta, address: thorAddress, hexPublicKey: "")
        coin.rawBalance = rawBalance
        return coin
    }

    private static func makeNativeCoin(_ chain: Chain, ticker: String, address: String) -> Coin {
        let coin = Coin(
            asset: CoinMeta(
                chain: chain,
                ticker: ticker,
                logo: "",
                decimals: 8,
                priceProviderId: ticker.lowercased(),
                contractAddress: "",
                isNativeToken: true
            ),
            address: address,
            hexPublicKey: ""
        )
        coin.rawBalance = "100000000"
        return coin
    }

    private struct Fixture {
        let viewModel: SecuredWithdrawTransactionViewModel
        let stub: StubSecuredWithdrawDataSource
        let vault: Vault
        let securedBTC: Coin
        let securedETH: Coin
    }

    /// A vault holding RUNE, native BTC and native ETH, plus the two secured
    /// twins. The secured coins are pre-added so `CoinService.addIfNeeded`
    /// short-circuits on `vault.coin(for:)` — deriving a new address needs real
    /// TSS material, which a fixture vault does not have.
    private func makeFixture(
        includeNativeBTC: Bool = true,
        securedBTCBalance: String = "100000000",
        securedETHBalance: String = "1000000000"
    ) -> Fixture {
        let rune = Coin(
            asset: CoinMeta(
                chain: .thorChain,
                ticker: "RUNE",
                logo: "",
                decimals: 8,
                priceProviderId: "thorchain",
                contractAddress: "",
                isNativeToken: true
            ),
            address: Self.thorAddress,
            hexPublicKey: ""
        )
        rune.rawBalance = "100000000000"

        let securedBTC = Self.makeSecuredCoin(denom: Self.btcDenom, rawBalance: securedBTCBalance)
        let securedETH = Self.makeSecuredCoin(denom: Self.ethDenom, rawBalance: securedETHBalance)

        var coins: [Coin] = [rune, securedBTC, securedETH]
        if includeNativeBTC {
            coins.append(Self.makeNativeCoin(.bitcoin, ticker: "BTC", address: Self.btcAddress))
        }
        coins.append(Self.makeNativeCoin(.ethereum, ticker: "ETH", address: Self.ethAddress))

        let vault = FunctionActionFixture.makeVault(coins: coins)

        let stub = StubSecuredWithdrawDataSource()
        stub.balances = [
            CosmosBalance(denom: "rune", amount: "100000000000"),
            CosmosBalance(denom: "x/ruji", amount: "500000000"),
            CosmosBalance(denom: Self.ethDenom, amount: securedETHBalance),
            CosmosBalance(denom: Self.btcDenom, amount: securedBTCBalance)
        ]
        stub.outboundFees = ["BTC": Decimal(string: "0.0001")!, "ETH": Decimal(string: "0.002")!]
        stub.fiatRates = [
            "BTC": 100_000,
            "ETH": 2_000
        ]

        return Fixture(
            viewModel: SecuredWithdrawTransactionViewModel(coin: rune, vault: vault, dataSource: stub),
            stub: stub,
            vault: vault,
            securedBTC: securedBTC,
            securedETH: securedETH
        )
    }

    // MARK: - Waiting helpers

    /// `setupForm()` publishes validity on the main run loop, so the flag
    /// settles a turn after the value is written.
    private func awaitValidForm(
        _ viewModel: SecuredWithdrawTransactionViewModel,
        is expected: Bool
    ) async {
        guard viewModel.validForm != expected else { return }
        let settled = XCTestExpectation(description: "validForm becomes \(expected)")
        var cancellable: AnyCancellable?
        cancellable = viewModel.$validForm
            .first(where: { $0 == expected })
            .sink { _ in settled.fulfill() }
        await fulfillment(of: [settled], timeout: 2)
        cancellable?.cancel()
    }

    private func awaitAssets(_ viewModel: SecuredWithdrawTransactionViewModel) async {
        guard viewModel.isLoadingAssets else { return }
        let settled = XCTestExpectation(description: "assets load")
        var cancellable: AnyCancellable?
        cancellable = viewModel.$isLoadingAssets
            .first(where: { $0 == false })
            .sink { _ in settled.fulfill() }
        await fulfillment(of: [settled], timeout: 2)
        cancellable?.cancel()
    }

    private func awaitThreshold(
        _ viewModel: SecuredWithdrawTransactionViewModel,
        is expected: OutboundFeeThreshold
    ) async {
        guard viewModel.outboundFeeThreshold != expected else { return }
        let settled = XCTestExpectation(description: "threshold becomes \(expected)")
        var cancellable: AnyCancellable?
        cancellable = viewModel.$outboundFeeThreshold
            .first(where: { $0 == expected })
            .sink { _ in settled.fulfill() }
        await fulfillment(of: [settled], timeout: 2)
        cancellable?.cancel()
    }

    private func awaitMinimum(
        _ viewModel: SecuredWithdrawTransactionViewModel,
        is expected: Decimal
    ) async {
        await awaitThreshold(viewModel, is: .known(expected))
    }

    /// Gives the form's validity pipeline a run-loop turn without asserting a
    /// transition — for cases whose expected result is the value already held.
    private func settle() async {
        let turned = XCTestExpectation(description: "run loop turn")
        RunLoop.main.perform { turned.fulfill() }
        await fulfillment(of: [turned], timeout: 2)
    }

    private func select(
        _ denom: String,
        on viewModel: SecuredWithdrawTransactionViewModel
    ) {
        guard let asset = viewModel.availableAssets.first(where: { $0.thorchainAsset == denom }) else {
            return XCTFail("\(denom) must be offered by the picker")
        }
        viewModel.selectedAsset = asset
        viewModel.onAssetSelected()
    }

    /// Loads the picker and selects `denom`, with its threshold already settled.
    private func loadedFixture(
        selecting denom: String = SecuredWithdrawTransactionViewModelTests.btcDenom,
        minimum: Decimal? = SecuredWithdrawTransactionViewModelTests.btcMinimum,
        includeNativeBTC: Bool = true
    ) async -> Fixture {
        let fixture = makeFixture(includeNativeBTC: includeNativeBTC)
        fixture.viewModel.onLoad()
        await awaitAssets(fixture.viewModel)
        select(denom, on: fixture.viewModel)
        if let minimum {
            await awaitMinimum(fixture.viewModel, is: minimum)
        }
        return fixture
    }

    // MARK: - Nothing selected

    func testPristineFormIsBlockedUntilAnAssetIsPicked() {
        let fixture = makeFixture()
        XCTAssertNil(fixture.viewModel.selectedAsset)
        XCTAssertNil(fixture.viewModel.selectedAssetCoin)
        XCTAssertFalse(fixture.viewModel.validForm)
        XCTAssertNil(fixture.viewModel.transactionBuilder, "No asset means no redemption")
    }

    /// Blocked, but never silent: the user is told what to do next rather than
    /// left with a button that does nothing.
    func testBlockedFormExplainsThatAnAssetIsMissing() {
        let fixture = makeFixture()
        XCTAssertNil(fixture.viewModel.transactionBuilder)
        XCTAssertEqual(fixture.viewModel.destinationField.error, "selectSecuredAssetToWithdraw".localized)
        XCTAssertEqual(fixture.viewModel.amountField.error, "selectSecuredAssetToWithdraw".localized)
    }

    // MARK: - Discovery

    func testOnlySecuredDenomsWithABalanceReachThePicker() async {
        let fixture = makeFixture()
        fixture.viewModel.onLoad()
        await awaitAssets(fixture.viewModel)

        XCTAssertEqual(
            fixture.viewModel.availableAssets.map { $0.thorchainAsset },
            [Self.btcDenom, Self.ethDenom],
            "Native RUNE and x/ denoms are not secured assets; the list sorts by display name"
        )
    }

    func testZeroBalanceSecuredAssetsAreOmitted() async {
        let fixture = makeFixture(securedBTCBalance: "0")
        fixture.viewModel.onLoad()
        await awaitAssets(fixture.viewModel)

        XCTAssertEqual(fixture.viewModel.availableAssets.map { $0.thorchainAsset }, [Self.ethDenom])
    }

    func testBalanceFetchFailureSurfacesAMessageRatherThanAnEmptyPicker() async {
        let fixture = makeFixture()
        fixture.stub.balancesError = HelperError.runtimeError("offline")
        fixture.viewModel.onLoad()
        await awaitAssets(fixture.viewModel)

        XCTAssertTrue(fixture.viewModel.availableAssets.isEmpty)
        XCTAssertEqual(fixture.viewModel.loadError, "noSecuredAssets".localized)
    }

    func testDenomClassification() {
        XCTAssertTrue(SecuredWithdrawTransactionViewModel.isSecuredDenom("btc-btc"))
        XCTAssertTrue(SecuredWithdrawTransactionViewModel.isSecuredDenom("eth-usdc-0xa0b8"))
        XCTAssertFalse(SecuredWithdrawTransactionViewModel.isSecuredDenom("rune"))
        XCTAssertFalse(SecuredWithdrawTransactionViewModel.isSecuredDenom("x/ruji"))
        XCTAssertFalse(SecuredWithdrawTransactionViewModel.isSecuredDenom("x/staking-tcy"))
    }

    // MARK: - The destination chain

    func testSelectingAnAssetPrefillsTheVaultsAddressOnThatAssetsOwnChain() async {
        let fixture = await loadedFixture()

        XCTAssertEqual(fixture.viewModel.destinationField.value, Self.btcAddress)
        XCTAssertNil(fixture.viewModel.destinationNotice)
        XCTAssertEqual(fixture.viewModel.destinationCoin.chain, .bitcoin)
    }

    /// The defect this migration closes. The payout leaves THORChain, so the
    /// address has to be valid on the secured asset's L1 — a `thor1…` here
    /// sends funds nowhere recoverable, and the legacy form accepted it.
    func testAThorchainAddressIsRejectedAsABitcoinDestination() async {
        let fixture = await loadedFixture()
        await awaitValidForm(fixture.viewModel, is: false)
        fixture.viewModel.amountField.value = "0.5"
        await awaitValidForm(fixture.viewModel, is: true)

        fixture.viewModel.destinationField.value = Self.thorAddress
        await awaitValidForm(fixture.viewModel, is: false)

        XCTAssertNil(fixture.viewModel.transactionBuilder)
        XCTAssertEqual(fixture.viewModel.destinationField.error, "validAddressError".localized)
    }

    func testAnEthereumAddressIsRejectedAsABitcoinDestination() async {
        let fixture = await loadedFixture()
        fixture.viewModel.amountField.value = "0.5"
        await awaitValidForm(fixture.viewModel, is: true)

        fixture.viewModel.destinationField.value = Self.ethAddress
        await awaitValidForm(fixture.viewModel, is: false)

        XCTAssertNil(fixture.viewModel.transactionBuilder)
    }

    func testADifferentBitcoinAddressIsAccepted() async {
        let fixture = await loadedFixture()
        fixture.viewModel.destinationField.value = Self.otherBtcAddress
        fixture.viewModel.amountField.value = "0.5"
        await awaitValidForm(fixture.viewModel, is: true)

        let builder = fixture.viewModel.transactionBuilder as? SecuredWithdrawTransactionBuilder
        XCTAssertEqual(builder?.destinationAddress, Self.otherBtcAddress)
    }

    /// Switching the asset repoints the validator, not just the prefill: a
    /// Bitcoin address left over from the previous selection must stop passing.
    func testSwitchingAssetRepointsTheDestinationChain() async {
        let fixture = await loadedFixture()

        select(Self.ethDenom, on: fixture.viewModel)
        await awaitMinimum(fixture.viewModel, is: Self.ethMinimum)

        XCTAssertEqual(fixture.viewModel.destinationField.value, Self.ethAddress)
        XCTAssertEqual(fixture.viewModel.destinationCoin.chain, .ethereum)

        fixture.viewModel.destinationField.value = Self.btcAddress
        await awaitValidForm(fixture.viewModel, is: false)
        XCTAssertNil(fixture.viewModel.transactionBuilder, "A BTC address cannot receive an ETH redemption")
    }

    /// The vault holds no Bitcoin coin, so there is nothing to pre-fill. The
    /// exit still has to be reachable — the user is told what is missing and
    /// can paste an address they control.
    func testMissingL1CoinExplainsItselfAndStillAllowsAPastedAddress() async {
        let fixture = await loadedFixture(minimum: nil, includeNativeBTC: false)

        XCTAssertEqual(fixture.viewModel.destinationField.value, "")
        XCTAssertNotNil(fixture.viewModel.destinationNotice)
        XCTAssertTrue(fixture.viewModel.destinationNotice?.contains("BTC") == true)
        XCTAssertNil(fixture.viewModel.transactionBuilder)

        fixture.viewModel.destinationField.value = Self.otherBtcAddress
        fixture.viewModel.amountField.value = "0.5"
        await awaitValidForm(fixture.viewModel, is: true)

        let builder = fixture.viewModel.transactionBuilder as? SecuredWithdrawTransactionBuilder
        XCTAssertEqual(builder?.memo, "SECURE-:\(Self.otherBtcAddress)")
    }

    func testAddressResultWritesTheDestination() async {
        let fixture = await loadedFixture()
        fixture.viewModel.handle(destinationAddressResult: AddressResult(address: Self.otherBtcAddress))
        XCTAssertEqual(fixture.viewModel.destinationField.value, Self.otherBtcAddress)
    }

    func testNilAddressResultLeavesTheDestinationUnchanged() async {
        let fixture = await loadedFixture()
        fixture.viewModel.handle(destinationAddressResult: nil)
        XCTAssertEqual(fixture.viewModel.destinationField.value, Self.btcAddress)
    }

    // MARK: - Amount

    func testEmptyAmountBlocksTheBuilder() async {
        let fixture = await loadedFixture()
        await settle()

        XCTAssertFalse(fixture.viewModel.validForm)
        XCTAssertNil(fixture.viewModel.transactionBuilder)
        XCTAssertEqual(fixture.viewModel.amountField.error, "enterValidAmount".localized)
    }

    func testZeroAmountBlocksTheBuilder() async {
        let fixture = await loadedFixture()
        fixture.viewModel.amountField.value = "0"
        await awaitValidForm(fixture.viewModel, is: false)

        XCTAssertNil(fixture.viewModel.transactionBuilder)
    }

    func testAmountAboveTheSecuredBalanceBlocksTheBuilder() async {
        let fixture = await loadedFixture()
        fixture.viewModel.amountField.value = "2"
        await awaitValidForm(fixture.viewModel, is: false)

        XCTAssertNil(fixture.viewModel.transactionBuilder)
        XCTAssertEqual(fixture.viewModel.amountField.error, "amountExceeded".localized)
    }

    /// The balance is the selected secured asset's, not the RUNE account's.
    func testTheBalanceCeilingFollowsTheSelectedAsset() async {
        let fixture = await loadedFixture()
        fixture.viewModel.amountField.value = "5"
        await awaitValidForm(fixture.viewModel, is: false)

        select(Self.ethDenom, on: fixture.viewModel)
        await awaitMinimum(fixture.viewModel, is: Self.ethMinimum)
        await awaitValidForm(fixture.viewModel, is: true)

        XCTAssertNotNil(fixture.viewModel.transactionBuilder, "5 is within the 10 ETH secured balance")
    }

    // MARK: - The outbound-fee floor

    func testAmountBelowTheOutboundFeeThresholdBlocksTheBuilder() async {
        let fixture = await loadedFixture()
        XCTAssertEqual(fixture.viewModel.minimumWithdrawAmount, Self.btcMinimum)

        fixture.viewModel.amountField.value = "0.0001"
        await awaitValidForm(fixture.viewModel, is: false)

        XCTAssertNil(fixture.viewModel.transactionBuilder, "A redemption under the outbound fee arrives worth nothing")
        XCTAssertEqual(
            fixture.viewModel.amountField.error,
            String(
                format: "withdrawBelowOutboundFee".localized,
                Self.btcMinimum.formatForDisplay(),
                "BTC"
            )
        )
    }

    func testAmountAtTheOutboundFeeThresholdBuilds() async {
        let fixture = await loadedFixture()
        fixture.viewModel.amountField.value = "0.00012"
        await awaitValidForm(fixture.viewModel, is: true)

        XCTAssertNotNil(fixture.viewModel.transactionBuilder)
    }

    /// An outstanding request must HOLD the gate shut, not leave it open.
    /// "Still asking" and "there is no floor" were both a zero minimum, so a
    /// fast Continue could advance below a floor that had not landed yet —
    /// and nothing re-checks the threshold at sign time.
    func testSubmissionIsBlockedWhileTheThresholdIsOutstanding() async {
        let fixture = makeFixture()
        fixture.stub.hold(chain: "BTC")
        fixture.viewModel.onLoad()
        await awaitAssets(fixture.viewModel)
        select(Self.btcDenom, on: fixture.viewModel)

        fixture.viewModel.amountField.value = "0.5"
        await settle()

        XCTAssertEqual(fixture.viewModel.outboundFeeThreshold, .pending)
        XCTAssertNil(fixture.viewModel.transactionBuilder, "An unanswered fee floor must not be treated as no floor")
        XCTAssertEqual(fixture.viewModel.amountField.error, "pleaseWait".localized, "Blocked, but never silent")

        fixture.stub.release(chain: "BTC")
        await awaitMinimum(fixture.viewModel, is: Self.btcMinimum)
        await awaitValidForm(fixture.viewModel, is: true)

        XCTAssertNotNil(fixture.viewModel.transactionBuilder, "0.5 clears the floor once it is known")
    }

    /// The threshold lands from a network reply, which the shared `Form`
    /// pipeline never observes — it only watches `$value`. An amount typed
    /// before the reply must still be re-judged against it.
    func testAThresholdArrivingAfterTheAmountClosesTheGate() async {
        let fixture = makeFixture()
        fixture.stub.hold(chain: "BTC")
        fixture.viewModel.onLoad()
        await awaitAssets(fixture.viewModel)
        select(Self.btcDenom, on: fixture.viewModel)

        fixture.viewModel.amountField.value = "0.0001"
        await settle()

        fixture.stub.release(chain: "BTC")
        await awaitMinimum(fixture.viewModel, is: Self.btcMinimum)

        XCTAssertFalse(fixture.viewModel.validForm)
        XCTAssertNil(fixture.viewModel.transactionBuilder)
        XCTAssertEqual(
            fixture.viewModel.amountField.error,
            String(format: "withdrawBelowOutboundFee".localized, Self.btcMinimum.formatForDisplay(), "BTC")
        )
    }

    /// Fails OPEN, deliberately. This is the only route out of a secured
    /// position, so an unavailable fee endpoint must not become "you cannot
    /// exit" — the network still refuses a genuinely dust payout.
    func testAnUnavailableOutboundFeeLeavesTheFormOpen() async {
        let fixture = makeFixture()
        fixture.stub.outboundFees = [:]
        fixture.viewModel.onLoad()
        await awaitAssets(fixture.viewModel)
        select(Self.btcDenom, on: fixture.viewModel)

        await awaitThreshold(fixture.viewModel, is: .unavailable)
        fixture.viewModel.amountField.value = "0.0000001"
        await awaitValidForm(fixture.viewModel, is: true)

        XCTAssertEqual(fixture.viewModel.minimumWithdrawAmount, 0)
        XCTAssertNotNil(fixture.viewModel.transactionBuilder)
    }

    /// Same reasoning for a missing price: the threshold is expressed in fiat,
    /// so a coin with no rate has no threshold rather than an infinite one.
    func testAMissingRateLeavesTheFormOpen() async {
        let fixture = makeFixture()
        fixture.stub.fiatRates = [:]
        fixture.viewModel.onLoad()
        await awaitAssets(fixture.viewModel)
        select(Self.btcDenom, on: fixture.viewModel)

        await awaitThreshold(fixture.viewModel, is: .unavailable)
        fixture.viewModel.amountField.value = "0.0000001"
        await awaitValidForm(fixture.viewModel, is: true)

        XCTAssertEqual(fixture.viewModel.minimumWithdrawAmount, 0)
        XCTAssertNotNil(fixture.viewModel.transactionBuilder)
    }

    /// A selection that cannot be priced at all — the vault holds no coin on
    /// the payout chain — is `.notApplicable`, not `.pending`. It must not
    /// hold the gate shut waiting for a request that was never made.
    func testAnUnpriceableSelectionDoesNotHoldTheGateShut() async {
        let fixture = await loadedFixture(minimum: nil, includeNativeBTC: false)

        XCTAssertEqual(fixture.viewModel.outboundFeeThreshold, .notApplicable)
        XCTAssertTrue(fixture.stub.outboundFeeRequests.isEmpty)

        fixture.viewModel.destinationField.value = Self.otherBtcAddress
        fixture.viewModel.amountField.value = "0.5"
        await awaitValidForm(fixture.viewModel, is: true)
        XCTAssertNotNil(fixture.viewModel.transactionBuilder)
    }

    // MARK: - The latest-wins race

    /// The legacy form fired one unowned task per selection and wrote every
    /// reply unconditionally, so a slow answer for an asset the user had moved
    /// off overwrote the current one — leaving `minimumWithdrawAmount`
    /// describing a different asset entirely.
    func testALateThresholdForAPreviousAssetCannotOverwriteTheCurrentOne() async {
        let fixture = makeFixture()
        fixture.stub.hold(chain: "BTC")
        fixture.viewModel.onLoad()
        await awaitAssets(fixture.viewModel)

        select(Self.btcDenom, on: fixture.viewModel)
        select(Self.ethDenom, on: fixture.viewModel)
        await awaitMinimum(fixture.viewModel, is: Self.ethMinimum)

        let staleThresholdLanded = XCTestExpectation(description: "the BTC threshold must never land")
        staleThresholdLanded.isInverted = true
        var cancellable: AnyCancellable?
        cancellable = fixture.viewModel.$outboundFeeThreshold
            .sink { if $0 == .known(Self.btcMinimum) { staleThresholdLanded.fulfill() } }

        fixture.stub.release(chain: "BTC")
        await fulfillment(of: [staleThresholdLanded], timeout: 1)
        cancellable?.cancel()

        XCTAssertEqual(fixture.viewModel.minimumWithdrawAmount, Self.ethMinimum)
    }

    /// The other half of the fix: the superseded request is cancelled, so in
    /// the common case the work is abandoned rather than merely ignored.
    func testSelectingAnotherAssetAsksForTheNewAssetsThreshold() async {
        let fixture = await loadedFixture()
        select(Self.ethDenom, on: fixture.viewModel)
        await awaitMinimum(fixture.viewModel, is: Self.ethMinimum)

        XCTAssertEqual(fixture.stub.outboundFeeRequests, ["BTC", "ETH"])
    }

    // MARK: - Reload lifecycle

    /// A reload can retire the position the user had picked. The form must not
    /// keep pointing at an asset the account no longer holds — and the stale
    /// threshold must go with it.
    func testReloadDroppingTheSelectedAssetResetsTheForm() async {
        let fixture = await loadedFixture()
        fixture.viewModel.destinationField.value = Self.otherBtcAddress
        fixture.viewModel.amountField.value = "0.5"
        await awaitValidForm(fixture.viewModel, is: true)

        fixture.stub.balances = [CosmosBalance(denom: Self.ethDenom, amount: "1000000000")]
        fixture.viewModel.loadAvailableSecuredAssets()
        await awaitAssets(fixture.viewModel)

        XCTAssertNil(fixture.viewModel.selectedAsset)
        XCTAssertNil(fixture.viewModel.selectedAssetCoin)
        XCTAssertEqual(fixture.viewModel.destinationField.value, "")
        XCTAssertEqual(fixture.viewModel.outboundFeeThreshold, .notApplicable)
        XCTAssertNil(fixture.viewModel.transactionBuilder, "The picked position is gone")
    }

    /// A selection the reload still offers survives it, re-resolved against the
    /// fresh map so the coin, the destination chain and the floor keep
    /// describing the same asset.
    func testReloadKeepingTheSelectedAssetReResolvesIt() async {
        let fixture = await loadedFixture()

        fixture.viewModel.loadAvailableSecuredAssets()
        await awaitAssets(fixture.viewModel)
        await awaitMinimum(fixture.viewModel, is: Self.btcMinimum)

        XCTAssertEqual(fixture.viewModel.selectedAsset?.thorchainAsset, Self.btcDenom)
        XCTAssertNotNil(fixture.viewModel.selectedAssetCoin)
        XCTAssertEqual(fixture.viewModel.destinationField.value, Self.btcAddress)
    }

    // MARK: - Malformed denoms

    /// `isSecuredDenom` only checks the dash shape, and `securedAssetChain`
    /// falls back to "THOR" when it cannot split a prefix. A denom that
    /// resolves back to THORChain must not be handed a THORChain address
    /// validator and a THORChain pre-fill — a payout never settles there, so
    /// that would look valid all the way to a signature.
    func testADenomResolvingBackToThorchainIsRejectedAsADestination() async {
        let fixture = makeFixture()
        fixture.stub.balances = [CosmosBalance(denom: "thor-rune", amount: "100000000")]
        let malformed = Self.makeSecuredCoin(denom: "thor-rune", rawBalance: "100000000")
        fixture.vault.coins.append(malformed)

        fixture.viewModel.onLoad()
        await awaitAssets(fixture.viewModel)
        select("thor-rune", on: fixture.viewModel)

        XCTAssertEqual(fixture.viewModel.destinationField.value, "")
        XCTAssertNotNil(fixture.viewModel.destinationNotice)
        XCTAssertNil(fixture.viewModel.transactionBuilder)

        fixture.viewModel.destinationField.value = Self.thorAddress
        fixture.viewModel.amountField.value = "0.5"
        await settle()
        XCTAssertNil(fixture.viewModel.transactionBuilder, "A THORChain address can never be a SECURE- payout")
    }

    // MARK: - The submission gate

    func testBuilderCarriesTheExactMemoAndAmount() async {
        let fixture = await loadedFixture()
        fixture.viewModel.amountField.value = "0.5"
        await awaitValidForm(fixture.viewModel, is: true)

        let builder = fixture.viewModel.transactionBuilder as? SecuredWithdrawTransactionBuilder
        XCTAssertEqual(builder?.memo, "SECURE-:\(Self.btcAddress)")
        XCTAssertEqual(builder?.amount, "0.5")
        XCTAssertEqual(builder?.coin.contractAddress, Self.btcDenom)
        XCTAssertEqual(builder?.toAddress, "")
    }

    /// The aggregate is republished a run-loop turn after an edit, so a submit
    /// in the same turn would otherwise ride the previous "valid".
    func testInvalidatingTheAmountBlocksTheBuilderInTheSameRunLoopTurn() async {
        let fixture = await loadedFixture()
        fixture.viewModel.amountField.value = "0.5"
        await awaitValidForm(fixture.viewModel, is: true)

        fixture.viewModel.amountField.value = "2"
        XCTAssertTrue(fixture.viewModel.validForm, "Precondition: the aggregate has not settled yet")
        XCTAssertNil(fixture.viewModel.transactionBuilder, "A same-turn edit must not submit on a stale aggregate")
    }

    /// Pins the guard directly: even handed a `validForm` that says yes, the
    /// builder re-runs the fields and refuses.
    func testBuilderIgnoresAStaleAggregate() async {
        let fixture = await loadedFixture()
        fixture.viewModel.amountField.value = "0.0001"
        await awaitValidForm(fixture.viewModel, is: false)

        fixture.viewModel.validForm = true
        XCTAssertNil(fixture.viewModel.transactionBuilder)
    }

    /// The mirror window: a form completed and submitted in one turn must not
    /// have its first Continue tap silently swallowed.
    func testCompletingTheFormBuildsInTheSameRunLoopTurn() async {
        let fixture = await loadedFixture()
        await awaitValidForm(fixture.viewModel, is: false)

        fixture.viewModel.amountField.value = "0.5"
        XCTAssertFalse(fixture.viewModel.validForm, "Precondition: the aggregate has not settled yet")
        XCTAssertNotNil(fixture.viewModel.transactionBuilder)
    }

    // MARK: - Display

    func testBalanceDescriptionNamesTheL1QualifiedAsset() async {
        let fixture = makeFixture()
        XCTAssertEqual(fixture.viewModel.balanceDescription, "selectSecuredAssetToSeeBalance".localized)

        fixture.viewModel.onLoad()
        await awaitAssets(fixture.viewModel)
        select(Self.btcDenom, on: fixture.viewModel)

        XCTAssertEqual(fixture.viewModel.selectedAssetDisplayName, "BTC.BTC")
        XCTAssertTrue(fixture.viewModel.balanceDescription.contains("BTC.BTC"))
    }
}

// MARK: - Stub

@MainActor
final class StubSecuredWithdrawDataSource: SecuredWithdrawDataSource {
    var balances: [CosmosBalance] = []
    var balancesError: Error?
    /// Keyed by THORChain inbound chain name (`BTC`, `ETH`). A missing key is
    /// "the node has no inbound row for this chain".
    var outboundFees: [String: Decimal] = [:]
    /// Fiat per single unit, keyed by ticker. A missing key is "no price".
    var fiatRates: [String: Decimal] = [:]

    private(set) var outboundFeeRequests: [String] = []
    private var heldChains: Set<String> = []
    private var gates: [String: CheckedContinuation<Void, Never>] = [:]

    /// Holds the next fee request for `chain` open until `release(chain:)`,
    /// which is how the tests put two threshold requests in flight at once.
    func hold(chain: String) {
        heldChains.insert(chain)
    }

    func release(chain: String) {
        heldChains.remove(chain)
        gates.removeValue(forKey: chain)?.resume()
    }

    // swiftlint:disable:next async_without_await
    func securedAssetBalances(address _: String, chain _: Chain) async throws -> [CosmosBalance] {
        if let balancesError { throw balancesError }
        return balances
    }

    func outboundFee(forInboundChain chainName: String) async -> Decimal? {
        outboundFeeRequests.append(chainName)
        if heldChains.contains(chainName) {
            await withCheckedContinuation { gates[chainName] = $0 }
        }
        return outboundFees[chainName]
    }

    func fiatValue(of amount: Decimal, coin: Coin) -> Decimal {
        guard let rate = fiatRates[coin.ticker.uppercased()] else { return 0 }
        return amount * rate
    }
}
