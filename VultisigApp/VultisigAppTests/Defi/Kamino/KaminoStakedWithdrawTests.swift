//
//  KaminoStakedWithdrawTests.swift
//  VultisigAppTests
//
//  The withdraw of FARM-STAKED shares — the path steps 1–7 refused because the
//  transaction had never been observed, driven here against the real ones.
//
//  Six vectors were captured from `api.kamino.finance` on 2026-08-05 by building
//  unsigned transactions for third-party wallets (a POST and a decode; nothing
//  was signed and no funds moved), and every one of them was simulated on
//  mainnet with `err: null`. They cover the three shapes the API actually
//  builds:
//
//    - wholly staked position          → 5 instructions, unstake = the request
//    - mixed position, above unstaked  → 5 instructions, unstake = the SHORTFALL
//    - mixed position, within unstaked → 2 instructions, no farms at all
//
//  plus the wrapped-SOL vault, which adds the payout account's `closeAccount`,
//  and the one that must be REFUSED: the reported 14-decimal balance sent back
//  verbatim, whose vault-withdraw `u64` is the withdraw-everything sentinel.
//
//  These resolve through the real address lookup table and compare account
//  PUBKEYS, not indices. An index is only a position; showing that the validator
//  accepted an index shows nothing about which account the instruction receives.
//

import BigInt
@testable import VultisigApp
import WalletCore
import XCTest

final class KaminoStakedWithdrawTests: XCTestCase {

    // MARK: - Discriminators are derived, not pasted

    /// Both farms discriminators the staked path introduces, recomputed from the
    /// instruction NAME.
    ///
    /// This is the difference between an identification and a coincidence. A
    /// constant lifted out of a captured transaction matches the bytes it was
    /// lifted from and asserts nothing about what they are; one that equals
    /// `sha256("global:<name>")[0..<8]` says the bytes are that instruction. The
    /// two names were found by sweeping the farms instruction set against the
    /// observed bytes, and both matched exactly.
    func testTheFarmsDiscriminatorsAreTheirAnchorNames() {
        XCTAssertEqual(
            KaminoInstructionDiscriminator.farmsUnstake,
            Self.anchorDiscriminator("unstake")
        )
        XCTAssertEqual(
            KaminoInstructionDiscriminator.farmsWithdrawUnstakedDeposits,
            Self.anchorDiscriminator("withdraw_unstaked_deposits")
        )
        // And the bytes that were actually observed on the wire.
        XCTAssertEqual(
            KaminoInstructionDiscriminator.farmsUnstake,
            [0x5a, 0x5f, 0x6b, 0x2a, 0xcd, 0x7c, 0x32, 0xe1]
        )
        XCTAssertEqual(
            KaminoInstructionDiscriminator.farmsWithdrawUnstakedDeposits,
            [0x24, 0x66, 0xbb, 0x31, 0xdc, 0x24, 0x84, 0x43]
        )
    }

    /// The two `farms` instructions the app already knew must not collide with
    /// the two it just learned — a discriminator clash would silently reclassify
    /// one instruction as another.
    func testEveryFarmsDiscriminatorIsDistinct() {
        let all = [
            KaminoInstructionDiscriminator.farmsStake,
            KaminoInstructionDiscriminator.farmsInitializeUser,
            KaminoInstructionDiscriminator.farmsUnstake,
            KaminoInstructionDiscriminator.farmsWithdrawUnstakedDeposits
        ]
        XCTAssertEqual(Set(all.map { Data($0) }).count, all.count)
    }

    // MARK: - The captured shape

    /// Five instructions, in this order, with BOTH farms instructions ahead of
    /// the vault withdraw and TWO account creations.
    func testTheStakedWithdrawIsFiveInstructionsInTheCapturedOrder() throws {
        let kinds = try Self.kinds(of: KaminoTransactionFixtures.stakedWithdraw.source)

        XCTAssertEqual(kinds, [
            .createTokenAccount,
            .farmsUnstake,
            .farmsWithdrawUnstakedDeposits,
            .createTokenAccount,
            .kvaultWithdraw
        ])
    }

    /// The wrapped-SOL vault adds the payout account's `closeAccount`, which is
    /// what unwraps the payout to native SOL — six instructions, and the only
    /// staked shape that carries one at all.
    func testTheWrappedSolStakedWithdrawAlsoClosesThePayoutAccount() throws {
        let kinds = try Self.kinds(of: KaminoTransactionFixtures.solStakedWithdraw.source)

        XCTAssertEqual(kinds, [
            .createTokenAccount,
            .farmsUnstake,
            .farmsWithdrawUnstakedDeposits,
            .createTokenAccount,
            .kvaultWithdraw,
            .closeTokenAccount
        ])
    }

    /// A request inside the unstaked balance is the OLD two-instruction shape.
    /// Same wallet, same vault, same position — only the amount differs.
    func testARequestInsideTheUnstakedBalanceCarriesNoFarmsInstruction() throws {
        let kinds = try Self.kinds(of: KaminoTransactionFixtures.mixedWithdrawWithinUnstaked.source)

        XCTAssertEqual(kinds, [.createTokenAccount, .kvaultWithdraw])
    }

