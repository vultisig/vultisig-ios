//
//  IBCTransferTransactionViewModelTests.swift
//  VultisigAppTests
//
//  Form behaviour, including the two things the legacy sub-model got wrong: it
//  seeded the amount with the whole balance and no fee reserve, and it validated
//  the destination address against a permissive multi-chain check rather than
//  against the chain the funds were about to land on.
//
//  Addresses here are real bech32 with real checksums — `AddressValidator` runs
//  `AnyAddress`/`CoinType.validate`, and each of these three chains has its own
//  WalletCore coin type, so an address for the wrong one is genuinely rejected
//  rather than merely prefix-mismatched. That is the whole point of the
//  per-destination validation this replaces.
//
//  `transactionBuilder` reads the fields synchronously (it calls
//  `validateErrors()` first), so these do not have to wait on the published
//  `validForm` — which is exactly why it reads the fields rather than the
//  aggregate.
//

@testable import VultisigApp
import Combine
import XCTest

@MainActor
final class IBCTransferTransactionViewModelTests: XCTestCase {

    private static let gaiaAddress = "cosmos1qypqxpq9qcrsszg2pvxq6rs0zqg3yyc5lzv7xu"
    private static let kujiraAddress = "kujira1qypqxpq9qcrsszg2pvxq6rs0zqg3yyc5w2wxtk"
    private static let osmosisAddress = "osmo1qypqxpq9qcrsszg2pvxq6rs0zqg3yyc5helwsw"

    private let enUS = Locale(identifier: "en_US")

    // MARK: - Fixtures

    private func makeKuji(rawBalance: String = "10000000") -> Coin {
        FunctionCallFixture.makeCoin(
            .kujira,
            ticker: "KUJI",
            decimals: 6,
            isNative: true,
            rawBalance: rawBalance,
            address: Self.kujiraAddress
        )
    }

    private func makeAtom() -> Coin {
        FunctionCallFixture.makeCoin(
            .gaiaChain,
            ticker: "ATOM",
            decimals: 6,
            isNative: true,
            address: Self.gaiaAddress
        )
    }

    private func makeOsmo() -> Coin {
        FunctionCallFixture.makeCoin(
            .osmosis,
            ticker: "OSMO",
            decimals: 6,
            isNative: true,
            address: Self.osmosisAddress
        )
    }

    private func makeViewModel(
        coin: Coin? = nil,
        extraCoins: [Coin] = [],
        destinationChain: Chain? = nil
    ) -> IBCTransferTransactionViewModel {
        let source = coin ?? makeKuji()
        let vault = FunctionCallFixture.makeVault(coins: [source] + extraCoins)
        let viewModel = IBCTransferTransactionViewModel(
            coin: source,
            vault: vault,
            destinationChain: destinationChain,
            locale: enUS
        )
        viewModel.onLoad()
        return viewModel
    }

