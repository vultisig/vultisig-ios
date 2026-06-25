//
//  TonStakeTransactionViewModelTests.swift
//  VultisigAppTests
//
//  Covers the TON stake form view-model: destination-address selection
//  (existing pool reuse vs first-time picked pool) and the fee headroom that
//  backs the min-stake / max-stakeable calculations.
//

@testable import VultisigApp
import XCTest

@MainActor
final class TonStakeTransactionViewModelTests: XCTestCase {

    private static let poolAddress = "EQDInDQGu7271ihfBYrR6oN0B0sn2K6cVtPbX4ckk466dIQr"

    private func makeTonCoin(rawBalance: String = "100000000000") -> Coin {
        let meta = CoinMeta(
            chain: .ton,
            ticker: "GRAM",
            logo: "gram",
            decimals: 9,
            priceProviderId: "the-open-network",
            contractAddress: "",
            isNativeToken: true
        )
        let coin = Coin(
            asset: meta,
            address: "UQAfixturetonchainvaultaddress00000000000000000",
            hexPublicKey: ""
        )
        coin.rawBalance = rawBalance
        return coin
    }

    private func makePool(
        address: String = "0:a44757069a7b04e393782b4a2d3e5e449f19d16a4986a9e25436e6b97e45a16a",
        minStake: Decimal = 50,
        implementation: String = "whales"
    ) -> TonStakingPool {
        TonStakingPool(
            entry: TonStakingPoolListEntry(
                address: address,
                name: "Test Pool",
                apy: 13.27,
                minStake: NSDecimalNumber(decimal: minStake * pow(Decimal(10), 9)).int64Value,
                verified: true,
                currentNominators: 100,
                maxNominators: 30000,
                implementation: implementation
            ),
            decimals: 9
        )
    }

    func testAddMoreReusesExistingPoolAddress() {
        let vm = TonStakeTransactionViewModel(
            coin: makeTonCoin(),
            vault: .example,
            existingPoolAddress: Self.poolAddress
        )
        XCTAssertFalse(vm.isFirstTimeStake)
        XCTAssertEqual(vm.destinationPoolAddress, Self.poolAddress)
        XCTAssertTrue(vm.hasDestinationPool)
    }

    func testFirstTimeStakeUsesPickedPoolAddress() {
        let vm = TonStakeTransactionViewModel(
            coin: makeTonCoin(),
            vault: .example,
            existingPoolAddress: nil
        )
        XCTAssertTrue(vm.isFirstTimeStake)
        XCTAssertNil(vm.destinationPoolAddress)
        XCTAssertFalse(vm.hasDestinationPool)

        let pool = makePool()
        vm.selectedPool = pool
        XCTAssertEqual(vm.destinationPoolAddress, pool.address)
        XCTAssertTrue(vm.hasDestinationPool)
    }

    func testMinStakeDrivenByPickedPool() {
        let vm = TonStakeTransactionViewModel(
            coin: makeTonCoin(),
            vault: .example,
            existingPoolAddress: nil
        )
        // Before a pool is picked, the conservative default floor applies.
        XCTAssertEqual(vm.minStake, TonStakeTransactionViewModel.defaultMinStake)
        vm.selectedPool = makePool(minStake: 50)
        XCTAssertEqual(vm.minStake, 50)
    }

    func testRequiredMinStakeAddsDepositBuffer() {
        let vm = TonStakeTransactionViewModel(
            coin: makeTonCoin(),
            vault: .example,
            existingPoolAddress: nil
        )
        vm.selectedPool = makePool(minStake: 50)
        // Pool minimum is 50, but the amount must clear 50 + the ~1 TON deposit
        // commission buffer so the pool doesn't reject (and bounce) the deposit.
        XCTAssertEqual(vm.requiredMinStake, 50 + TonStakeTransactionViewModel.depositFeeBuffer)
    }