    /// The unstake argument is a `u128` scaled by `10^18`, and reading it as a
    /// `u64` does not merely lose precision — it produces a different number
    /// entirely, because the low eight bytes of `1 share × 10^18` are not one
    /// share.
    func testTheUnstakeArgumentIsAScaledUInt128AndNotAUInt64() throws {
        let transaction = try SolanaV0Transaction(
            base64Transaction: KaminoTransactionFixtures.stakedWithdraw.source
        )
        let data = transaction.instructions[1].data

        XCTAssertEqual(data.count, 24)
        XCTAssertEqual(
            KaminoInstructionDiscriminator.anchorArgument128(data),
            BigInt(1_000_000) * KaminoInstructionDiscriminator.farmsStakeScale
        )
        // The `u64` reader refuses it outright rather than taking half of it.
        XCTAssertNil(KaminoInstructionDiscriminator.anchorArgument(data))
    }

    /// The shortfall invariant, read straight out of the captured bytes: against
    /// a position holding `0.959593` unstaked, a request of `1.5` carries an
    /// unstake of exactly `0.540407`.
    func testTheCapturedUnstakeIsExactlyTheShortfall() throws {
        let transaction = try SolanaV0Transaction(
            base64Transaction: KaminoTransactionFixtures.mixedWithdrawStraddling.source
        )

        let unstake = try XCTUnwrap(
            KaminoInstructionDiscriminator.anchorArgument128(transaction.instructions[1].data)
        )
        let burned = try XCTUnwrap(
            KaminoInstructionDiscriminator.anchorArgument(transaction.instructions[4].data)
        )

        XCTAssertEqual(burned, 1_500_000)
        XCTAssertEqual(unstake, BigInt(540_407) * KaminoInstructionDiscriminator.farmsStakeScale)
        XCTAssertEqual(
            unstake,
            (BigInt(burned) - BigInt(959_593)) * KaminoInstructionDiscriminator.farmsStakeScale
        )
    }

    // MARK: - Golden vectors through the validator

    /// Every captured staked shape validates against the request it answers,
    /// resolved through the real lookup table.
    func testEveryCapturedStakedWithdrawValidates() throws {
        for sample in Self.samples {
            try KaminoTransactionValidator.validate(
                transaction: try SolanaV0Transaction(base64Transaction: sample.vector.source),
                intent: sample.intent,
                lookupTables: KaminoTransactionFixtures.lookupTables
            )
        }
    }

    /// And after the app's compute budget goes in, with both ComputeBudget
    /// instructions now required and pinned. Injection shifts every
    /// lookup-derived account index by one, so this is also the check that the
    /// staked instructions still receive the same accounts afterwards.
    func testEveryCapturedStakedWithdrawValidatesAfterInjection() throws {
        for sample in Self.samples {
            let intent = KaminoTransactionIntent(
                operation: sample.intent.operation,
                vault: sample.intent.vault,
                owner: sample.intent.owner,
                priorityFee: KaminoPriorityFee(
                    limit: sample.vector.unitLimit,
                    price: KaminoTransactionFixtures.unitPriceMicroLamports
                )
            )
            try KaminoTransactionValidator.validate(
                transaction: try SolanaV0Transaction(base64Transaction: sample.vector.injected),
                intent: intent,
                lookupTables: KaminoTransactionFixtures.lookupTables
            )
        }
    }

    /// The accounts, by pubkey, after the lookup table is resolved.
    ///
    /// This is what the golden vectors are for. The unstake authority and the
    /// unstaked shares' destination are the two slots that decide whose position
    /// moves and where it lands, and both are compared against values derived
    /// locally — the signer, and the ATA derivation — never read out of the
    /// response.
    func testTheFarmsInstructionsNameTheSignersOwnAccounts() throws {
        let vector = KaminoTransactionFixtures.stakedWithdraw
        let transaction = try SolanaV0Transaction(base64Transaction: vector.source)
        let accounts = try transaction.resolvedAccountAddresses(
            lookupTables: KaminoTransactionFixtures.lookupTables
        )

        let unstake = transaction.instructions[1].accountIndexes.map { accounts[Int($0)] }
        XCTAssertEqual(unstake[KaminoInstructionAccounts.FarmsUnstake.owner], vector.feePayer)
        XCTAssertEqual(
            unstake[KaminoInstructionAccounts.FarmsUnstake.farm],
            KaminoVaultRegistry.steakhouseUSDC.farm
        )

        let release = transaction.instructions[2].accountIndexes.map { accounts[Int($0)] }
        XCTAssertEqual(release[KaminoInstructionAccounts.FarmsWithdrawUnstakedDeposits.owner], vector.feePayer)
        XCTAssertEqual(
            release[KaminoInstructionAccounts.FarmsWithdrawUnstakedDeposits.farm],
            KaminoVaultRegistry.steakhouseUSDC.farm
        )

        // The released shares land in the signer's own share account, and it is
        // the SAME account the vault withdraw then burns from.
        let destination = release[KaminoInstructionAccounts.FarmsWithdrawUnstakedDeposits.userShareAccount]
        XCTAssertTrue(
            SolanaAssociatedTokenAccount
                .ownedAccounts(owner: vector.feePayer, mint: KaminoVaultRegistry.steakhouseUSDC.sharesMint)
                .contains(destination)
        )
        let burn = transaction.instructions[4].accountIndexes.map { accounts[Int($0)] }
        XCTAssertEqual(burn[KaminoInstructionAccounts.KvaultWithdraw.userShareAccount], destination)
    }

