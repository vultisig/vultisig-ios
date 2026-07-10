//
//  LimitSwapFormViewModelTests.swift
//  VultisigAppTests
//

@testable import VultisigApp
import BigInt
import XCTest

@MainActor
final class LimitSwapFormViewModelTests: XCTestCase {

    private var storeToken: TestContextToken!
    private var vault: Vault!
    private var quoteService: MockLimitSwapQuoteService!
    private var interactor: DefaultLimitSwapInteractor!

    override func setUp() async throws {
        try await super.setUp()
        storeToken = try TestStore.installInMemoryContainer()
        vault = TestStore.makeVault()

        // Vault holds matching coins for source (BTC) + target (ETH) so
        // destinationAddress() can resolve.
        vault.coins.append(Coin(
            asset: CoinMeta.make(chain: .bitcoin, ticker: "BTC", decimals: 8),
            address: "bc1qsourceaddress0000000000000000000000000",
            hexPublicKey: "btc-pubkey"
        ))
        vault.coins.append(Coin(
            asset: CoinMeta.make(chain: .ethereum, ticker: "ETH", decimals: 18),
            address: "0xethdestaddress00000000000000000000000000",
            hexPublicKey: "eth-pubkey"
        ))

        quoteService = MockLimitSwapQuoteService()
        interactor = DefaultLimitSwapInteractor(quoteService: quoteService)
    }

    override func tearDown() async throws {
        interactor = nil
        quoteService = nil
        vault = nil
        TestStore.restore(storeToken)
        storeToken = nil
        try await super.tearDown()
    }

    // MARK: - input mutations

    func testAmountChangedUpdatesDraft() {
        let vm = makeViewModel()
        vm.amountChanged(BigInt(50_000_000))
        XCTAssertEqual(vm.draft.sourceAmount, BigInt(50_000_000))
    }

    func testTargetPriceChangedUpdatesDraft() {
        let vm = makeViewModel()
        vm.targetPriceChanged(Decimal(string: "16.5")!)
        XCTAssertEqual(vm.draft.targetPrice, Decimal(string: "16.5")!)
    }

    func testSelectExpiryHoursUpdatesDraft() {
        let vm = makeViewModel()
        vm.selectExpiryHours(72)
        XCTAssertEqual(vm.draft.expiryHours, 72)
    }

    func testToggleDisplayUnitFlipsBetweenAssetAndUsd() {
        let vm = makeViewModel(initialDisplayUnit: .asset)
        vm.toggleDisplayUnit()
        XCTAssertEqual(vm.draft.displayUnit, .usd)
        vm.toggleDisplayUnit()
        XCTAssertEqual(vm.draft.displayUnit, .asset)
    }

    // MARK: - preset pills

    func testSelectPresetPctMarketAlignsTargetWithMarketPrice() {
        let vm = makeViewModel()
        vm.marketPriceRef = 100
        vm.selectPresetPct(0)
        XCTAssertEqual(vm.draft.targetPrice, 100)
    }

    func testSelectPresetPctOnePercentAddsOnePercent() {
        let vm = makeViewModel()
        vm.marketPriceRef = 100
        vm.selectPresetPct(1)
        XCTAssertEqual(vm.draft.targetPrice, 101)
    }

    func testSelectPresetPctTenPercentAddsTenPercent() {
        let vm = makeViewModel()
        vm.marketPriceRef = 100
        vm.selectPresetPct(10)
        XCTAssertEqual(vm.draft.targetPrice, 110)
    }

    func testSelectPresetPctIsNoOpWhenMarketReferenceMissing() {
        let vm = makeViewModel()
        vm.marketPriceRef = nil
        vm.draft.targetPrice = 50
        vm.selectPresetPct(5)
        XCTAssertEqual(vm.draft.targetPrice, 50, "Preset must not act without a market reference")
    }

    // MARK: - asset selection invalidates market reference

    func testSelectFromAssetClearsMarketPriceReference() {
        let vm = makeViewModel()
        vm.marketPriceRef = 16
        vm.selectFromAsset(LimitSwapAsset(
            chain: .litecoin, ticker: "LTC", decimals: 8,
            contractAddress: "", isNativeToken: true
        ))
        XCTAssertNil(vm.marketPriceRef)
    }

