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
        interactor = DefaultLimitSwapInteractor(
            quoteService: quoteService,
            storage: LimitOrderStorageService()
        )
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

    func testRefreshMarketPriceFallsBackToOneUnitWhenSourceAmountIsZero() async {
        // Phase-1 behaviour: the view kicks `refreshMarketPrice()` on appear
        // before the user has typed anything, so the VM substitutes a 1-unit
        // (`10^sourceDecimals`) quote rather than early-returning. This
        // populates `marketPriceRef` for the preset pills + price-field
        // auto-seed.
        let vm = makeViewModel(sourceAmount: 0)
        quoteService.marketPriceResult = .success(99)

        await vm.refreshMarketPrice()

        XCTAssertEqual(vm.marketPriceRef, 99)
        XCTAssertEqual(quoteService.marketPriceCallCount, 1)
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

    // MARK: - destinationAddress lookup

    func testDestinationAddressFindsMatchingVaultCoin() {
        let vm = makeViewModel()
        XCTAssertEqual(vm.destinationAddress(), "0xethdestaddress00000000000000000000000000")
    }

    // MARK: - fixtures

    private func makeViewModel(
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

    private func btcAsset() -> LimitSwapAsset {
        LimitSwapAsset(chain: .bitcoin, ticker: "BTC", decimals: 8, contractAddress: "BTC-contract", isNativeToken: true)
    }

    private func ethAsset() -> LimitSwapAsset {
        LimitSwapAsset(chain: .ethereum, ticker: "ETH", decimals: 18, contractAddress: "ETH-contract", isNativeToken: true)
    }
}

private struct UntestedError: Error {}