    /// The two account creations are the share account and the payout account,
    /// both the signer's own, in that order — not one repeated.
    func testTheTwoAccountCreationsAreTheShareAndPayoutAccounts() throws {
        let vector = KaminoTransactionFixtures.stakedWithdraw
        let transaction = try SolanaV0Transaction(base64Transaction: vector.source)
        let accounts = try transaction.resolvedAccountAddresses(
            lookupTables: KaminoTransactionFixtures.lookupTables
        )

        let mints = [0, 3].map { position -> String in
            let indexes = transaction.instructions[position].accountIndexes
            return accounts[Int(indexes[KaminoInstructionAccounts.AssociatedToken.mint])]
        }

        XCTAssertEqual(mints, [
            KaminoVaultRegistry.steakhouseUSDC.sharesMint,
            KaminoVaultRegistry.steakhouseUSDC.tokenMint
        ])
    }

    // MARK: - Refusals

    /// The captured transaction the app must NOT accept.
    ///
    /// It is what the API builds when the reported `stakedShares` string —
    /// `"136.26461099910218"`, fourteen decimals on a six-decimal mint — is
    /// handed straight back as the amount: the vault withdraw's `u64` comes back
    /// as `18446744073709551615`, the withdraw-everything sentinel. Refused on
    /// the amount, which is the guard the whole withdraw flow is built around.
    func testTheReportedBalanceSentVerbatimIsRefusedAsTheSentinel() throws {
        let vector = KaminoTransactionFixtures.stakedWithdrawSentinel
        let requested = KaminoShareAmount(baseUnits: BigInt(136_264_610), decimals: 6)

        XCTAssertThrowsError(
            try KaminoTransactionValidator.validate(
                transaction: try SolanaV0Transaction(base64Transaction: vector.source),
                intent: Self.intent(
                    vector: vector,
                    shares: requested,
                    unstaked: KaminoShareAmount(baseUnits: BigInt(0), decimals: 6)
                ),
                lookupTables: KaminoTransactionFixtures.lookupTables
            )
        ) { error in
            XCTAssertEqual(
                error as? KaminoValidationError,
                .amountMismatch(
                    role: "withdraw share amount",
                    expected: "136264610",
                    actual: String(UInt64.max)
                )
            )
        }
    }

    /// An unstake for MORE than the request needs is refused, and this is the
    /// finding the exact pin exists for: the extra shares leave the farm, stop
    /// earning, and never appear on the verify screen, which shows an amount and
    /// not a stake. Bounding the unstake above by the request would let this
    /// through whenever the position is bigger than the withdraw.
    func testAnUnstakeLargerThanTheShortfallIsRefused() throws {
        let vector = KaminoTransactionFixtures.mixedWithdrawStraddling

        // Same bytes, but told the position was wholly staked — so the shortfall
        // the validator computes is the whole 1,500,000 rather than 540,407.
        XCTAssertThrowsError(
            try KaminoTransactionValidator.validate(
                transaction: try SolanaV0Transaction(base64Transaction: vector.source),
                intent: Self.intent(
                    vector: vector,
                    shares: KaminoShareAmount(baseUnits: BigInt(1_500_000), decimals: 6),
                    unstaked: KaminoShareAmount(baseUnits: BigInt(0), decimals: 6)
                ),
                lookupTables: KaminoTransactionFixtures.lookupTables
            )
        ) { error in
            guard case .amountMismatch(let role, _, _)? = error as? KaminoValidationError else {
                return XCTFail("expected an amount mismatch, got \(error)")
            }
            XCTAssertEqual(role, "unstaked share amount")
        }
    }

    /// And a request that needs a release but arrives without one is refused as
    /// a missing step rather than accepted as a smaller transaction.
    func testAWithdrawMissingItsFarmReleaseIsRefused() throws {
        let vector = KaminoTransactionFixtures.mixedWithdrawWithinUnstaked

        XCTAssertThrowsError(
            try KaminoTransactionValidator.validate(
                transaction: try SolanaV0Transaction(base64Transaction: vector.source),
                intent: Self.intent(
                    vector: vector,
                    shares: KaminoShareAmount(baseUnits: BigInt(500_000), decimals: 6),
                    // Nothing unstaked, so this request needs the farm.
                    unstaked: KaminoShareAmount(baseUnits: BigInt(0), decimals: 6)
                ),
                lookupTables: KaminoTransactionFixtures.lookupTables
            )
        ) { error in
            XCTAssertEqual(
                error as? KaminoValidationError,
                .missingInstruction("farm unstake")
            )
        }
    }

    // MARK: - The offline decode