    func testSelectToAssetClearsMarketPriceReference() {
        let vm = makeViewModel()
        vm.marketPriceRef = 16
        vm.selectToAsset(LimitSwapAsset(
            chain: .thorChain, ticker: "RUNE", decimals: 8,
            contractAddress: "", isNativeToken: true
        ))
        XCTAssertNil(vm.marketPriceRef)
    }

    // MARK: - computed UI state

    func testPctFromMarketIsZeroWhenMarketReferenceMissing() {
        let vm = makeViewModel()
        vm.marketPriceRef = nil
        vm.draft.targetPrice = 100
        XCTAssertEqual(vm.pctFromMarket, 0)
    }

    func testPctFromMarketComputesCorrectPercentage() {
        let vm = makeViewModel()
        vm.marketPriceRef = 100
        vm.draft.targetPrice = 105
        XCTAssertEqual(vm.pctFromMarket, 5)
    }

    func testDisplayedWarningIsNilWithoutMarketReference() {
        let vm = makeViewModel()
        vm.marketPriceRef = nil
        vm.draft.targetPrice = 50
        XCTAssertNil(vm.displayedWarning)
    }

    func testDisplayedWarningTriggersAtOrBelowMarket() {
        let vm = makeViewModel()
        vm.marketPriceRef = 100
        vm.draft.targetPrice = 95
        XCTAssertEqual(vm.displayedWarning, .priceAtOrBelowMarket)
    }

    func testDisplayedWarningTriggersFarAboveMarket() {
        let vm = makeViewModel()
        vm.marketPriceRef = 100
        vm.draft.targetPrice = 121
        XCTAssertEqual(vm.displayedWarning, .priceFarAboveMarket)
    }

    func testDisplayedWarningIsNilInTheReasonableBand() {
        let vm = makeViewModel()
        vm.marketPriceRef = 100
        vm.draft.targetPrice = 110
        XCTAssertNil(vm.displayedWarning)
    }

    // MARK: - refreshMarketPrice

    func testRefreshMarketPriceStoresFetchedValue() async {
        let vm = makeViewModel(sourceAmount: BigInt(100_000_000))
        quoteService.marketPriceResult = .success(Decimal(string: "16.5")!)

        await vm.refreshMarketPrice()

        XCTAssertEqual(vm.marketPriceRef, Decimal(string: "16.5")!)
        XCTAssertNil(vm.marketPriceError)
        XCTAssertFalse(vm.isLoadingMarketPrice)
        XCTAssertEqual(quoteService.marketPriceCallCount, 1)
    }

    func testRefreshMarketPriceFailureSurfacesErrorAndPreservesPreviousReference() async {
        struct UpstreamError: Error {}

        let vm = makeViewModel(sourceAmount: BigInt(100_000_000))
        vm.marketPriceRef = 16
        quoteService.marketPriceResult = .failure(UpstreamError())

        await vm.refreshMarketPrice()

        XCTAssertEqual(vm.marketPriceRef, 16, "Previous reference must be preserved on failure")
        XCTAssertNotNil(vm.marketPriceError)
        XCTAssertFalse(vm.isLoadingMarketPrice)
    }

    func testRefreshMarketPriceFallsBackToOneUnitWhenSourceAmountIsZeroWithoutRate() async {
        // Phase-1 behaviour: the view kicks `refreshMarketPrice()` on appear
        // before the user has typed anything, so the VM substitutes a probe
        // quote rather than early-returning. With no source USD rate the probe
        // falls back to a 1-unit (`10^sourceDecimals`) quote.
        let vm = makeViewModel(sourceAmount: 0)
        quoteService.marketPriceResult = .success(99)

        await vm.refreshMarketPrice()

        XCTAssertEqual(vm.marketPriceRef, 99)
        XCTAssertEqual(quoteService.marketPriceCallCount, 1)
        XCTAssertEqual(quoteService.marketPriceAmounts.first, BigInt(10).power(8),
                       "Without a USD rate the probe must fall back to 1 whole unit")
    }

    func testRefreshMarketPriceProbesFiatNotionalWhenSourceAmountIsZero() async {
        // The bug: a cheap source (e.g. RUNE) at 0 amount probed with 1 whole
        // unit, which THORChain rejects (outbound fee > output) so no reference
        // ever loaded. With a source USD rate the probe is sized to ~$100 of the
        // source instead — here $2/unit BTC-decimals → 50 units × 1e8.
        let vm = makeViewModel(sourceAmount: 0)
        vm.sourceUsdPricePerUnit = 2
        quoteService.marketPriceResult = .success(99)

        await vm.refreshMarketPrice()

        XCTAssertEqual(quoteService.marketPriceAmounts.first, BigInt(5_000_000_000))
    }