    /// Regression: pool deposits must be sent to the bounceable (`EQ…`) form so a
    /// rejected deposit bounces back instead of being absorbed by the pool. The
    /// staking API hands us raw `0:` addresses, which the signer would otherwise
    /// treat as non-bounceable.
    func testStakeBuilderNormalizesPoolAddressToBounceable() {
        let rawPool = "0:a44757069a7b04e393782b4a2d3e5e449f19d16a4986a9e25436e6b97e45a16a"
        let builder = TonStakeTransactionBuilder(coin: makeTonCoin(), amount: "50", poolAddress: rawPool, memo: "Stake")
        XCTAssertTrue(builder.toAddress.hasPrefix("E"), "stake destination must be bounceable EQ form, got \(builder.toAddress)")
        XCTAssertNotEqual(builder.toAddress, rawPool)
        XCTAssertEqual(builder.memoFunctionDictionary.get("nodeAddress"), builder.toAddress)
    }

    func testUnstakeBuilderNormalizesPoolAddressToBounceable() {
        let rawPool = "0:a44757069a7b04e393782b4a2d3e5e449f19d16a4986a9e25436e6b97e45a16a"
        let builder = TonUnstakeTransactionBuilder(coin: makeTonCoin(), amount: "1", poolAddress: rawPool, memo: "Withdraw")
        XCTAssertTrue(builder.toAddress.hasPrefix("E"), "unstake destination must be bounceable EQ form, got \(builder.toAddress)")
        XCTAssertNotEqual(builder.toAddress, rawPool)
    }

    // MARK: - Per-implementation deposit comment resolution

    /// First-time stake into a whales pool resolves the deposit comment
    /// "Deposit" (verified on-chain; the README's "Stake" is rejected), not "d".
    func testFirstTimeWhalesStakeResolvesDepositComment() {
        let vm = TonStakeTransactionViewModel(
            coin: makeTonCoin(),
            vault: .example,
            existingPoolAddress: nil
        )
        vm.selectedPool = makePool(implementation: "whales")
        XCTAssertEqual(vm.destinationPoolImplementation, "whales")
        XCTAssertEqual(vm.depositComment, "Deposit")
    }

    /// First-time stake into a tf (standard nominator) pool resolves "d".
    func testFirstTimeTfStakeResolvesDComment() {
        let vm = TonStakeTransactionViewModel(
            coin: makeTonCoin(),
            vault: .example,
            existingPoolAddress: nil
        )
        vm.selectedPool = makePool(implementation: "tf")
        XCTAssertEqual(vm.depositComment, "d")
    }

    /// Add-more reuses the stored existing-pool implementation to resolve the
    /// deposit comment.
    func testAddMoreResolvesCommentFromExistingImplementation() {
        let whalesVM = TonStakeTransactionViewModel(
            coin: makeTonCoin(),
            vault: .example,
            existingPoolAddress: Self.poolAddress,
            existingPoolImplementation: "whales"
        )
        XCTAssertEqual(whalesVM.depositComment, "Deposit")

        let tfVM = TonStakeTransactionViewModel(
            coin: makeTonCoin(),
            vault: .example,
            existingPoolAddress: Self.poolAddress,
            existingPoolImplementation: "tf"
        )
        XCTAssertEqual(tfVM.depositComment, "d")
    }

    /// An unknown/unsupported implementation resolves no comment, so no builder
    /// is produced — the build is blocked rather than guessing a comment.
    func testUnsupportedImplementationBlocksBuilder() {
        let vm = TonStakeTransactionViewModel(
            coin: makeTonCoin(),
            vault: .example,
            existingPoolAddress: Self.poolAddress,
            existingPoolImplementation: "liquidTF"
        )
        XCTAssertNil(vm.depositComment)
        XCTAssertNil(vm.transactionBuilder)
    }

    func testMaxStakeableReservesNetworkFee() {
        let vm = TonStakeTransactionViewModel(
            coin: makeTonCoin(rawBalance: "100000000000"), // 100 TON
            vault: .example,
            existingPoolAddress: Self.poolAddress
        )
        // 100 TON minus the 0.05 TON default fee.
        XCTAssertEqual(vm.maxStakeableAmount, Decimal(string: "99.95"))
    }