    /// A co-signer holds no position, so it accepts either shape — but it reads
    /// the same claim off the bytes, and refuses an unstake that releases more
    /// than the withdraw burns.
    func testTheOfflineDecodeReadsTheStakedWithdraw() throws {
        let vector = KaminoTransactionFixtures.stakedWithdraw
        let decoded = try XCTUnwrap(
            KaminoTransactionDecoder.decode(
                try SolanaV0Transaction(base64Transaction: vector.source)
            )
        )

        XCTAssertEqual(decoded.operation, .withdraw)
        XCTAssertEqual(decoded.descriptor, KaminoVaultRegistry.steakhouseUSDC)
        XCTAssertEqual(decoded.amountBaseUnits, BigInt(1_000_000))
        XCTAssertEqual(decoded.signer, vector.feePayer)
        XCTAssertFalse(decoded.withdrawsEntirePosition)
    }

    /// The sentinel is surfaced rather than rendered as 18.4 quintillion shares,
    /// which would be literally true and say nothing.
    func testTheOfflineDecodeFlagsTheSentinel() throws {
        let decoded = try XCTUnwrap(
            KaminoTransactionDecoder.decode(
                try SolanaV0Transaction(
                    base64Transaction: KaminoTransactionFixtures.stakedWithdrawSentinel.source
                )
            )
        )

        XCTAssertTrue(decoded.withdrawsEntirePosition)
    }

    /// The bound a co-signer CAN check without a position: an unstake may not
    /// release more shares than the withdraw beside it burns.
    func testTheOfflineDecodeRefusesAnUnstakeAboveTheWithdraw() throws {
        // The withdraw burns 1,000,000 shares; release 2,000,000.
        let edited = try Self.replacingUnstakeAmount(
            in: KaminoTransactionFixtures.stakedWithdraw.source,
            with: BigInt(2_000_000) * KaminoInstructionDiscriminator.farmsStakeScale
        )

        XCTAssertNil(
            KaminoTransactionDecoder.decode(try SolanaV0Transaction(base64Transaction: edited))
        )
    }

    /// A release amount that is not a whole number of share base units is not a
    /// share count at all.
    func testTheOfflineDecodeRefusesAnUnscaledUnstake() throws {
        let edited = try Self.replacingUnstakeAmount(
            in: KaminoTransactionFixtures.stakedWithdraw.source,
            with: BigInt(1_000_000) * KaminoInstructionDiscriminator.farmsStakeScale + 1
        )

        XCTAssertNil(
            KaminoTransactionDecoder.decode(try SolanaV0Transaction(base64Transaction: edited))
        )
    }

    /// And the untouched vector still decodes, so the two refusals above are
    /// caused by the amount rather than by the edit.
    func testTheUneditedStakedWithdrawStillDecodes() throws {
        let unchanged = try Self.replacingUnstakeAmount(
            in: KaminoTransactionFixtures.stakedWithdraw.source,
            with: BigInt(1_000_000) * KaminoInstructionDiscriminator.farmsStakeScale
        )

        XCTAssertEqual(unchanged, KaminoTransactionFixtures.stakedWithdraw.source)
        XCTAssertNotNil(
            KaminoTransactionDecoder.decode(try SolanaV0Transaction(base64Transaction: unchanged))
        )
    }

    /// Half a farm release is not a smaller release — it is shares taken out of
    /// the farm and left in its pending-withdrawal state, out of the position
    /// the app reads and off every screen. Refused on BOTH devices, including
    /// the offline one where the pair is otherwise optional.
    func testAnUnstakeWithoutItsCompanionIsRefused() throws {
        let edited = try Self.removingInstruction(
            at: 2,
            from: KaminoTransactionFixtures.stakedWithdraw.source
        )

        // Offline, where the pair is optional and could otherwise be split.
        XCTAssertNil(
            KaminoTransactionDecoder.decode(try SolanaV0Transaction(base64Transaction: edited))
        )

        // And online.
        XCTAssertThrowsError(
            try KaminoTransactionValidator.validate(
                transaction: try SolanaV0Transaction(base64Transaction: edited),
                intent: Self.intent(
                    vector: KaminoTransactionFixtures.stakedWithdraw,
                    shares: KaminoShareAmount(baseUnits: BigInt(1_000_000), decimals: 6),
                    unstaked: KaminoShareAmount(baseUnits: BigInt(0), decimals: 6)
                ),
                lookupTables: KaminoTransactionFixtures.lookupTables
            )
        ) { error in
            XCTAssertEqual(
                error as? KaminoValidationError,
                .missingInstruction("farm unstaked share withdrawal")
            )
        }
    }

    /// The other half, for the same reason: moving a pending balance the
    /// transaction never released is a movement the decode cannot account for.
    func testAReleaseWithoutItsUnstakeIsRefused() throws {
        let edited = try Self.removingInstruction(
            at: 1,
            from: KaminoTransactionFixtures.stakedWithdraw.source
        )

        XCTAssertNil(
            KaminoTransactionDecoder.decode(try SolanaV0Transaction(base64Transaction: edited))
        )
    }

