//
//  CosmosWithdrawRewardsTransactionViewModelTests.swift
//  VultisigAppTests
//
//  Pins the load-bearing claim-flow guards: soft batch cap (Spec D-9)
//  and balance pre-flight (Spec Risk 3).
//

@testable import VultisigApp
import XCTest

@MainActor
final class CosmosWithdrawRewardsTransactionViewModelTests: XCTestCase {

    private static func makeLunaCoin(balance: Decimal = 100) -> Coin {
        let meta = CoinMeta(
            chain: .terra,
            ticker: "LUNA",
            logo: "LunaLogo",
            decimals: 6,
            priceProviderId: "terra-luna-2",
            contractAddress: "",
            isNativeToken: true
        )
        let coin = Coin(
            asset: meta,
            address: "terra1delegator0000000000000000000000000000000",
            hexPublicKey: "02" + String(repeating: "00", count: 32)
        )
        coin.rawBalance = String(describing: NSDecimalNumber(decimal: balance * 1_000_000))
        return coin
    }

    private static func makeLuncCoin(balance: Decimal) -> Coin {
        let meta = CoinMeta(
            chain: .terraClassic,
            ticker: "LUNC",
            logo: "LunaLogo",
            decimals: 6,
            priceProviderId: "terra-luna",
            contractAddress: "",
            isNativeToken: true
        )
        let coin = Coin(
            asset: meta,
            address: "terra1delegator0000000000000000000000000000000",
            hexPublicKey: "02" + String(repeating: "00", count: 32)
        )
        coin.rawBalance = String(describing: NSDecimalNumber(decimal: balance * 1_000_000))
        return coin
    }

    private static func makeCandidates(count: Int) -> [CosmosWithdrawRewardsCandidate] {
        (0..<count).map { idx in
            CosmosWithdrawRewardsCandidate(
                validatorAddress: "terravaloper1val\(idx)",
                validatorMoniker: "Validator \(idx)",
                pendingReward: 0.1
            )
        }
    }

    func testDefaultsToSelectAllUpToCapEightOfNine() {
        let vm = CosmosWithdrawRewardsTransactionViewModel(
            coin: Self.makeLunaCoin(),
            vault: .example,
            candidates: Self.makeCandidates(count: 9)
        )
        XCTAssertEqual(vm.selectedValidators.count, 8)
        XCTAssertTrue(vm.hitBatchCapWarning)
    }

    func testTogglingValidatorAddsAndRemoves() {
        let candidates = Self.makeCandidates(count: 3)
        let vm = CosmosWithdrawRewardsTransactionViewModel(
            coin: Self.makeLunaCoin(),
            vault: .example,
            candidates: candidates
        )
        XCTAssertEqual(vm.selectedValidators.count, 3)
        vm.toggle(validator: candidates[0])
        XCTAssertEqual(vm.selectedValidators.count, 2)
        vm.toggle(validator: candidates[0])
        XCTAssertEqual(vm.selectedValidators.count, 3)
    }

    func testCannotSelectBeyondCap() {
        // Start with 8 selected. Trying to add a 9th must be rejected.
        let candidates = Self.makeCandidates(count: 9)
        let vm = CosmosWithdrawRewardsTransactionViewModel(
            coin: Self.makeLunaCoin(),
            vault: .example,
            candidates: candidates
        )
        // candidate at idx 8 is the unselected one (default selects first 8).
        let unselected = candidates[8]
        XCTAssertFalse(vm.selectedValidators.contains(unselected.validatorAddress))
        vm.toggle(validator: unselected)
        XCTAssertFalse(vm.selectedValidators.contains(unselected.validatorAddress))
        XCTAssertEqual(vm.selectedValidators.count, 8)
        XCTAssertTrue(vm.hitBatchCapWarning)
    }

    func testValidFormFalseWhenNoValidatorsSelected() {
        let vm = CosmosWithdrawRewardsTransactionViewModel(
            coin: Self.makeLunaCoin(),
            vault: .example,
            candidates: []
        )
        XCTAssertFalse(vm.validForm)
    }

    func testValidFormFalseWhenBalanceBelowFee() {
        // LUNC: balance preflight test. 1 LUNC ≈ 1,000,000 uluna —
        // feeAmount per msg = 100,000,000 uluna (= 100 LUNC). Tiny
        // balance must fail the preflight even for a single-msg claim.
        let candidates = Self.makeCandidates(count: 1)
        let coin = Self.makeLuncCoin(balance: 1)
        let vm = CosmosWithdrawRewardsTransactionViewModel(
            coin: coin,
            vault: .example,
            candidates: candidates
        )
        XCTAssertFalse(vm.hasSufficientBalanceForFee)
        XCTAssertFalse(vm.validForm)
        XCTAssertNil(vm.transactionBuilder, "Insufficient balance must block the builder")
    }

    func testValidFormTrueWithSufficientBalance() {
        let candidates = Self.makeCandidates(count: 2)
        let vm = CosmosWithdrawRewardsTransactionViewModel(
            coin: Self.makeLunaCoin(balance: 1000),
            vault: .example,
            candidates: candidates
        )
        XCTAssertTrue(vm.hasSufficientBalanceForFee)
        XCTAssertTrue(vm.validForm)
        XCTAssertNotNil(vm.transactionBuilder)
    }

    func testTransactionBuilderPreservesCandidateOrder() {
        // Pin the byte-equality contract — the SignDoc resolver emits one
        // `MsgWithdrawDelegatorReward` per validator in the order the
        // builder hands them over. If the VM accidentally sorts by Set
        // hash, that breaks regression against the SDK fixtures.
        let candidates = Self.makeCandidates(count: 5)
        let vm = CosmosWithdrawRewardsTransactionViewModel(
            coin: Self.makeLunaCoin(balance: 1000),
            vault: .example,
            candidates: candidates
        )
        guard let builder = vm.transactionBuilder as? CosmosWithdrawRewardsTransactionBuilder else {
            XCTFail("Expected CosmosWithdrawRewardsTransactionBuilder")
            return
        }
        XCTAssertEqual(builder.validatorAddresses, candidates.map(\.validatorAddress))
    }

    func testSelectAllRespectsCap() {
        let candidates = Self.makeCandidates(count: 12)
        let vm = CosmosWithdrawRewardsTransactionViewModel(
            coin: Self.makeLunaCoin(balance: 1000),
            vault: .example,
            candidates: candidates
        )
        vm.selectedValidators.removeAll()
        XCTAssertEqual(vm.selectedValidators.count, 0)
        vm.toggleSelectAll()
        XCTAssertEqual(vm.selectedValidators.count, 8)
        XCTAssertTrue(vm.hitBatchCapWarning)
    }
}