    func testRefreshMarketPriceUsesTypedAmountOverProbe() async {
        // Once the user has typed an amount it is used verbatim, ignoring the
        // notional probe / source price.
        let vm = makeViewModel(sourceAmount: BigInt(777))
        vm.sourceUsdPricePerUnit = 2
        quoteService.marketPriceResult = .success(99)

        await vm.refreshMarketPrice()

        XCTAssertEqual(quoteService.marketPriceAmounts.first, BigInt(777))
    }

    func testRefreshMarketPriceFailsWhenTargetChainHasNoVaultCoin() async {
        // Replace the vault's ETH coin with a chain not represented (LTC),
        // so destinationAddress() returns nil for the .ethereum target.
        vault.coins.removeAll(where: { $0.chain == .ethereum })

        let vm = makeViewModel(sourceAmount: BigInt(100_000_000))
        quoteService.marketPriceResult = .success(99)

        await vm.refreshMarketPrice()

        guard case LimitSwapFormViewModel.ViewModelError.noDestinationAddressForTargetChain = vm.marketPriceError ?? UntestedError() else {
            return XCTFail("Expected noDestinationAddressForTargetChain")
        }
        XCTAssertNil(vm.marketPriceRef)
    }

    // MARK: - refreshNetworkFeeEstimate (limit network-fee estimate)

    func testRefreshNetworkFeeEstimateSkippedWhenAmountIsZero() async {
        let mockInteractor = MockLimitSwapInteractor()
        mockInteractor.networkFeeResult = .success(BigInt(4_200))
        let vm = makeViewModel(interactor: mockInteractor, sourceAmount: 0)

        await vm.refreshNetworkFeeEstimate(sourceCoin: btcCoin(), targetCoin: ethCoin())

        XCTAssertEqual(mockInteractor.estimateNetworkFeeCallCount, 0, "No estimate is needed before an amount is entered")
        XCTAssertEqual(vm.networkFeeEstimate, .zero)
    }

    func testRefreshNetworkFeeEstimateStoresInteractorResult() async {
        let mockInteractor = MockLimitSwapInteractor()
        mockInteractor.networkFeeResult = .success(BigInt(4_200))
        let vm = makeViewModel(interactor: mockInteractor, sourceAmount: BigInt(100_000_000))

        await vm.refreshNetworkFeeEstimate(sourceCoin: btcCoin(), targetCoin: ethCoin())

        XCTAssertEqual(mockInteractor.estimateNetworkFeeCallCount, 1)
        XCTAssertEqual(mockInteractor.estimateNetworkFeeAmounts.first, BigInt(100_000_000),
                       "The estimate must be sized to the real (placed) amount")
        XCTAssertEqual(vm.networkFeeEstimate, BigInt(4_200))
    }

    func testInputChangesClearStaleNetworkFeeEstimate() {
        // A fee estimate must never survive a source/target/amount change — else a
        // previous pair/amount's fee could be snapshotted into the placed order.
        let vm = makeViewModel()

        vm.networkFeeEstimate = BigInt(111)
        vm.amountChanged(BigInt(5))
        XCTAssertEqual(vm.networkFeeEstimate, .zero, "amountChanged must clear the estimate")

        vm.networkFeeEstimate = BigInt(222)
        vm.selectFromAsset(LimitSwapAsset(chain: .litecoin, ticker: "LTC", decimals: 8, contractAddress: "", isNativeToken: true))
        XCTAssertEqual(vm.networkFeeEstimate, .zero, "selectFromAsset must clear the estimate")

        vm.networkFeeEstimate = BigInt(333)
        vm.selectToAsset(LimitSwapAsset(chain: .thorChain, ticker: "RUNE", decimals: 8, contractAddress: "", isNativeToken: true))
        XCTAssertEqual(vm.networkFeeEstimate, .zero, "selectToAsset must clear the estimate")
    }