    /// The matcher's paired rule is what does it, independent of the template it
    /// is driven with.
    func testThePairedStepRefusesEitherHalfAlone() {
        let steps = KaminoInstructionSequence.expected(
            operation: .withdraw,
            isWrappedSolVault: false,
            hasFarm: true,
            hasPriorityFee: false,
            farmUnstake: .unknown
        )

        for lone in [KaminoInstructionSequence.Kind.farmsUnstake, .farmsWithdrawUnstakedDeposits] {
            let result = KaminoInstructionSequence.match(
                kinds: [.createTokenAccount, lone, .kvaultWithdraw],
                against: steps
            )
            guard case .failure(let failure) = result else {
                return XCTFail("expected \(lone) alone to be refused")
            }
            guard case .incompleteInstructionPair = failure else {
                return XCTFail("expected an incomplete pair, got \(failure)")
            }
        }

        // Both together, and neither at all, are the two accepted shapes.
        XCTAssertNotNil(
            try? KaminoInstructionSequence.match(
                kinds: [.createTokenAccount, .farmsUnstake, .farmsWithdrawUnstakedDeposits, .kvaultWithdraw],
                against: steps
            ).get()
        )
        XCTAssertNotNil(
            try? KaminoInstructionSequence.match(
                kinds: [.createTokenAccount, .kvaultWithdraw],
                against: steps
            ).get()
        )
    }

    // MARK: - The farms user state, derived

    /// The account that decides WHICH stake a farms instruction moves, pinned
    /// against the three real ones in the captured transactions.
    ///
    /// It is a program address over `("user", farm, owner)`, which is what lets
    /// the offline decode attribute a farm release at all: the farm slot itself
    /// is an address-lookup-table entry in every captured transaction and cannot
    /// be resolved without the network, but this can be recomputed from the
    /// registry's farm and the transaction's own signer.
    func testTheFarmsUserStateIsDerivedFromTheFarmAndOwner() throws {
        let steakhouse = try XCTUnwrap(KaminoVaultRegistry.steakhouseUSDC.farm)
        let allez = try XCTUnwrap(KaminoVaultRegistry.allezSOL.farm)

        XCTAssertEqual(
            KaminoFarmsUserState.derive(
                farm: steakhouse,
                owner: "6BTaMq25LcNDTVhheUe9UyvwWgayqFv77njymVnG8SNy"
            ),
            "2BargidHgSggDPTQeVqjkBG3U5WNFTLGpGGU2cTVfh1q"
        )
        XCTAssertEqual(
            KaminoFarmsUserState.derive(
                farm: steakhouse,
                owner: "DhCrkyWYGQayd4QNUDdLyvrALLmrJqTUHPGoA98pX2YU"
            ),
            "J9sg4ZH65VfAbmwMU5mkPwtocwYdqtcKKBnMZctCVprj"
        )
        XCTAssertEqual(
            KaminoFarmsUserState.derive(
                farm: allez,
                owner: "CHFeSGER1nXFUtvdAVb49rLHTgvvuxEXmeTG3GBtgKzF"
            ),
            "179edaHAQZ6Dg7JcU8NbbYr4qEkMhMbUZfkqBXFtA3v"
        )
    }

    /// Both seeds matter. Change either and the address is somewhere else, which
    /// is the whole reason recomputing it is an identification.
    func testTheFarmsUserStateChangesWithBothSeeds() throws {
        let steakhouse = try XCTUnwrap(KaminoVaultRegistry.steakhouseUSDC.farm)
        let allez = try XCTUnwrap(KaminoVaultRegistry.allezSOL.farm)
        let owner = "6BTaMq25LcNDTVhheUe9UyvwWgayqFv77njymVnG8SNy"

        let base = try XCTUnwrap(KaminoFarmsUserState.derive(farm: steakhouse, owner: owner))
        XCTAssertNotEqual(base, KaminoFarmsUserState.derive(farm: allez, owner: owner))
        XCTAssertNotEqual(
            base,
            KaminoFarmsUserState.derive(
                farm: steakhouse,
                owner: "DhCrkyWYGQayd4QNUDdLyvrALLmrJqTUHPGoA98pX2YU"
            )
        )
        XCTAssertNil(KaminoFarmsUserState.derive(farm: steakhouse, owner: "not-an-address"))
    }

    /// A program address is off the ed25519 curve by construction, and an
    /// ordinary account address is on it. If the curve test were inverted or
    /// vacuous the derivation above would still produce *an* address, so this is
    /// what stops it agreeing by accident.
    func testProgramAddressesAreOffTheCurveAndAccountsAreOnIt() throws {
        let derived = try XCTUnwrap(
            KaminoFarmsUserState.derive(
                farm: try XCTUnwrap(KaminoVaultRegistry.steakhouseUSDC.farm),
                owner: "6BTaMq25LcNDTVhheUe9UyvwWgayqFv77njymVnG8SNy"
            )
        )
        XCTAssertFalse(
            SolanaProgramDerivedAddress.isOnEd25519Curve(
                try XCTUnwrap(Base58.decodeNoCheck(string: derived))
            )
        )

        // Real wallet addresses are public keys, so they are on the curve.
        for wallet in [
            "6BTaMq25LcNDTVhheUe9UyvwWgayqFv77njymVnG8SNy",
            "DhCrkyWYGQayd4QNUDdLyvrALLmrJqTUHPGoA98pX2YU",
            "CHFeSGER1nXFUtvdAVb49rLHTgvvuxEXmeTG3GBtgKzF"
        ] {
            XCTAssertTrue(
                SolanaProgramDerivedAddress.isOnEd25519Curve(
                    try XCTUnwrap(Base58.decodeNoCheck(string: wallet))
                ),
                wallet
            )
        }
    }

