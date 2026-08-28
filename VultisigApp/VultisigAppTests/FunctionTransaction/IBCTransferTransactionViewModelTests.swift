//
//  IBCTransferTransactionViewModelTests.swift
//  VultisigAppTests
//

@testable import VultisigApp
import XCTest

@MainActor
final class IBCTransferTransactionViewModelTests: XCTestCase {
    private static let gaiaAddress = "cosmos1qypqxpq9qcrsszg2pvxq6rs0zqg3yyc5lzv7xu"
    private static let osmosisAddress = "osmo1qypqxpq9qcrsszg2pvxq6rs0zqg3yyc5helwsw"

    private let enUS = Locale(identifier: "en_US")

    private func makeOsmo(rawBalance: String = "10000000") -> Coin {
        FunctionActionFixture.makeCoin(
            .osmosis,
            ticker: "OSMO",
            decimals: 6,
            isNative: true,
            rawBalance: rawBalance,
            address: Self.osmosisAddress
        )
    }

    private func makeAtom() -> Coin {
        FunctionActionFixture.makeCoin(
            .gaiaChain,
            ticker: "ATOM",
            decimals: 6,
            isNative: true,
            address: Self.gaiaAddress
        )
    }

    private func makeIbcToken() -> Coin {
        FunctionActionFixture.makeCoin(
            .osmosis,
            ticker: "ION",
            decimals: 6,
            isNative: false,
            address: Self.osmosisAddress
        )
    }

    private func makeViewModel(
        coin: Coin? = nil,
        extraCoins: [Coin] = [],
        destinationChain: Chain? = nil
    ) -> IBCTransferTransactionViewModel {
        let source = coin ?? makeOsmo()
        let vault = FunctionActionFixture.makeVault(coins: [source] + extraCoins)
        let viewModel = IBCTransferTransactionViewModel(
            coin: source,
            vault: vault,
            destinationChain: destinationChain,
            locale: enUS
        )
        viewModel.onLoad()
        return viewModel
    }

    private func gaiaDestination(_ viewModel: IBCTransferTransactionViewModel) throws -> IBCDestination {
        try XCTUnwrap(viewModel.destinations.first { $0.chain == .gaiaChain })
    }

    func testDestinationsExposeOnlyTheRemainingLiveRoutes() {
        XCTAssertEqual(makeViewModel().destinations.map(\.chain), [.gaiaChain])
        XCTAssertEqual(makeViewModel(coin: makeAtom()).destinations.map(\.chain), [.osmosis])
        XCTAssertFalse(makeViewModel().destinations.contains { $0.chain == .kujira })
    }

    func testHistoricalKujiraCoinHasNoRoutesAndCannotBuild() {
        let historical = FunctionActionFixture.makeCoin(
            .kujira,
            ticker: "KUJI",
            decimals: 6,
            isNative: true
        )
        let viewModel = makeViewModel(coin: historical)

        XCTAssertTrue(viewModel.destinations.isEmpty)
        XCTAssertTrue(viewModel.hasNoDestinations)
        XCTAssertTrue(viewModel.isContinueDisabled)
        XCTAssertNil(viewModel.transactionBuilder)
    }

    func testPreselectedDestinationOpensOnThatRoute() {
        let viewModel = makeViewModel(destinationChain: .gaiaChain)

        XCTAssertEqual(viewModel.selectedDestination?.chain, .gaiaChain)
        XCTAssertEqual(viewModel.selectedDestination?.sourceChannel, "channel-0")
    }

    func testTheListIsEnteredColdWithNoRouteSelected() {
        let viewModel = makeViewModel()

        XCTAssertNil(viewModel.selectedDestination)
        XCTAssertFalse(viewModel.isContinueDisabled)
    }

    func testTheSpendableCeilingReservesTheFeeForANativeAsset() {
        let osmo = makeOsmo()
        let viewModel = makeViewModel(coin: osmo)

        XCTAssertGreaterThan(viewModel.feeReserve, 0)
        XCTAssertEqual(viewModel.spendableBalance, osmo.balanceDecimal - viewModel.feeReserve)
    }

    func testNonNativeAssetNeedsTheChainsNativeCoinForGas() {
        let withoutGas = makeViewModel(coin: makeIbcToken())
        let withGas = makeViewModel(coin: makeIbcToken(), extraCoins: [makeOsmo()])

        XCTAssertFalse(withoutGas.hasSufficientBalanceForFee)
        XCTAssertTrue(withGas.hasSufficientBalanceForFee)
        XCTAssertEqual(withGas.spendableBalance, withGas.coin.balanceDecimal)
    }

    func testAnAmountAtTheFullBalanceIsRejectedBecauseItWouldEatTheFee() throws {
        let osmo = makeOsmo()
        let viewModel = makeViewModel(coin: osmo)
        viewModel.select(try gaiaDestination(viewModel))
        viewModel.addressViewModel.field.value = Self.gaiaAddress
        viewModel.amountField.value = osmo.balanceDecimal.description

        XCTAssertNil(viewModel.transactionBuilder)
    }

    func testAddressIsValidatedAgainstTheDestinationChain() throws {
        let viewModel = makeViewModel()
        viewModel.select(try gaiaDestination(viewModel))
        viewModel.amountField.value = "1"

        viewModel.addressViewModel.field.value = Self.osmosisAddress
        XCTAssertNil(viewModel.transactionBuilder)

        viewModel.addressViewModel.field.value = Self.gaiaAddress
        XCTAssertNotNil(viewModel.transactionBuilder)
    }

    func testDestinationAddressIsPrefilledFromTheVault() throws {
        let viewModel = makeViewModel(extraCoins: [makeAtom()])

        viewModel.select(try gaiaDestination(viewModel))

        XCTAssertEqual(viewModel.addressViewModel.field.value, Self.gaiaAddress)
    }

    func testInvalidOrMissingFieldsCannotBuild() throws {
        let viewModel = makeViewModel()
        viewModel.select(try gaiaDestination(viewModel))
        viewModel.amountField.value = "1"

        viewModel.addressViewModel.field.value = .empty
        XCTAssertNil(viewModel.transactionBuilder)

        viewModel.addressViewModel.field.value = "not-an-address"
        XCTAssertNil(viewModel.transactionBuilder)
    }

    func testValidFormBuildsTheTransferWithTypedFields() throws {
        let viewModel = makeViewModel()
        viewModel.select(try gaiaDestination(viewModel))
        viewModel.addressViewModel.field.value = Self.gaiaAddress
        viewModel.amountField.value = "1.5"
        viewModel.memoField.value = "deposit:12345"

        let builder = try XCTUnwrap(viewModel.transactionBuilder as? IBCTransferTransactionBuilder)

        XCTAssertEqual(builder.destination.chain, .gaiaChain)
        XCTAssertEqual(builder.destination.sourceChannel, "channel-0")
        XCTAssertEqual(builder.destinationAddress, Self.gaiaAddress)
        XCTAssertEqual(builder.userMemo, "deposit:12345")
        XCTAssertEqual(builder.amount, "1.5")
        XCTAssertEqual(builder.coin.chain, .osmosis)
        XCTAssertEqual(CosmosIBCTransferMemo(packed: builder.memo)?.userMemo, "deposit:12345")
    }
}