    func testRefreshNetworkFeeEstimateKeepsPreviousEstimateOnFailure() async {
        struct UpstreamError: Error {}
        let mockInteractor = MockLimitSwapInteractor()
        mockInteractor.networkFeeResult = .failure(UpstreamError())
        let vm = makeViewModel(interactor: mockInteractor, sourceAmount: BigInt(100_000_000))
        vm.networkFeeEstimate = BigInt(999)  // a prior successful estimate

        await vm.refreshNetworkFeeEstimate(sourceCoin: btcCoin(), targetCoin: ethCoin())

        XCTAssertEqual(vm.networkFeeEstimate, BigInt(999), "A transient fetch failure must not zero the estimate")
    }

    // MARK: - refreshSupportedChains (routed through the injected interactor)

    func testRefreshSupportedChainsUsesInjectedInteractor() async {
        quoteService.inboundAddressesResult = [
            InboundAddress(
                chain: "BTC", address: "a", router: nil, halted: false,
                global_trading_paused: false, chain_trading_paused: false,
                chain_lp_actions_paused: false, gas_rate: "0", gas_rate_units: "u",
                dust_threshold: nil, outbound_fee: nil, outbound_tx_size: nil
            ),
            InboundAddress(
                chain: "ETH", address: "b", router: nil, halted: false,
                global_trading_paused: false, chain_trading_paused: false,
                chain_lp_actions_paused: false, gas_rate: "0", gas_rate_units: "u",
                dust_threshold: nil, outbound_fee: nil, outbound_tx_size: nil
            )
        ]
        let vm = makeViewModel()

        await vm.refreshSupportedChains()

        XCTAssertEqual(quoteService.inboundAddressesCallCount, 1)
        let supported = vm.supportedChains ?? []
        XCTAssertTrue(supported.contains(.thorChain))
        XCTAssertTrue(supported.contains(.bitcoin))
        XCTAssertTrue(supported.contains(.ethereum))
    }

    // MARK: - destinationAddress lookup

    func testDestinationAddressFindsMatchingVaultCoin() {
        let vm = makeViewModel()
        XCTAssertEqual(vm.destinationAddress(), "0xethdestaddress00000000000000000000000000")
    }

    // MARK: - preparePlaceableOrder (the live place-order gate)

    func testPreparePlaceableOrderBuildsRecordAndMemoForValidDraft() {
        let vm = makeViewModel(sourceAmount: BigInt(100_000_000))
        vm.advancedSwapQueueEnabled = true
        vm.draft.targetPrice = 16
        vm.draft.expiryHours = 24

        guard let prepared = vm.preparePlaceableOrder() else {
            return XCTFail("Expected a prepared order for a valid draft")
        }

        XCTAssertNil(vm.placeOrderError)
        // Memo prefix / affiliate are stable regardless of LIM encoding.
        XCTAssertTrue(prepared.memo.hasPrefix("=<:ETH.ETH:0xethdestaddress00000000000000000000000000:"))
        XCTAssertTrue(prepared.memo.contains(":\(THORChainSwaps.affiliateFeeAddress):"))

        let record = prepared.record
        XCTAssertEqual(record.sourceAsset, "BTC.BTC")
        XCTAssertEqual(record.targetAsset, "ETH.ETH")
        XCTAssertEqual(record.destAddress, "0xethdestaddress00000000000000000000000000")
        XCTAssertEqual(record.targetPrice, 16)
        XCTAssertEqual(record.expiryHours, 24)
        XCTAssertEqual(record.expiryBlocks, 14_400)
        XCTAssertEqual(record.sourceAmount, "100000000")
        XCTAssertEqual(record.status, .pending)
        XCTAssertTrue(record.inboundTxHash.isEmpty, "Inbound hash is spliced in later on the Done screen")
        XCTAssertEqual(record.memo, prepared.memo)
    }

    func testPreparePlaceableOrderRejectsNonNativeSource() {
        let vm = makeViewModel(sourceAmount: BigInt(100_000_000))
        vm.advancedSwapQueueEnabled = true
        vm.draft.fromAsset = LimitSwapAsset(
            chain: .ethereum, ticker: "USDC", decimals: 6,
            contractAddress: "0x1234567890abcdefEC7", isNativeToken: false
        )
        vm.draft.toAsset = LimitSwapAsset(
            chain: .bitcoin, ticker: "BTC", decimals: 8,
            contractAddress: "", isNativeToken: true
        )
        // Vault needs a BTC coin as the destination for the .bitcoin target.
        vault.coins.append(Coin(
            asset: CoinMeta.make(chain: .bitcoin, ticker: "BTC", decimals: 8),
            address: "bc1qdest0000000000000000000000000000000000",
            hexPublicKey: "btc-dest-pubkey"
        ))
        vm.draft.targetPrice = Decimal(string: "0.00002")!

        XCTAssertNil(vm.preparePlaceableOrder())
        XCTAssertEqual(vm.placeOrderError, .nonNativeSourceUnsupported)
    }

