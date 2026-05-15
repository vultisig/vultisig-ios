//
//  EditReferralDetailsViewModelTests.swift
//  VultisigAppTests
//
//  Unit tests for the `@Observable` `EditReferralDetailsViewModel` (the
//  form-VM rewrite of `EditReferralViewModel`). Drives pure helpers + the
//  navigation-boundary `buildSendTransaction()` and `verifyReferralEntries()`
//  paths. Network-dependent paths (setup, calculateFees) are covered by
//  future integration tests.
//

import BigInt
import XCTest
@testable import VultisigApp

@MainActor
final class EditReferralDetailsViewModelTests: XCTestCase {

    // MARK: - Init / baseline

    func testInitProducesEmptyFormState() {
        let vm = ReferralFormFixture.makeEditVM()
        XCTAssertEqual(vm.extendedCount, 0)
        XCTAssertNil(vm.preferredAsset)
        XCTAssertNil(vm.initialPreferredAsset)
        XCTAssertFalse(vm.loadingFees)
        XCTAssertFalse(vm.hasError)
        XCTAssertNil(vm.errorMessage)
        XCTAssertEqual(vm.feePerBlock, 0)
        XCTAssertEqual(vm.gas, .zero)
    }

    func testReferralCodeUppercasesThornameName() {
        let vm = ReferralFormFixture.makeEditVM(thornameDetails: ReferralFormFixture.makeThorname(name: "abcd"))
        XCTAssertEqual(vm.referralCode, "ABCD")
    }

    // MARK: - Fee helpers (pure)

    func testTotalFeeAmountScalesWithExtendedCount() {
        let vm = ReferralFormFixture.makeEditVM { vm in
            vm.feePerBlock = 1
            vm.extendedCount = 2
        }
        // total = (feePerBlock * blocksPerYear * extendedCount) / 1e8
        let expected = Decimal(ReferralExpiryDataCalculator.blockPerYear * 2) / 100_000_000
        XCTAssertEqual(vm.totalFeeAmount, expected)
    }

    func testTotalFeeAmountIsZeroWithNoExtension() {
        let vm = ReferralFormFixture.makeEditVM { vm in
            vm.feePerBlock = 100
            vm.extendedCount = 0
        }
        XCTAssertEqual(vm.totalFeeAmount, 0)
    }

    func testTotalFeeAmountTextSuffixesRUNE() {
        let vm = ReferralFormFixture.makeEditVM { vm in
            vm.feePerBlock = 0
            vm.extendedCount = 0
        }
        XCTAssertEqual(vm.totalFeeAmountText, "0 RUNE")
    }

    // MARK: - isValidForm

    func testIsValidFormRespectsExtendedCount() {
        let vm = ReferralFormFixture.makeEditVM()
        XCTAssertFalse(vm.isValidForm)
        vm.extendedCount = 1
        XCTAssertTrue(vm.isValidForm)
    }

    func testIsValidFormFalseWhenExtensionZeroAndPreferredAssetUnchanged() {
        let vm = ReferralFormFixture.makeEditVM { vm in
            vm.preferredAsset = nil
            vm.initialPreferredAsset = nil
            vm.extendedCount = 0
        }
        XCTAssertFalse(vm.isValidForm)
    }

    // MARK: - buildSendTransaction (boundary)

    func testBuildSendTransactionConstructsEditMemoWithReferralCode() {
        let rune = ReferralFormFixture.makeRune()
        let vm = ReferralFormFixture.makeEditVM(
            rune: rune,
            thornameDetails: ReferralFormFixture.makeThorname(name: "abcd")
        ) { vm in
            vm.gas = 200_000
            vm.extendedCount = 1
            vm.feePerBlock = 10
        }
        let tx = vm.buildSendTransaction()
        XCTAssertEqual(tx.coin.ticker, "RUNE")
        XCTAssertEqual(tx.fromAddress, rune.address)
        XCTAssertEqual(tx.gas, 200_000)
        XCTAssertEqual(tx.transactionType, .unspecified)
        // Edit memo always starts with `~:` + uppercase referral code
        XCTAssertTrue(tx.memo.hasPrefix("~:ABCD"), "memo was: \(tx.memo)")
    }

    func testBuildSendTransactionMemoFunctionDictionaryHasSingleMemoEntry() {
        let vm = ReferralFormFixture.makeEditVM { vm in
            vm.extendedCount = 1
        }
        let tx = vm.buildSendTransaction()
        XCTAssertEqual(tx.memoFunctionDictionary, ["memo": ""])
    }

    // MARK: - verifyReferralEntries (sync — no awaits)

    func testVerifyReferralEntriesReturnsTxOnSufficientBalance() {
        let rune = ReferralFormFixture.makeRune(rawBalance: "10000000000")  // 100 RUNE
        let vm = ReferralFormFixture.makeEditVM(rune: rune) { vm in
            vm.gas = 100_000
            vm.feePerBlock = 1
            vm.extendedCount = 1
        }
        let tx = vm.verifyReferralEntries()
        XCTAssertNotNil(tx)
        XCTAssertFalse(vm.hasError)
    }

    func testVerifyReferralEntriesBlocksOnInsufficientBalance() {
        let rune = ReferralFormFixture.makeRune(rawBalance: "100")  // ~0 RUNE
        let vm = ReferralFormFixture.makeEditVM(rune: rune) { vm in
            vm.gas = 100_000_000_000  // huge gas
            vm.feePerBlock = 100_000_000
            vm.extendedCount = 10
        }
        let tx = vm.verifyReferralEntries()
        XCTAssertNil(tx)
        XCTAssertTrue(vm.hasError)
        XCTAssertEqual(vm.errorMessage, "insufficientBalance")
    }

    // MARK: - Singleton avoidance (decision-pin)

    func testInitDoesNotReadAppViewModelShared() {
        // The new VM takes vault + nativeCoin via init. There is no fallback
        // to AppViewModel.shared.selectedVault — Foundation PR + #4350 killed
        // such fallbacks in the Send pilot. This test pins that contract.
        let rune = ReferralFormFixture.makeRune()
        let vault = ReferralFormFixture.makeVault(coins: [rune])
        let vm = EditReferralDetailsViewModel(
            nativeCoin: rune,
            vault: vault,
            thornameDetails: ReferralFormFixture.makeThorname(),
            currentBlockHeight: 0,
            interactor: MockSendInteractor(),
            addCoinIfNeeded: { _, _ in nil }
        )
        XCTAssertIdentical(vm.vault, vault)
        XCTAssertEqual(vm.nativeCoin.address, rune.address)
    }
}
