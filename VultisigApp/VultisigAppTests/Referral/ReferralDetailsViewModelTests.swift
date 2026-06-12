//
//  ReferralDetailsViewModelTests.swift
//  VultisigAppTests
//
//  Unit tests for the `@Observable` `ReferralDetailsViewModel` (the
//  form-VM rewrite of `ReferralViewModel`). Drives pure helpers + the
//  navigation-boundary `buildSendTransaction()` path. Network-dependent
//  paths (verifyReferralCode, calculateFees, fetchReferralCodeDetails)
//  are covered by future integration tests with a stubbed THORChain
//  service.
//

import BigInt
import XCTest
@testable import VultisigApp

@MainActor
final class ReferralDetailsViewModelTests: XCTestCase {

    // MARK: - Init / baseline

    func testInitWithVaultProducesEmptyFormState() {
        let vm = ReferralFormFixture.makeCreateVM()
        XCTAssertEqual(vm.referralCode, "")
        XCTAssertEqual(vm.expireInCount, 1)
        XCTAssertNil(vm.availabilityStatus)
        XCTAssertFalse(vm.isReferralCodeVerified)
        XCTAssertFalse(vm.isLoading)
        XCTAssertEqual(vm.registrationFee, 0)
        XCTAssertEqual(vm.feePerBlock, 0)
        XCTAssertEqual(vm.gas, .zero)
        XCTAssertFalse(vm.vault.isFastVault)
    }

    func testNativeCoinResolvesFromVaultRuneCoin() {
        let rune = ReferralFormFixture.makeRune()
        let vm = ReferralFormFixture.makeCreateVM(rune: rune)
        XCTAssertEqual(vm.nativeCoin?.ticker, "RUNE")
        XCTAssertEqual(vm.nativeCoin?.chain, .thorChain)
    }

    func testNativeCoinIsNilWhenVaultHasNoRune() {
        let nonRuneVault = SendFormFixture.makeVault(coins: [SendFormFixture.makeBTC()])
        let vm = ReferralDetailsViewModel(vault: nonRuneVault, interactor: MockSendInteractor(), saveReferralCode: { _ in })
        XCTAssertNil(vm.nativeCoin)
    }

    // MARK: - Fee helpers (pure)

    func testGetRegistrationFeeDividesBy10ToThe8() {
        let vm = ReferralFormFixture.makeCreateVM { vm in
            vm.registrationFee = 1_000_000_000 // 10 RUNE in 8-decimal raw
        }
        XCTAssertEqual(vm.getRegistrationFee(), 10)
    }

    func testGetTotalFeeIncludesFeePerBlockWhenSingleYear() {
        // Single-year registration: total = (registrationFee + feePerBlock) / 1e8
        let vm = ReferralFormFixture.makeCreateVM { vm in
            vm.registrationFee = 1_000_000_000  // 10 RUNE
            vm.feePerBlock = 10_000_000         // 0.1 RUNE
            vm.expireInCount = 1
        }
        XCTAssertEqual(vm.getTotalFee(), 10 + Decimal(0.1))
    }

    func testGetTotalFeeAppliesBlockMultiplierWhenMultipleYears() {
        // For years > 1, total = (regFee + feePerBlock * blocksPerYear * (years - 1)) / 1e8
        let vm = ReferralFormFixture.makeCreateVM { vm in
            vm.registrationFee = 1_000_000_000
            vm.feePerBlock = 1
            vm.expireInCount = 3
        }
        // years - 1 = 2; feePerBlock * blocksPerYear * 2
        let extraBlocks = Decimal(ReferralExpiryDataCalculator.blockPerYear * 2)
        let expected = (Decimal(1_000_000_000) + extraBlocks) / 100_000_000
        XCTAssertEqual(vm.getTotalFee(), expected)
    }

    func testGetFiatAmountReturnsEmptyStringWhenNoNativeCoin() {
        let nonRuneVault = SendFormFixture.makeVault(coins: [SendFormFixture.makeBTC()])
        let vm = ReferralDetailsViewModel(vault: nonRuneVault, interactor: MockSendInteractor(), saveReferralCode: { _ in })
        XCTAssertEqual(vm.getFiatAmount(for: 100), "")
    }

    // MARK: - Counter

    func testHandleCounterIncreaseAdvancesExpireCount() {
        let vm = ReferralFormFixture.makeCreateVM()
        vm.handleCounterIncrease()
        XCTAssertEqual(vm.expireInCount, 2)
    }

    func testHandleCounterDecreaseStopsAtZero() {
        let vm = ReferralFormFixture.makeCreateVM { vm in
            vm.expireInCount = 0
        }
        vm.handleCounterDecrease()
        XCTAssertEqual(vm.expireInCount, 0)
    }

    // MARK: - Reset