    func testPreparePlaceableOrderRejectsUnsupportedExpiryViaValidation() {
        let vm = makeViewModel(sourceAmount: BigInt(100_000_000))
        vm.advancedSwapQueueEnabled = true
        vm.draft.targetPrice = 16
        vm.draft.expiryHours = 99  // not in {12, 24, 72}

        XCTAssertNil(vm.preparePlaceableOrder())
        guard case .invalidInputs(let errors)? = vm.placeOrderError else {
            return XCTFail("Expected .invalidInputs, got \(String(describing: vm.placeOrderError))")
        }
        XCTAssertTrue(errors.contains(.expiryHoursUnsupported(99)))
    }

    func testPreparePlaceableOrderReturnsNilSilentlyWhenAmountIsZero() {
        let vm = makeViewModel(sourceAmount: 0)
        vm.draft.targetPrice = 16

        XCTAssertNil(vm.preparePlaceableOrder())
        XCTAssertNil(vm.placeOrderError, "A not-ready draft returns nil without raising a user-facing error")
    }

    func testPreparePlaceableOrderWiresReferredAffiliateFragment() {
        // A vault with a referral code produces the referred affiliate fragment
        // `<code>/vi` — verified via the same helper the market path uses.
        // Use an ETH (non-UTXO, 250B cap) source so the referred memo isn't
        // rejected by the 80B UTXO cap.
        vault.referralCode = ReferralCode(code: "myref", vault: vault)
        let vm = makeViewModel(sourceAmount: BigInt("1000000000000000000"))
        vm.advancedSwapQueueEnabled = true
        vm.draft.fromAsset = LimitSwapAsset(
            chain: .ethereum, ticker: "ETH", decimals: 18,
            contractAddress: "ETH-contract", isNativeToken: true
        )
        vm.draft.toAsset = LimitSwapAsset(
            chain: .bitcoin, ticker: "BTC", decimals: 8,
            contractAddress: "BTC-contract", isNativeToken: true
        )
        vm.draft.targetPrice = Decimal(string: "0.0625")!

        guard let prepared = vm.preparePlaceableOrder() else {
            return XCTFail("Expected a prepared order")
        }
        XCTAssertTrue(
            prepared.memo.hasSuffix(":myref/\(THORChainSwaps.affiliateFeeAddress):\(THORChainSwaps.referredUserFeeRateBp)/\(THORChainSwaps.referredAffiliateFeeRateBp)"),
            "Referred affiliate fragment must be wired; got: \(prepared.memo)"
        )
    }

    func testPreparePlaceableOrderMapsByteCapOverflowToMemoTooLong() {
        // BTC (UTXO, 80B cap) source + a token target with a referred affiliate
        // overflows the 80-byte cap → user-facing .memoTooLong.
        vault.referralCode = ReferralCode(code: "myref", vault: vault)
        // Target the vault's ETH address via a token asset with a long contract.
        let vm = makeViewModel(sourceAmount: BigInt(100_000_000))
        vm.advancedSwapQueueEnabled = true
        vm.draft.toAsset = LimitSwapAsset(
            chain: .ethereum, ticker: "USDC", decimals: 6,
            contractAddress: "0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48", isNativeToken: false
        )
        vm.draft.targetPrice = Decimal(string: "0.00002")!

        XCTAssertNil(vm.preparePlaceableOrder())
        guard case .memoTooLong(let actual, let limit)? = vm.placeOrderError else {
            return XCTFail("Expected .memoTooLong, got \(String(describing: vm.placeOrderError))")
        }
        XCTAssertGreaterThan(actual, limit)
        XCTAssertEqual(limit, 80)
    }

