//
//  StakingFormViewModelDescriptorTests.swift
//  VultisigAppTests
//
//  Pins the descriptor each staking form view-model exposes to the generic
//  `StakingTransactionScreen` — title key, amount-section spec (presence +
//  button/slider + seed-max), validator-picker spec (presence + title), read-only
//  rows, notices, and the Continue-disabled gate. This is the contract the
//  generic screen renders, so locking it here guards behavior parity after the
//  five bespoke screens were collapsed onto the shared screen.
//

@testable import VultisigApp
import XCTest

@MainActor
final class StakingFormViewModelDescriptorTests: XCTestCase {

    // MARK: - Cosmos delegate

    func testCosmosDelegateDescriptor() {
        let vm = CosmosDelegateTransactionViewModel(coin: Self.qbtcCoin(balance: 5), vault: .example)

        XCTAssertEqual(vm.titleKey, "cosmosStakingDelegateTitle")
        XCTAssertFalse(vm.isContinueDisabled, "5 QBTC covers the fee")
        XCTAssertNotNil(vm.amountSpec)
        guard case .button? = vm.amountSpec?.type else { return XCTFail("delegate amount uses the button selector") }
        XCTAssertEqual(vm.amountSpec?.seedMaxOnLoad, false)
        XCTAssertNotNil(vm.pickerSpec)
        XCTAssertEqual(vm.pickerSpec?.title, "cosmosStakingValidatorPicker".localized)
        XCTAssertEqual(vm.pickerSpec?.isSelected, false)
        XCTAssertNil(vm.pickerSpec?.preview)
        XCTAssertTrue(vm.readOnlyRows.isEmpty)
        XCTAssertTrue(vm.notices.isEmpty)
    }

    func testCosmosDelegateInsufficientFeeSurfacesNoticeAndDisablesContinue() {
        // Below the QBTC fee (0.000008): nothing stakeable, fee notice shows.
        let vm = CosmosDelegateTransactionViewModel(
            coin: Self.qbtcCoin(balance: Decimal(string: "0.0000018")!),
            vault: .example
        )

        XCTAssertTrue(vm.isContinueDisabled)
        XCTAssertEqual(vm.notices, [.insufficientFee(ticker: "QBTC")])
    }

    // MARK: - Cosmos undelegate

    func testCosmosUndelegateDescriptor() {
        let vm = CosmosUndelegateTransactionViewModel(
            coin: Self.qbtcCoin(balance: 5),
            vault: .example,
            validatorAddress: "qbtcvaloper1abc",
            validatorMoniker: "Validator",
            stakedBalance: 1000
        )

        XCTAssertEqual(vm.titleKey, "cosmosStakingUndelegateTitle")
        XCTAssertNotNil(vm.amountSpec)
        guard case .slider? = vm.amountSpec?.type else { return XCTFail("undelegate amount uses the slider selector") }
        XCTAssertEqual(vm.amountSpec?.seedMaxOnLoad, true)
        XCTAssertNil(vm.pickerSpec, "undelegate has no validator picker")
        XCTAssertTrue(vm.readOnlyRows.isEmpty)
    }

    // MARK: - Solana delegate

    func testSolanaDelegateDescriptor() {
        let vm = SolanaDelegateTransactionViewModel(coin: Self.solanaCoin(balance: 5), vault: .example)

        XCTAssertEqual(vm.titleKey, "cosmosStakingDelegateTitle", "Solana delegate reuses the Cosmos title key")
        XCTAssertNotNil(vm.amountSpec)
        guard case .button? = vm.amountSpec?.type else { return XCTFail("delegate amount uses the button selector") }
        XCTAssertNotNil(vm.pickerSpec)
        XCTAssertEqual(vm.pickerSpec?.isSelected, false)
        XCTAssertTrue(vm.readOnlyRows.isEmpty)
    }

    // Note: Solana unstake/withdraw no longer route through the generic
    // `StakingTransactionScreen` — they have no editable field, so the DeFi
    // screen builds the tx and pushes straight to Verify. There is no descriptor
    // to pin for them.

    // MARK: - Fixtures

    private static func qbtcCoin(balance: Decimal) -> Coin {
        let meta = CoinMeta(
            chain: .qbtc,
            ticker: "QBTC",
            logo: "qbtc",
            decimals: 8,
            priceProviderId: "",
            contractAddress: "",
            isNativeToken: true
        )
        let coin = Coin(
            asset: meta,
            address: "qbtc1delegator000000000000000000000000000000",
            hexPublicKey: "02" + String(repeating: "00", count: 32)
        )
        coin.rawBalance = String(describing: NSDecimalNumber(decimal: balance * 100_000_000))
        return coin
    }

    private static func solanaCoin(balance: Decimal) -> Coin {
        let meta = CoinMeta(
            chain: .solana,
            ticker: "SOL",
            logo: "solana",
            decimals: 9,
            priceProviderId: "solana",
            contractAddress: "",
            isNativeToken: true
        )
        let coin = Coin(
            asset: meta,
            address: "So11111111111111111111111111111111111111112",
            hexPublicKey: "02" + String(repeating: "00", count: 32)
        )
        coin.rawBalance = String(describing: NSDecimalNumber(decimal: balance * 1_000_000_000))
        return coin
    }
}