    /// A release aimed at another holder's position on the same farm — the case
    /// the derived user state exists to refuse, and one the farm slot alone
    /// cannot catch because the farm is right.
    func testAFarmsInstructionNamingAnotherHoldersUserStateIsRefused() throws {
        let other = try XCTUnwrap(
            KaminoFarmsUserState.derive(
                farm: try XCTUnwrap(KaminoVaultRegistry.steakhouseUSDC.farm),
                owner: "DhCrkyWYGQayd4QNUDdLyvrALLmrJqTUHPGoA98pX2YU"
            )
        )
        let edited = try Self.replacingStaticKey(
            at: 1,
            with: other,
            in: KaminoTransactionFixtures.stakedWithdraw.source
        )

        XCTAssertNil(
            KaminoTransactionDecoder.decode(try SolanaV0Transaction(base64Transaction: edited))
        )

        XCTAssertThrowsError(
            try KaminoTransactionValidator.validate(
                transaction: try SolanaV0Transaction(base64Transaction: edited),
                intent: Self.intent(
                    vector: KaminoTransactionFixtures.stakedWithdraw,
                    shares: KaminoShareAmount(baseUnits: BigInt(1_000_000), decimals: 6),
                    unstaked: KaminoShareAmount(baseUnits: BigInt(0), decimals: 6)
                ),
                lookupTables: KaminoTransactionFixtures.lookupTables
            )
        ) { error in
            guard case .accountMismatch(let role, _, _)? = error as? KaminoValidationError else {
                return XCTFail("expected an account mismatch, got \(error)")
            }
            XCTAssertEqual(role, "farm user state")
        }
    }

    // MARK: - Closing the payout account

    /// A full wrapped-SOL withdraw closes TWO accounts — the payout account and
    /// the emptied share account — so the step has to be repeatable. A template
    /// allowing one would refuse a transaction the API really builds.
    func testAWrappedSolWithdrawMayCloseTwoAccounts() {
        let steps = KaminoInstructionSequence.expected(
            operation: .withdraw,
            isWrappedSolVault: true,
            hasFarm: true,
            hasPriorityFee: false,
            farmUnstake: .forbidden
        )

        let result = KaminoInstructionSequence.match(
            kinds: [.createTokenAccount, .kvaultWithdraw, .closeTokenAccount, .closeTokenAccount],
            against: steps
        )

        XCTAssertNotNil(try? result.get())
    }

    /// And on that vault the close is REQUIRED, because closing the payout
    /// account is what unwraps wSOL into the native SOL the screen promises. A
    /// withdraw without it executes and leaves the user holding wrapped SOL.
    func testAWrappedSolWithdrawWithoutItsCloseIsRefused() {
        let steps = KaminoInstructionSequence.expected(
            operation: .withdraw,
            isWrappedSolVault: true,
            hasFarm: true,
            hasPriorityFee: false,
            farmUnstake: .forbidden
        )

        let result = KaminoInstructionSequence.match(
            kinds: [.createTokenAccount, .kvaultWithdraw],
            against: steps
        )

        guard case .failure(.missingInstruction(let name)) = result else {
            return XCTFail("expected the close to be required on the wrapped-SOL vault")
        }
        XCTAssertEqual(name, "close token account")
    }

    /// The USDC vaults are the other way round: the close appears only on a full
    /// withdraw of an unstaked position, and not at all on the staked path, so
    /// its absence there is not a finding.
    func testATokenVaultWithdrawNeedsNoClose() {
        let steps = KaminoInstructionSequence.expected(
            operation: .withdraw,
            isWrappedSolVault: false,
            hasFarm: true,
            hasPriorityFee: false,
            farmUnstake: .forbidden
        )

        XCTAssertNotNil(
            try? KaminoInstructionSequence.match(
                kinds: [.createTokenAccount, .kvaultWithdraw],
                against: steps
            ).get()
        )
    }

    // MARK: - What a co-signer refuses

    /// An account creation the signer PAYS for, owned by somebody else. The step
    /// is repeatable, so without this an extra creation would ride alongside a
    /// legitimate withdraw and spend the signer's SOL on a stranger's rent.
    ///
    /// Only the ATA's WALLET slot is repointed — at another account the message
    /// already carries, so no key is added and no index shifts. The signer, the
    /// payer and every other account stay exactly as captured, which is what
    /// makes the refusal attributable to this one slot.
    func testTheOfflineDecodeRefusesAnAccountCreationForAnotherWallet() throws {
        let edited = try Self.repointing(
            instruction: 0,
            slot: KaminoInstructionAccounts.AssociatedToken.wallet,
            toAccountIndex: 1,
            in: KaminoTransactionFixtures.mixedWithdrawWithinUnstaked.source
        )

        XCTAssertNil(
            KaminoTransactionDecoder.decode(try SolanaV0Transaction(base64Transaction: edited))
        )
    }

    /// The same for who collects the rent of a closed account.
    func testTheOfflineDecodeRefusesACloseThatPaysSomebodyElse() throws {
        let edited = try Self.repointing(
            instruction: 5,
            slot: KaminoInstructionAccounts.CloseAccount.destination,
            toAccountIndex: 1,
            in: KaminoTransactionFixtures.solStakedWithdraw.source
        )

        XCTAssertNil(
            KaminoTransactionDecoder.decode(try SolanaV0Transaction(base64Transaction: edited))
        )
    }