    func testResetAllDataClearsFormState() {
        let vm = ReferralFormFixture.makeCreateVM { vm in
            vm.referralCode = "ABCD"
            vm.expireInCount = 5
            vm.availabilityStatus = .available
            vm.isReferralCodeVerified = true
            vm.referralAvailabilityErrorMessage = "error"
            vm.registrationFee = 999
            vm.feePerBlock = 888
            vm.showReferralAlert = true
            vm.referralAlertMessage = "hi"
        }
        vm.resetAllData()
        XCTAssertEqual(vm.referralCode, "")
        XCTAssertEqual(vm.expireInCount, 1)
        XCTAssertNil(vm.availabilityStatus)
        XCTAssertFalse(vm.isReferralCodeVerified)
        XCTAssertNil(vm.referralAvailabilityErrorMessage)
        XCTAssertEqual(vm.registrationFee, 0)
        XCTAssertEqual(vm.feePerBlock, 0)
        XCTAssertFalse(vm.showReferralAlert)
        XCTAssertEqual(vm.referralAlertMessage, "")
    }

    func testResetReferralDataClearsOnlyAvailabilityState() {
        let vm = ReferralFormFixture.makeCreateVM { vm in
            vm.referralCode = "ABCD"
            vm.availabilityStatus = .alreadyTaken
            vm.isReferralCodeVerified = true
            vm.expireInCount = 5
            vm.referralAvailabilityErrorMessage = "msg"
        }
        vm.resetReferralData()
        XCTAssertNil(vm.availabilityStatus)
        XCTAssertFalse(vm.isReferralCodeVerified)
        XCTAssertNil(vm.referralAvailabilityErrorMessage)
        XCTAssertEqual(vm.referralCode, "ABCD")  // preserved
        XCTAssertEqual(vm.expireInCount, 5)       // preserved
    }

    // MARK: - buildSendTransaction (boundary)

    func testBuildSendTransactionReturnsNilWhenNoNativeCoin() {
        let nonRuneVault = SendFormFixture.makeVault(coins: [SendFormFixture.makeBTC()])
        let vm = ReferralDetailsViewModel(vault: nonRuneVault, interactor: MockSendInteractor(), saveReferralCode: { _ in })
        XCTAssertNil(vm.buildSendTransaction())
    }

    func testBuildSendTransactionPopulatesRUNECoinAndMemo() {
        let rune = ReferralFormFixture.makeRune()
        let vm = ReferralFormFixture.makeCreateVM(rune: rune) { vm in
            vm.referralCode = "abcd"
            vm.registrationFee = 1_000_000_000
            vm.feePerBlock = 0
            vm.expireInCount = 1
            vm.gas = 200_000
        }
        let tx = vm.buildSendTransaction()
        XCTAssertNotNil(tx)
        XCTAssertEqual(tx?.coin.ticker, "RUNE")
        XCTAssertEqual(tx?.fromAddress, rune.address)
        XCTAssertEqual(tx?.gas, 200_000)
        XCTAssertEqual(tx?.transactionType, .unspecified)
    }

    func testBuildSendTransactionMemoFormatMatchesReferralEncoding() {
        let rune = ReferralFormFixture.makeRune()
        let vm = ReferralFormFixture.makeCreateVM(rune: rune) { vm in
            vm.referralCode = "abcd"
        }
        let tx = vm.buildSendTransaction()
        let expected = "~:ABCD:THOR:\(rune.address):\(rune.address)"
        XCTAssertEqual(tx?.memo, expected)
    }

    func testBuildSendTransactionUppercasesReferralCode() {
        let rune = ReferralFormFixture.makeRune()
        let vm = ReferralFormFixture.makeCreateVM(rune: rune) { vm in
            vm.referralCode = "MixedCase"  // 9 chars; not real validation, just the casing test
        }
        let tx = vm.buildSendTransaction()
        XCTAssertTrue(tx?.memo.contains(":MIXEDCASE:") ?? false)
    }

    func testBuildSendTransactionMemoFunctionDictionaryHasSingleMemoEntry() {
        let rune = ReferralFormFixture.makeRune()
        let vm = ReferralFormFixture.makeCreateVM(rune: rune) { vm in
            vm.referralCode = "test"
        }
        let tx = vm.buildSendTransaction()
        XCTAssertEqual(tx?.memoFunctionDictionary, ["memo": ""])
    }

    // MARK: - Singleton avoidance (decision-pin)

    func testInitDoesNotReadAppViewModelShared() {
        // The new VM takes vault via init. There is no fallback to
        // AppViewModel.shared.selectedVault — Foundation PR + #4350 killed
        // such fallbacks in the Send pilot. This test pins that contract.
        let vault = ReferralFormFixture.makeVault(coins: [ReferralFormFixture.makeRune()])
        let vm = ReferralDetailsViewModel(vault: vault, interactor: MockSendInteractor(), saveReferralCode: { _ in })
        XCTAssertIdentical(vm.vault, vault)
    }
}