    private func destination(
        _ viewModel: IBCTransferTransactionViewModel,
        _ chain: Chain,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> IBCDestination {
        try XCTUnwrap(
            viewModel.destinations.first { $0.chain == chain },
            "\(viewModel.coin.chain.rawValue) must route to \(chain.rawValue)",
            file: file,
            line: line
        )
    }

    // MARK: - Destinations

    func testDestinationsMirrorTheChainsIbcRoutes() {
        XCTAssertEqual(
            makeViewModel().destinations.map { $0.chain },
            Chain.kujira.ibcTo.map { $0.destinationChain }
        )
        XCTAssertEqual(makeViewModel(coin: makeAtom()).destinations.map { $0.chain }, [.osmosis, .kujira])
        XCTAssertEqual(makeViewModel(coin: makeOsmo()).destinations.map { $0.chain }, [.gaiaChain, .kujira])
    }

    func testDestinationsCarryTheChannelOfEachRoute() throws {
        let viewModel = makeViewModel()
        XCTAssertEqual(try destination(viewModel, .gaiaChain).sourceChannel, "channel-0")
        XCTAssertEqual(try destination(viewModel, .osmosis).sourceChannel, "channel-3")
    }

    /// Carried over from the legacy form, which expressed it as a `continue`
    /// inside its chain loop whose condition never depended on the loop
    /// variable — so it skipped every destination. LVN has never been
    /// IBC-transferable; now the form says so instead of silently refusing.
    func testKujiraLvnHasNoRoutesAndHardDisablesContinue() {
        let lvn = FunctionCallFixture.makeCoin(
            .kujira,
            ticker: TokensStore.Token.kujiraLVN.ticker,
            decimals: 6,
            isNative: false,
            address: Self.kujiraAddress
        )
        let viewModel = makeViewModel(coin: lvn)

        XCTAssertTrue(viewModel.destinations.isEmpty)
        XCTAssertTrue(viewModel.hasNoDestinations)
        XCTAssertTrue(viewModel.isContinueDisabled)
        XCTAssertNil(viewModel.transactionBuilder, "A routeless asset can never build a transfer")
    }

    func testAPreSelectedDestinationOpensOnThatRoute() {
        let viewModel = makeViewModel(destinationChain: .osmosis)
        XCTAssertEqual(viewModel.selectedDestination?.chain, .osmosis)
        XCTAssertEqual(viewModel.selectedDestination?.sourceChannel, "channel-3")
    }

    func testTheListIsEnteredColdWithNoRouteSelected() {
        let viewModel = makeViewModel()
        XCTAssertNil(viewModel.selectedDestination)
        XCTAssertFalse(viewModel.isContinueDisabled, "Continue reveals the errors; it is not disabled here")
    }

    // MARK: - The amount pre-fill defect

    /// The legacy form did `self.amount = coin.balanceDecimal` in its
    /// initialiser, putting "send everything, then be unable to pay the fee" one
    /// tap away.
    func testTheAmountFieldStartsEmptyRatherThanSeededWithTheBalance() {
        let viewModel = makeViewModel()
        XCTAssertEqual(viewModel.amountField.value, .empty)
        XCTAssertEqual(viewModel.amountField.rawValue, .empty)
        XCTAssertFalse(viewModel.amountField.touched, "A pristine field must not show errors yet")
    }

    /// The fee is paid in the same denom a native transfer moves, so the ceiling
    /// the percentage buttons scale has to reserve it.
    func testTheSpendableCeilingReservesTheFeeForANativeAsset() {
        let kuji = makeKuji()
        let viewModel = makeViewModel(coin: kuji)

        XCTAssertGreaterThan(viewModel.feeReserve, 0)
        XCTAssertEqual(viewModel.spendableBalance, kuji.balanceDecimal - viewModel.feeReserve)
        XCTAssertLessThan(viewModel.spendableBalance, kuji.balanceDecimal)
    }

    private func makeUsk() -> Coin {
        FunctionCallFixture.makeCoin(
            .kujira,
            ticker: "USK",
            decimals: 6,
            isNative: false,
            address: Self.kujiraAddress
        )
    }

    /// A non-native token's fee comes out of the chain's native balance, so
    /// reserving from the transferred token would strand a slice of it.
    func testANonNativeAssetReservesNothingFromItsOwnBalance() {
        let usk = makeUsk()
        let viewModel = makeViewModel(coin: usk, extraCoins: [makeKuji()])
        XCTAssertEqual(viewModel.spendableBalance, usk.balanceDecimal)
        XCTAssertTrue(viewModel.hasSufficientBalanceForFee)
    }

    /// …but the gas still has to exist somewhere. Verify's own fee pre-flight
    /// skips the check when the vault holds no native coin for the chain, so a
    /// token transfer from a gas-less vault would otherwise reach the signing
    /// ceremony before failing.
    func testANonNativeAssetStillNeedsTheChainsNativeCoinForGas() {
        let viewModel = makeViewModel(coin: makeUsk())
        XCTAssertNil(
            viewModel.vault.coins.first { $0.chain == .kujira && $0.isNativeToken },
            "Fixture must hold no KUJI"
        )
        XCTAssertFalse(viewModel.hasSufficientBalanceForFee)
        XCTAssertTrue(viewModel.isContinueDisabled)
    }

    func testANonNativeAssetWithDustGasCannotBuild() {
        let viewModel = makeViewModel(coin: makeUsk(), extraCoins: [makeKuji(rawBalance: "1")])
        XCTAssertFalse(viewModel.hasSufficientBalanceForFee)
        XCTAssertNil(viewModel.transactionBuilder)
    }

    func testAnAmountAtTheFullBalanceIsRejectedBecauseItWouldEatTheFee() throws {
        let kuji = makeKuji()
        let viewModel = makeViewModel(coin: kuji)

        viewModel.select(try destination(viewModel, .gaiaChain))
        viewModel.addressViewModel.field.value = Self.gaiaAddress
        viewModel.amountField.value = kuji.balanceDecimal.description

        XCTAssertNil(viewModel.transactionBuilder, "The whole balance leaves nothing for the fee")
    }

    func testALiquidBalanceBelowTheFeeCannotBuild() throws {
        let dust = makeKuji(rawBalance: "1")
        let viewModel = makeViewModel(coin: dust)

        viewModel.select(try destination(viewModel, .gaiaChain))
        viewModel.addressViewModel.field.value = Self.gaiaAddress
        viewModel.amountField.value = "0.000001"

        XCTAssertFalse(viewModel.hasSufficientBalanceForFee)
        XCTAssertNil(viewModel.transactionBuilder)
        XCTAssertTrue(
            viewModel.isContinueDisabled,
            "No amount edit can cover the fee, so the button must read as disabled rather than no-op"
        )
    }

    // MARK: - Address validation, per destination chain

    func testTheAddressIsValidatedAgainstTheDestinationChainNotTheSource() throws {
        let viewModel = makeViewModel()
        viewModel.select(try destination(viewModel, .gaiaChain))
        viewModel.amountField.value = "1"

        // Valid on the SOURCE chain, and wrong here.
        viewModel.addressViewModel.field.value = Self.kujiraAddress
        XCTAssertNil(viewModel.transactionBuilder, "A kujira1… address does not exist on Gaia")

        viewModel.addressViewModel.field.value = Self.gaiaAddress
        XCTAssertNotNil(viewModel.transactionBuilder)
    }

    func testChangingTheDestinationClearsAnAddressValidForThePreviousChain() throws {
        let viewModel = makeViewModel(extraCoins: [makeAtom()])

        viewModel.select(try destination(viewModel, .gaiaChain))
        viewModel.amountField.value = "1"
        XCTAssertEqual(
            viewModel.addressViewModel.field.value,
            Self.gaiaAddress,
            "The vault's own address on the destination chain is pre-filled"
        )
        XCTAssertNotNil(viewModel.transactionBuilder)

        // Switching route must not leave the previous chain's address behind as
        // still-valid: that is how funds go to an address on the wrong chain.
        viewModel.select(try destination(viewModel, .osmosis))
        XCTAssertNotEqual(viewModel.addressViewModel.field.value, Self.gaiaAddress)
        XCTAssertNil(viewModel.transactionBuilder)
    }

    func testTheDestinationAddressIsPrefilledFromTheVaultWhenItHoldsThatChain() throws {
        let viewModel = makeViewModel(extraCoins: [makeAtom(), makeOsmo()])

        viewModel.select(try destination(viewModel, .osmosis))
        XCTAssertEqual(viewModel.addressViewModel.field.value, Self.osmosisAddress)

        viewModel.select(try destination(viewModel, .gaiaChain))
        XCTAssertEqual(viewModel.addressViewModel.field.value, Self.gaiaAddress)
    }

    func testAnEmptyAddressCannotBuildAndTheTapRevealsTheError() throws {
        let viewModel = makeViewModel()
        viewModel.select(try destination(viewModel, .gaiaChain))
        viewModel.addressViewModel.field.value = .empty
        viewModel.amountField.value = "1"

        XCTAssertNil(viewModel.transactionBuilder)
        XCTAssertNotNil(viewModel.addressViewModel.field.error, "Continue is what reveals the error")
    }

    func testGarbageAddressCannotBuild() throws {
        let viewModel = makeViewModel()
        viewModel.select(try destination(viewModel, .gaiaChain))
        viewModel.addressViewModel.field.value = "not-an-address"
        viewModel.amountField.value = "1"

        XCTAssertNil(viewModel.transactionBuilder)
    }

    func testNoDestinationSelectedCannotBuild() {
        let viewModel = makeViewModel()
        viewModel.addressViewModel.field.value = Self.gaiaAddress
        viewModel.amountField.value = "1"
        XCTAssertNil(viewModel.transactionBuilder, "A transfer with no route has no channel to sign")
    }

    // MARK: - The builder it produces

    func testAValidFormBuildsTheTransferWithTypedFields() throws {
        let viewModel = makeViewModel()

        viewModel.select(try destination(viewModel, .gaiaChain))
        viewModel.addressViewModel.field.value = Self.gaiaAddress
        viewModel.amountField.value = "1.5"
        viewModel.memoField.value = "deposit:12345"

        let builder = try XCTUnwrap(viewModel.transactionBuilder as? IBCTransferTransactionBuilder)

        XCTAssertEqual(builder.destination.chain, .gaiaChain)
        XCTAssertEqual(builder.destination.sourceChannel, "channel-0")
        XCTAssertEqual(builder.destinationAddress, Self.gaiaAddress)
        XCTAssertEqual(builder.userMemo, "deposit:12345")
        XCTAssertEqual(builder.amount, "1.5")
        XCTAssertEqual(builder.coin.chain, .kujira)

        // And the colon memo survives all the way to the wire string.
        XCTAssertEqual(CosmosIBCTransferMemo(packed: builder.memo)?.userMemo, "deposit:12345")
    }

    /// The amount field's percentage presets render through
    /// `Decimal.formatToDecimal(digits:)`, which groups — 25% of 4000 would land
    /// as `1,000`, exactly the spelling the parse refuses. The view-model writes
    /// app-generated values back ungrouped, so a preset stays usable without the
    /// parser having to guess at anyone's separators.
    ///
    /// There is no view here, so the field's own grouped write never happens;
    /// what this pins is that the view-model's write is ungrouped, parseable and
    /// arrives at the right number.
    func testAPercentagePresetLeavesAnAmountTheParserAccepts() async throws {
        // Non-native so no fee reserve skews the arithmetic: 25% of 4000 is
        // exactly 1000, the ambiguous shape.
        let usk = FunctionCallFixture.makeCoin(
            .kujira,
            ticker: "USK",
            decimals: 6,
            isNative: false,
            rawBalance: "4000000000",
            address: Self.kujiraAddress
        )
        let viewModel = makeViewModel(coin: usk, extraCoins: [makeKuji()])
        viewModel.select(try destination(viewModel, .gaiaChain))
        viewModel.addressViewModel.field.value = Self.gaiaAddress

        XCTAssertEqual(viewModel.spendableBalance, Decimal(4000))

        let settled = XCTestExpectation(description: "the preset amount settles")
        let cancellable = viewModel.amountField.$value
            .drop(while: { $0.isEmpty })
            .first(where: { !$0.contains(",") })
            .sink { _ in settled.fulfill() }

        viewModel.percentageSelected = 25
        await fulfillment(of: [settled], timeout: 3)
        cancellable.cancel()

        XCTAssertEqual(viewModel.amountField.value, "1000", "The grouped spelling must not survive")
        XCTAssertEqual(
            IBCTransferAmount.parse(viewModel.amountField.value, decimals: 6, locale: enUS),
            Decimal(1000)
        )

        // The builder still renders through the legacy `formatToDecimal`, whose
        // separators come from the machine's own locale — so pin the value that
        // rendering resolves to downstream, not the string it happens to produce.
        let builder = try XCTUnwrap(viewModel.transactionBuilder as? IBCTransferTransactionBuilder)
        XCTAssertEqual(
            builder.buildSendTransaction(vault: viewModel.vault).amountInRaw.description,
            "1000000000",
            "1000 USK at 6 decimals"
        )
    }

    /// The strict parse and the field validator agree, so an ambiguous amount
    /// fails the field rather than silently making Continue do nothing.
    func testAnAmbiguousAmountIsRejectedByTheFieldAndTheBuilder() throws {
        let viewModel = makeViewModel()

        viewModel.select(try destination(viewModel, .gaiaChain))
        viewModel.addressViewModel.field.value = Self.gaiaAddress
        viewModel.amountField.value = "1,5" // en_US: comma-decimal, not grouping

        XCTAssertNil(viewModel.transactionBuilder)
        XCTAssertNotNil(viewModel.amountField.error, "The user must be told, not silently ignored")
    }

    func testAnOptionalMemoIsOptional() throws {
        let viewModel = makeViewModel()

        viewModel.select(try destination(viewModel, .gaiaChain))
        viewModel.addressViewModel.field.value = Self.gaiaAddress
        viewModel.amountField.value = "1"

        let builder = try XCTUnwrap(viewModel.transactionBuilder as? IBCTransferTransactionBuilder)
        XCTAssertEqual(builder.userMemo, .empty)
        XCTAssertFalse(builder.memo.hasSuffix(":"))
    }

    /// The builder is the enforcement, not a disabled button — so a zero amount
    /// has to be caught here rather than by the field alone.
    func testZeroAmountCannotBuild() throws {
        let viewModel = makeViewModel()

        viewModel.select(try destination(viewModel, .gaiaChain))
        viewModel.addressViewModel.field.value = Self.gaiaAddress
        viewModel.amountField.value = "0"

        XCTAssertNil(viewModel.transactionBuilder)
    }
}