    func testInsufficientBalanceForFeeWhenBelowFee() {
        let vm = TonStakeTransactionViewModel(
            coin: makeTonCoin(rawBalance: "10000000"), // 0.01 TON < 0.05 fee
            vault: .example,
            existingPoolAddress: Self.poolAddress
        )
        XCTAssertFalse(vm.hasSufficientBalanceForFee)
        XCTAssertEqual(vm.maxStakeableAmount, 0)
    }

    // MARK: - Unstake comment resolution

    func testUnstakeWhalesResolvesWithdrawCommentAndBuilds() {
        let vm = TonUnstakeTransactionViewModel(
            coin: makeTonCoin(),
            vault: .example,
            poolAddress: "0:a44757069a7b04e393782b4a2d3e5e449f19d16a4986a9e25436e6b97e45a16a",
            poolImplementation: "whales",
            stakedAmount: 50
        )
        XCTAssertEqual(vm.withdrawComment, "Withdraw")
        let builder = try? XCTUnwrap(vm.transactionBuilder as? TonUnstakeTransactionBuilder)
        XCTAssertEqual(builder?.memo, "Withdraw")
        XCTAssertTrue(builder?.toAddress.hasPrefix("E") ?? false)
        // The withdraw carries the 0.2 TON deposit/withdraw fee, not 1 TON.
        XCTAssertEqual(builder?.amount, Self.expectedWithdrawalSignalAmount)
    }

    /// The 0.2 TON withdrawal signal, formatted exactly as the builder formats it
    /// (locale-dependent decimal separator), so the assertion holds on any
    /// simulator locale.
    private static let expectedWithdrawalSignalAmount =
        (Decimal(string: "0.2") ?? 0.2).formatToDecimal(digits: 9)

    /// The withdrawal signal must carry the 0.2 TON withdraw fee for `tf` pools
    /// too — a larger amount (e.g. 1 TON) is rejected on-chain.
    func testUnstakeSignalAmountIs0Point2Ton() {
        let vm = TonUnstakeTransactionViewModel(
            coin: makeTonCoin(),
            vault: .example,
            poolAddress: "0:a44757069a7b04e393782b4a2d3e5e449f19d16a4986a9e25436e6b97e45a16a",
            poolImplementation: "tf",
            stakedAmount: 50
        )
        XCTAssertEqual(
            (vm.transactionBuilder as? TonUnstakeTransactionBuilder)?.amount,
            Self.expectedWithdrawalSignalAmount
        )
    }

    /// The 0.2 TON signal plus the network fee must be covered by the liquid
    /// balance, otherwise no builder is produced.
    func testUnstakeBlocksBuilderWhenBalanceBelowSignalPlusFee() {
        let vm = TonUnstakeTransactionViewModel(
            coin: makeTonCoin(rawBalance: "100000000"), // 0.1 TON < 0.2 + fee
            vault: .example,
            poolAddress: "0:a44757069a7b04e393782b4a2d3e5e449f19d16a4986a9e25436e6b97e45a16a",
            poolImplementation: "whales",
            stakedAmount: 50
        )
        XCTAssertFalse(vm.hasSufficientBalance)
        XCTAssertNil(vm.transactionBuilder)
    }

    func testUnstakeTfResolvesWComment() {
        let vm = TonUnstakeTransactionViewModel(
            coin: makeTonCoin(),
            vault: .example,
            poolAddress: "0:a44757069a7b04e393782b4a2d3e5e449f19d16a4986a9e25436e6b97e45a16a",
            poolImplementation: "tf",
            stakedAmount: 50
        )
        XCTAssertEqual(vm.withdrawComment, "w")
        XCTAssertEqual((vm.transactionBuilder as? TonUnstakeTransactionBuilder)?.memo, "w")
    }

    func testUnstakeUnsupportedImplementationBlocksBuilder() {
        let vm = TonUnstakeTransactionViewModel(
            coin: makeTonCoin(),
            vault: .example,
            poolAddress: "0:a44757069a7b04e393782b4a2d3e5e449f19d16a4986a9e25436e6b97e45a16a",
            poolImplementation: nil,
            stakedAmount: 50
        )
        XCTAssertNil(vm.withdrawComment)
        XCTAssertNil(vm.transactionBuilder)
    }
}