    func testSelectPresetPctRoundsToEightDecimalsForRoundTripStability() {
        let vm = makeViewModel()
        vm.marketPriceRef = Decimal(string: "0.123456789")!  // 9-dp base
        vm.selectPresetPct(1)  // ×1.01 → more than 8 dp before rounding

        // The stored price must already be rounded to ≤ 8 dp so the text↔draft
        // round-trip (formatter caps at 8) is stable and doesn't clobber the preset.
        var rounded = Decimal()
        var value = vm.draft.targetPrice
        NSDecimalRound(&rounded, &value, 8, .plain)
        XCTAssertEqual(vm.draft.targetPrice, rounded, "Preset price must be pre-rounded to 8 dp")
        XCTAssertEqual(vm.lastPresetPct, 1)
    }

    // MARK: - Advanced Swap Queue mimir gate (fail-closed)

    func testPreparePlaceableOrderBlocksWhenQueueGateUnresolved() {
        // Fail-closed default: the mimir gate hasn't resolved (nil) yet, so a
        // fully valid draft must NOT be placeable.
        let vm = makeViewModel(sourceAmount: BigInt(100_000_000))
        vm.draft.targetPrice = 16
        XCTAssertNil(vm.advancedSwapQueueEnabled)

        XCTAssertNil(vm.preparePlaceableOrder())
        XCTAssertEqual(vm.placeOrderError, .advancedSwapQueueDisabled)
    }

    func testPreparePlaceableOrderBlocksWhenQueueGateDisabled() {
        let vm = makeViewModel(sourceAmount: BigInt(100_000_000))
        vm.advancedSwapQueueEnabled = false
        vm.draft.targetPrice = 16

        XCTAssertNil(vm.preparePlaceableOrder())
        XCTAssertEqual(vm.placeOrderError, .advancedSwapQueueDisabled)
    }

    func testRefreshAdvancedSwapQueueGateStoresEnabledResult() async {
        quoteService.advancedSwapQueueEnabledResult = true
        let vm = makeViewModel()

        await vm.refreshAdvancedSwapQueueGate()

        XCTAssertEqual(vm.advancedSwapQueueEnabled, true)
        XCTAssertTrue(vm.isAdvancedSwapQueueEnabled)
        XCTAssertEqual(quoteService.advancedSwapQueueCallCount, 1)
    }

    func testRefreshAdvancedSwapQueueGateStoresDisabledResult() async {
        quoteService.advancedSwapQueueEnabledResult = false
        let vm = makeViewModel()

        await vm.refreshAdvancedSwapQueueGate()

        XCTAssertEqual(vm.advancedSwapQueueEnabled, false)
        XCTAssertFalse(vm.isAdvancedSwapQueueEnabled)
    }

    // MARK: - fixtures

    private func makeViewModel(
        sourceAmount: BigInt = 0,
        initialDisplayUnit: PriceDisplayUnit = .asset
    ) -> LimitSwapFormViewModel {
        makeViewModel(interactor: interactor, sourceAmount: sourceAmount, initialDisplayUnit: initialDisplayUnit)
    }

    private func makeViewModel(
        interactor: LimitSwapInteractor,
        sourceAmount: BigInt = 0,
        initialDisplayUnit: PriceDisplayUnit = .asset
    ) -> LimitSwapFormViewModel {
        let draft = LimitSwapDraft(
            fromAsset: btcAsset(),
            toAsset: ethAsset(),
            sourceAmount: sourceAmount,
            displayUnit: initialDisplayUnit
        )
        return LimitSwapFormViewModel(
            initialDraft: draft,
            vault: vault,
            interactor: interactor
        )
    }

    /// The vault's BTC / ETH coins (installed in `setUp`) — for VM methods that
    /// take concrete source/target `Coin`s (e.g. the network-fee estimate).
    private func btcCoin() -> Coin {
        vault.coins.first { $0.chain == .bitcoin }!
    }

    private func ethCoin() -> Coin {
        vault.coins.first { $0.chain == .ethereum }!
    }

    private func btcAsset() -> LimitSwapAsset {
        LimitSwapAsset(chain: .bitcoin, ticker: "BTC", decimals: 8, contractAddress: "BTC-contract", isNativeToken: true)
    }

    private func ethAsset() -> LimitSwapAsset {
        LimitSwapAsset(chain: .ethereum, ticker: "ETH", decimals: 18, contractAddress: "ETH-contract", isNativeToken: true)
    }
}

private struct UntestedError: Error {}