    /// A compute-unit price outside the range this app clamps into. Under-tipping
    /// is not a spend, but it is not a price this app produces either, and a
    /// screen that agrees with it is agreeing with a number nothing chose.
    func testTheOfflineDecodeRefusesAPriceThisAppNeverChooses() throws {
        for price in [UInt64(1), KaminoComputeBudget.fallbackUnitPriceMicroLamports - 1] {
            let edited = try Self.replacingUnitPrice(
                price,
                in: KaminoTransactionFixtures.stakedWithdraw.injected
            )
            XCTAssertNil(
                KaminoTransactionDecoder.decode(try SolanaV0Transaction(base64Transaction: edited)),
                "price \(price)"
            )
        }

        // The floor itself is what the app injects, and it stays readable.
        let atTheFloor = try Self.replacingUnitPrice(
            KaminoComputeBudget.fallbackUnitPriceMicroLamports,
            in: KaminoTransactionFixtures.stakedWithdraw.injected
        )
        XCTAssertNotNil(
            KaminoTransactionDecoder.decode(try SolanaV0Transaction(base64Transaction: atTheFloor))
        )
    }

    /// The withdraw-everything sentinel must stop a co-signer's signature, not
    /// merely be labelled on the way past. This app cannot produce one, so a
    /// transaction carrying it did not come from here — and its consequence is
    /// the whole position rather than the number on screen.
    func testTheSentinelBlocksSigningEvenThoughItIsDisclosed() throws {
        let decoded = try XCTUnwrap(
            KaminoTransactionDecoder.decode(
                try SolanaV0Transaction(
                    base64Transaction: KaminoTransactionFixtures.stakedWithdrawSentinel.source
                )
            )
        )
        XCTAssertTrue(decoded.withdrawsEntirePosition)

        let display = KaminoVerifyPresentation.Display(
            operation: .withdraw,
            vaultName: KaminoVaultRegistry.steakhouseUSDC.fallbackName,
            vaultAddress: KaminoVaultRegistry.steakhouseUSDC.address,
            curator: KaminoVaultRegistry.steakhouseUSDC.curator,
            riskTier: KaminoVaultRegistry.steakhouseUSDC.riskTier,
            amount: decoded.amountString,
            unit: "shares",
            strandsWrappedSolRent: false,
            withdrawsEntirePosition: true
        )

        XCTAssertTrue(KaminoVerifyPresentation.State.verified(display).blocksSigning)
        XCTAssertTrue(KaminoVerifyPresentation.State.amountUnverifiable(display).blocksSigning)
    }

    // MARK: - Fixtures

    private struct Sample {
        let vector: KaminoTransactionFixtures.Vector
        let intent: KaminoTransactionIntent
    }

    private static var samples: [Sample] {
        [
            Sample(
                vector: KaminoTransactionFixtures.stakedWithdraw,
                intent: intent(
                    vector: KaminoTransactionFixtures.stakedWithdraw,
                    shares: KaminoShareAmount(baseUnits: BigInt(1_000_000), decimals: 6),
                    unstaked: KaminoShareAmount(baseUnits: BigInt(0), decimals: 6)
                )
            ),
            Sample(
                vector: KaminoTransactionFixtures.stakedWithdrawMaximum,
                intent: intent(
                    vector: KaminoTransactionFixtures.stakedWithdrawMaximum,
                    shares: KaminoShareAmount(baseUnits: BigInt(136_264_610), decimals: 6),
                    unstaked: KaminoShareAmount(baseUnits: BigInt(0), decimals: 6)
                )
            ),
            Sample(
                vector: KaminoTransactionFixtures.mixedWithdrawStraddling,
                intent: intent(
                    vector: KaminoTransactionFixtures.mixedWithdrawStraddling,
                    shares: KaminoShareAmount(baseUnits: BigInt(1_500_000), decimals: 6),
                    unstaked: KaminoShareAmount(baseUnits: BigInt(959_593), decimals: 6)
                )
            ),
            Sample(
                vector: KaminoTransactionFixtures.mixedWithdrawWithinUnstaked,
                intent: intent(
                    vector: KaminoTransactionFixtures.mixedWithdrawWithinUnstaked,
                    shares: KaminoShareAmount(baseUnits: BigInt(500_000), decimals: 6),
                    unstaked: KaminoShareAmount(baseUnits: BigInt(959_593), decimals: 6)
                )
            ),
            Sample(
                vector: KaminoTransactionFixtures.solStakedWithdraw,
                intent: intent(
                    vector: KaminoTransactionFixtures.solStakedWithdraw,
                    descriptor: KaminoVaultRegistry.allezSOL,
                    shares: KaminoShareAmount(baseUnits: BigInt(1_000_000), decimals: 6),
                    unstaked: KaminoShareAmount(baseUnits: BigInt(0), decimals: 6)
                )
            )
        ]
    }

