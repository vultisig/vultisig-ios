//
//  SendCustomByteFeeTests.swift
//  VultisigAppTests
//
//  The gas sheet's "Network rate (sats/vbyte)" field is the only control that
//  can move a UTXO fee — the chain otherwise prices a transaction as
//  `rate × size` and the rate came straight from `feeMode`. It used to be
//  collected into `customByteFee` and then dropped: `SendChainSpecificRequest`
//  had no byte-fee field, so `BlockChainService` recomputed the rate and the
//  user's edit did nothing.
//
//  These pin the threading (request → chain-specific), the non-positive clamp,
//  the cache key, and the rule that a rate is only "custom" once the user has
//  actually changed it away from the fee mode's own value.
//

import BigInt
import XCTest
import VultisigCommonData
@testable import VultisigApp

@MainActor
final class SendCustomByteFeeTests: XCTestCase {

    // MARK: - Request threading

    func testLoadGasInfoCarriesTheCustomByteFee() async {
        let btc = SendFormFixture.makeBTC()
        let interactor = MockSendInteractor()
        let vm = SendFormFixture.make(coin: btc, interactor: interactor)
        vm.amount = "0.1"
        vm.customByteFee = BigInt(9)

        await vm.loadGasInfo()

        XCTAssertEqual(interactor.fetchChainSpecificCalls.last?.customByteFee, BigInt(9))
    }

    func testTransactionInitCarriesTheCustomByteFeeIntoTheRequest() {
        let btc = SendFormFixture.makeBTC()
        let tx = SendTransaction(
            coin: btc,
            vault: SendFormFixture.makeVault(),
            fromAddress: btc.address,
            toAddress: "bc1qtest",
            toAddressLabel: nil,
            amount: "0.1",
            amountInFiat: "",
            memo: "",
            gas: .zero,
            fee: .zero,
            feeMode: .default,
            estimatedGasLimit: nil,
            customGasLimit: nil,
            customByteFee: BigInt(21),
            sendMaxAmount: false,
            isStakingOperation: false,
            transactionType: .unspecified,
            memoFunctionDictionary: [:],
            wasmContractPayload: nil,
            feeCoin: btc
        )

        XCTAssertEqual(SendChainSpecificRequest(tx: tx).customByteFee, BigInt(21),
                       "the Verify-stage request must carry the pinned rate too, or Verify re-prices at the mode's rate")
    }

    func testRequestDefaultsToNoOverride() {
        let request = SendChainSpecificRequest(
            coin: SendFormFixture.makeBTC(),
            toAddress: "bc1qtest",
            amount: BigInt(1),
            memo: nil,
            sendMaxAmount: false,
            isDeposit: false,
            transactionType: .unspecified,
            gasLimit: nil,
            feeMode: .default,
            fromAddress: "bc1qfrom"
        )
        XCTAssertNil(request.customByteFee)
    }

    // MARK: - Cache key

    func testCacheKeyDistinguishesPinnedRates() {
        let btc = SendFormFixture.makeBTC()
        let service = BlockChainService.shared

        func key(_ byteFee: BigInt?) -> String {
            service.getCacheKey(
                for: btc, action: .transfer, sendMaxAmount: false, isDeposit: false,
                transactionType: .unspecified, fromAddress: btc.address, toAddress: "bc1qtest",
                memo: nil, feeMode: .fast, customByteFee: byteFee, quote: nil
            )
        }

        XCTAssertNotEqual(key(BigInt(5)), key(BigInt(50)),
                          "two pinned rates must not share a cached chain-specific")
        XCTAssertNotEqual(key(nil), key(BigInt(5)),
                          "a pinned rate must not be served the fee mode's cached entry")
        XCTAssertEqual(key(BigInt(5)), key(BigInt(5)))
    }

    // MARK: - Gas sheet: custom only once the user edits it

    func testGasSheetReportsNoOverrideUntilTheUserEdits() {
        let vm = makeGasSettingsViewModel(customByteFee: nil)

        XCTAssertFalse(vm.hasUserEditedByteFee)
        XCTAssertNil(vm.resolvedCustomByteFee,
                     "an untouched sheet must keep following the fee mode")
    }

    func testGasSheetReportsAnEditedRate() {
        let vm = makeGasSettingsViewModel(customByteFee: nil)
        vm.setByteFee("12")

        XCTAssertTrue(vm.hasUserEditedByteFee)
        XCTAssertEqual(vm.resolvedCustomByteFee, BigInt(12))
    }

    /// Re-typing the fetched rate is still a choice. Inferring "edited" by
    /// comparing values would silently un-pin it.
    func testRetypingTheSameNumberStillPinsIt() {
        let vm = makeGasSettingsViewModel(customByteFee: nil)
        vm.setByteFee("30")

        XCTAssertEqual(vm.resolvedCustomByteFee, BigInt(30))
    }

    /// Reopening the sheet with a rate already pinned must not have the initial
    /// rate fetch overwrite the field and then read back as "unedited" — that
    /// dropped the pin on Save.
    func testReopeningWithAPinnedRateKeepsIt() {
        let vm = makeGasSettingsViewModel(customByteFee: BigInt(15))

        XCTAssertTrue(vm.hasUserEditedByteFee)
        XCTAssertEqual(vm.resolvedCustomByteFee, BigInt(15))
    }

    /// Choosing a priority is an explicit "follow the mode again", so it must
    /// release the pin — otherwise Low / Normal / Fast goes inert after the
    /// first edit.
    func testChoosingAPriorityReleasesThePin() {
        let vm = makeGasSettingsViewModel(customByteFee: BigInt(15))
        vm.selectMode(.safeLow)

        XCTAssertFalse(vm.hasUserEditedByteFee)
        XCTAssertNil(vm.resolvedCustomByteFee)
        XCTAssertEqual(vm.selectedMode, .safeLow)
    }

    func testGasSheetIgnoresNonPositiveAndUnparseableRates() {
        let vm = makeGasSettingsViewModel(customByteFee: nil)

        for entered in ["0", "-4", "", "abc"] {
            vm.setByteFee(entered)
            XCTAssertNil(vm.resolvedCustomByteFee, "\"\(entered)\" must not pin a rate")
        }
    }

    /// The value ends up in WalletCore's `Int64` byteFee, where an out-of-range
    /// conversion traps the process — a long enough number typed into the field
    /// must be rejected, not carried.
    func testGasSheetRejectsRatesBeyondInt64() {
        let vm = makeGasSettingsViewModel(customByteFee: nil)
        vm.setByteFee(BigInt(Int64.max).description + "0")

        XCTAssertNil(vm.resolvedCustomByteFee)

        vm.setByteFee(BigInt(Int64.max).description)
        XCTAssertEqual(vm.resolvedCustomByteFee, BigInt(Int64.max), "the boundary itself is representable")
    }

    private func makeGasSettingsViewModel(customByteFee: BigInt?) -> SendGasSettingsViewModel {
        SendGasSettingsViewModel(
            coin: SendFormFixture.makeBTC(),
            vault: SendFormFixture.makeVault(),
            gasLimit: BigInt(0),
            customGasLimit: nil,
            customByteFee: customByteFee,
            selectedMode: .fast,
            fromAddress: "bc1qfrom",
            toAddress: "bc1qtest",
            amount: BigInt(1),
            memo: nil
        )
    }
}