    private static func intent(
        vector: KaminoTransactionFixtures.Vector,
        descriptor: KaminoVaultDescriptor = KaminoVaultRegistry.steakhouseUSDC,
        shares: KaminoShareAmount,
        unstaked: KaminoShareAmount
    ) -> KaminoTransactionIntent {
        KaminoTransactionIntent(
            operation: .withdraw(KaminoWithdrawRequest(shares: shares, unstakedShares: unstaked)),
            vault: vaultInfo(descriptor: descriptor, lookupTable: vector.lookupTable),
            owner: vector.feePayer
        )
    }

    /// Only the live fields are supplied — the mints, their decimals and the
    /// farm come from the registry, which is the point of pinning them.
    private static func vaultInfo(
        descriptor: KaminoVaultDescriptor,
        lookupTable: String
    ) -> KaminoVaultInfo {
        KaminoVaultInfo(
            descriptor: descriptor,
            name: descriptor.fallbackName,
            minDeposit: KaminoTokenAmount(baseUnits: BigInt(100_000), decimals: descriptor.tokenDecimals),
            minWithdraw: KaminoShareAmount(baseUnits: BigInt(1_000), decimals: descriptor.sharesDecimals),
            lookupTable: lookupTable,
            apy30d: Decimal(string: "0.0391") ?? .zero,
            tokensPerShare: KaminoRate(apiString: "1.0536041812651029025") ?? KaminoRate(apiString: "1")!,
            tokenPriceUsd: 1
        )
    }

    private static func kinds(of base64: String) throws -> [KaminoInstructionSequence.Kind?] {
        let transaction = try SolanaV0Transaction(base64Transaction: base64)
        let accounts = transaction.staticAccountAddresses
        return transaction.instructions.map { instruction in
            let index = Int(instruction.programIdIndex)
            guard accounts.indices.contains(index) else { return nil }
            return KaminoInstructionSequence.kind(
                program: KaminoSolanaProgram(programId: accounts[index]),
                data: instruction.data
            )
        }
    }

    private static func anchorDiscriminator(_ name: String) -> [UInt8] {
        [UInt8](Hash.sha256(data: Data("global:\(name)".utf8)).prefix(8))
    }

    /// Points one instruction's account slot at a different account the message
    /// already carries. No key is added, so no index shifts and nothing else
    /// about the transaction changes.
    private static func repointing(
        instruction: Int,
        slot: Int,
        toAccountIndex index: UInt8,
        in base64: String
    ) throws -> String {
        var mutable = try MutableTransaction(base64: base64)
        mutable.instructions[instruction].accounts[slot] = index
        return try mutable.base64()
    }

    /// Substitutes one static account key, leaving every index untouched — so
    /// the transaction still has exactly the same shape and only the identity of
    /// one account changed.
    private static func replacingStaticKey(
        at position: Int,
        with address: String,
        in base64: String
    ) throws -> String {
        var mutable = try MutableTransaction(base64: base64)
        let key = try XCTUnwrap(Base58.decodeNoCheck(string: address))
        mutable.keys[position] = [UInt8](key)
        return try mutable.base64()
    }

    /// Rewrites the `SetComputeUnitPrice` argument, leaving the message's shape
    /// untouched.
    private static func replacingUnitPrice(_ price: UInt64, in base64: String) throws -> String {
        var mutable = try MutableTransaction(base64: base64)
        let position = try XCTUnwrap(
            mutable.instructions.firstIndex { $0.data.first == ComputeBudgetInstruction.setUnitPrice }
        )
        mutable.instructions[position].data =
            [ComputeBudgetInstruction.setUnitPrice] + withUnsafeBytes(of: price.littleEndian) { [UInt8]($0) }
        return try mutable.base64()
    }

    /// Drops one instruction, re-serialising the message around it.
    ///
    /// Shares `MutableTransaction` with the validator's own tests, which pin
    /// that an unmodified round trip is byte-identical — so a refusal here comes
    /// from the missing instruction rather than from the rebuild.
    private static func removingInstruction(at position: Int, from base64: String) throws -> String {
        var mutable = try MutableTransaction(base64: base64)
        mutable.instructions.remove(at: position)
        return try mutable.base64()
    }

    /// Rewrites the 16 argument bytes of the transaction's `farms::unstake`
    /// in place.
    ///
    /// A byte splice rather than a re-serialise, and safe for the same reason
    /// the blockhash splice is: the payload keeps its length, so every shortvec
    /// count and every following offset is unchanged. Nothing else in the
    /// message is touched, which is what makes a resulting refusal attributable
    /// to the amount.
    private static func replacingUnstakeAmount(in base64: String, with value: BigInt) throws -> String {
        var bytes = [UInt8](try XCTUnwrap(Data(base64Encoded: base64)))
        let discriminator = KaminoInstructionDiscriminator.farmsUnstake

        var matches = 0
        var start: Int?
        for offset in 0...(bytes.count - discriminator.count)
        where Array(bytes[offset..<offset + discriminator.count]) == discriminator {
            matches += 1
            start = offset
        }
        XCTAssertEqual(matches, 1, "expected exactly one farms::unstake payload")

        let argument = try XCTUnwrap(start) + discriminator.count
        var remaining = value
        for index in 0..<16 {
            bytes[argument + index] = UInt8(truncatingIfNeeded: Int(remaining & BigInt(0xFF)))
            remaining >>= 8
        }
        return Data(bytes).base64EncodedString()
    }
}
