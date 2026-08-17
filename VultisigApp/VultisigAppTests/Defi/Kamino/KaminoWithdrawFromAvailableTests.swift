//
//  KaminoWithdrawFromAvailableTests.swift
//  VultisigAppTests
//
//  A withdraw does not arrive as one instruction. It arrives as EITHER
//  `kvault::withdraw` or `kvault::withdraw_from_available`, and which one is a
//  fact about the vault's liquid buffer at the moment the API builds it.
//
//  The app knew only the first, so every withdraw decoded to nothing and the
//  verify screen refused to describe bytes it was being asked to co-sign. These
//  tests pin both — and, because the two are genuinely different instructions
//  read through ONE account index map, they pin the thing that makes sharing the
//  map legitimate rather than convenient: the two put the same accounts in the
//  same slots for every slot the app reads.
//
//  Three vectors, captured 2026-08-17 from `api.kamino.finance` by POSTing
//  `/ktx/kvault/withdraw` for third-party wallets and decoding the reply. The
//  API builds UNSIGNED transactions for any address: nothing was signed, nothing
//  was broadcast, no funds moved.
//

import BigInt
import CryptoKit
@testable import VultisigApp
import XCTest

final class KaminoWithdrawFromAvailableTests: XCTestCase {

    // MARK: - The discriminators are derived, not pasted

    /// Both kVault withdraw discriminators, recomputed from the instruction NAME
    /// with a hash implementation the app does not use.
    ///
    /// The derivation is the identification. A constant lifted out of a captured
    /// transaction matches the bytes it was lifted from and says nothing about
    /// what they are; one that equals `sha256("global:<name>")[0..<8]` says the
    /// bytes are that instruction. This is the check the original constant never
    /// had a partner for — it was right about `withdraw` and simply named the
    /// wrong instruction.
    func testBothWithdrawDiscriminatorsAreTheirAnchorNames() {
        XCTAssertEqual(
            KaminoInstructionDiscriminator.kvaultWithdraw,
            Self.anchorDiscriminator("withdraw")
        )
        XCTAssertEqual(
            KaminoInstructionDiscriminator.kvaultWithdrawFromAvailable,
            Self.anchorDiscriminator("withdraw_from_available")
        )
        XCTAssertEqual(
            KaminoInstructionDiscriminator.kvaultDeposit,
            Self.anchorDiscriminator("deposit")
        )
    }

    /// Three kVault instructions, three distinct eight-byte prefixes. A collision
    /// would make one of them unreachable and the other a liar.
    func testTheKvaultDiscriminatorsAreDistinct() {
        let discriminators = [
            KaminoInstructionDiscriminator.kvaultDeposit,
            KaminoInstructionDiscriminator.kvaultWithdraw,
            KaminoInstructionDiscriminator.kvaultWithdrawFromAvailable
        ]
        XCTAssertEqual(Set(discriminators.map { Data($0) }).count, discriminators.count)
        for discriminator in discriminators {
            XCTAssertEqual(discriminator.count, 8)
        }
    }

    // MARK: - The captured bytes carry what the constants claim

    /// Read out of the wire, not out of the enum: each captured transaction's
    /// kVault instruction carries the discriminator its shape says it should,
    /// and the `u64` share argument the request asked for.
    func testEveryCapturedShapeCarriesTheDiscriminatorAndAmountItClaims() throws {
        for shape in Self.shapes {
            let instruction = try Self.kvaultInstruction(of: shape)
            XCTAssertEqual(
                Array(instruction.data.prefix(8)),
                shape.discriminator,
                shape.name
            )
            XCTAssertEqual(
                KaminoInstructionDiscriminator.anchorArgument(instruction.data),
                shape.shareBaseUnits,
                shape.name
            )
        }
    }

    /// And the sequence walker calls every one of them a vault withdraw. This is
    /// the step that used to return `nil`, which is where the whole failure
    /// started.
    func testEveryCapturedShapeIsRecognisedAsAVaultWithdraw() throws {
        for shape in Self.shapes {
            let kinds = try Self.kinds(of: shape.source)
            XCTAssertEqual(
                kinds,
                [.createTokenAccount, .farmsUnstake, .farmsWithdrawUnstakedDeposits,
                 .createTokenAccount, .kvaultWithdraw],
                shape.name
            )
        }
    }

    /// The whole point of the fix, end to end: the offline decode a co-signer
    /// runs now describes these transactions instead of refusing them.
    func testTheOfflineDecodeReadsEveryCapturedShape() throws {
        for shape in Self.shapes {
            let decoded = try XCTUnwrap(
                KaminoTransactionDecoder.decode(rawTransactions: [shape.source]),
                shape.name
            )
            XCTAssertEqual(decoded.operation, .withdraw, shape.name)
            XCTAssertEqual(decoded.descriptor, shape.vault, shape.name)
            XCTAssertEqual(decoded.amountBaseUnits, BigInt(shape.shareBaseUnits), shape.name)
            XCTAssertEqual(decoded.signer, shape.owner, shape.name)
            XCTAssertFalse(decoded.withdrawsEntirePosition, shape.name)
            XCTAssertNil(decoded.priorityFee, shape.name)
        }
    }

    /// The exact pair of answers the verify screen keys `.unreadable` off.
    ///
    /// It reaches that state when the bytes DO invoke the kVaults program and the
    /// decode still returns nothing — which is precisely what every one of these
    /// used to do. Asserting both halves says the fix removed the refusal rather
    /// than removing the recognition.
    func testTheseAreTheBytesTheVerifyScreenUsedToCallUnreadable() throws {
        for shape in Self.shapes {
            let transaction = try SolanaV0Transaction(base64Transaction: shape.source)
            XCTAssertTrue(KaminoTransactionDecoder.invokesKaminoVault(transaction), shape.name)
            XCTAssertNotNil(KaminoTransactionDecoder.decode(transaction), shape.name)
        }
    }

    // MARK: - Why one account map may serve two instructions

    /// The load-bearing check.
    ///
    /// `withdraw` and `withdraw_from_available` are different instructions with
    /// different account counts, and the app reads both through
    /// `KaminoInstructionAccounts.KvaultWithdraw`. If their orderings differed,
    /// the verify screen would name a vault, a mint or a payout account that the
    /// instruction being signed does not put there — which is worse than the
    /// refusal this change removes.
    ///
    /// They do not differ. The program's IDL declares `withdraw`'s accounts as
    /// the `withdraw_from_available` group followed by the reserve-exit group, so
    /// the first fourteen are shared by construction. Here that is checked
    /// against the wire, by PUBKEY, on one wallet's withdraw from one vault built
    /// both ways minutes apart — which leaves the instruction choice as the only
    /// difference between the two.
    func testTheTwoWithdrawInstructionsAgreeOnEverySharedSlot() throws {
        let pair = KaminoTransactionFixtures.withdrawShapePair
        let available = try Self.resolvedKvaultAccounts(of: pair.available)
        let reserveExit = try Self.resolvedKvaultAccounts(of: pair.reserveExit)

        let shared = KaminoInstructionAccounts.KvaultWithdraw.sharedPrefixCount
        XCTAssertGreaterThanOrEqual(available.count, shared)
        XCTAssertGreaterThanOrEqual(reserveExit.count, shared)
        XCTAssertEqual(
            Array(available.prefix(shared)),
            Array(reserveExit.prefix(shared)),
            "the two withdraw instructions must name the same accounts in the shared prefix"
        )

        // And they are not simply the same instruction twice: the longer one
        // carries the reserve-exit group, which is where they part.
        XCTAssertNotEqual(available.count, reserveExit.count)
        XCTAssertNotEqual(available[shared], reserveExit[shared])
    }

    /// Every index the app actually reads lies inside that shared prefix. This is
    /// what turns the agreement above into permission to share the map: a later
    /// index added below `sharedPrefixCount` would be read out of a region the
    /// two instructions are not known to agree on, and this fails then.
    func testEveryIndexTheAppReadsLiesInsideTheSharedPrefix() {
        let indexes = [
            KaminoInstructionAccounts.KvaultWithdraw.user,
            KaminoInstructionAccounts.KvaultWithdraw.vault,
            KaminoInstructionAccounts.KvaultWithdraw.userTokenAccount,
            KaminoInstructionAccounts.KvaultWithdraw.tokenMint,
            KaminoInstructionAccounts.KvaultWithdraw.userShareAccount,
            KaminoInstructionAccounts.KvaultWithdraw.sharesMint
        ]
        for index in indexes {
            XCTAssertLessThan(index, KaminoInstructionAccounts.KvaultWithdraw.sharedPrefixCount)
        }
        XCTAssertLessThanOrEqual(
            KaminoInstructionAccounts.KvaultWithdraw.minimumCount,
            KaminoInstructionAccounts.KvaultWithdraw.sharedPrefixCount
        )
    }

    /// The slots are not merely equal to each other — they hold what the app says
    /// they hold, resolved through the real lookup table and compared against the
    /// pinned registry and a locally derived associated token account.
    ///
    /// Both instructions, because "the map is right for `withdraw`" and "the map
    /// is right for `withdraw_from_available`" are two claims.
    func testBothInstructionsNameTheVaultTheMintsAndTheSignersOwnAccounts() throws {
        let pair = KaminoTransactionFixtures.withdrawShapePair
        for shape in [pair.available, pair.reserveExit] {
            let accounts = try Self.resolvedKvaultAccounts(of: shape)
            let layout = KaminoInstructionAccounts.KvaultWithdraw.self

            XCTAssertEqual(accounts[layout.user], shape.owner, shape.name)
            XCTAssertEqual(accounts[layout.vault], shape.vault.address, shape.name)
            XCTAssertEqual(accounts[layout.tokenMint], shape.vault.tokenMint, shape.name)
            XCTAssertEqual(accounts[layout.sharesMint], shape.vault.sharesMint, shape.name)
            XCTAssertTrue(
                SolanaAssociatedTokenAccount
                    .ownedAccounts(owner: shape.owner, mint: shape.vault.sharesMint)
                    .contains(accounts[layout.userShareAccount]),
                shape.name
            )
            XCTAssertTrue(
                SolanaAssociatedTokenAccount
                    .ownedAccounts(owner: shape.owner, mint: shape.vault.tokenMint)
                    .contains(accounts[layout.userTokenAccount]),
                shape.name
            )
        }
    }

    /// The same request, built twelve days apart, switched instruction without
    /// changing a single account it hands it.
    ///
    /// `stakedWithdraw` was captured on 2026-08-05 as `withdraw`;
    /// `steakhouseWithdrawFromAvailable` is the same wallet, vault and one-share
    /// amount re-requested on 2026-08-17 and built as `withdraw_from_available`.
    /// So the drift that broke the decoder is recorded here as the API change it
    /// was, not as a constant that had always been wrong.
    func testTheSameRequestSwitchedInstructionButNotItsAccounts() throws {
        let legacy = try SolanaV0Transaction(
            base64Transaction: KaminoTransactionFixtures.stakedWithdraw.source
        )
        let legacyAccounts = try legacy.resolvedAccountAddresses(
            lookupTables: KaminoTransactionFixtures.lookupTables
        )
        let legacyInstruction = legacy.instructions[4]
        XCTAssertEqual(
            Array(legacyInstruction.data.prefix(8)),
            KaminoInstructionDiscriminator.kvaultWithdraw
        )

        let current = KaminoTransactionFixtures.steakhouseWithdrawFromAvailable
        let currentAccounts = try Self.resolvedKvaultAccounts(of: current)

        XCTAssertEqual(
            legacyInstruction.accountIndexes
                .prefix(KaminoInstructionAccounts.KvaultWithdraw.sharedPrefixCount)
                .map { legacyAccounts[Int($0)] },
            Array(currentAccounts.prefix(KaminoInstructionAccounts.KvaultWithdraw.sharedPrefixCount))
        )
        XCTAssertEqual(
            KaminoInstructionDiscriminator.anchorArgument(legacyInstruction.data),
            current.shareBaseUnits
        )
    }

    // MARK: - Through the initiating device's validator

    /// The check the initiating device makes before it signs, run over the bytes
    /// as captured.
    ///
    /// It is the strongest statement available about the account map, and it is
    /// a different statement from the decode: the validator resolves the address
    /// lookup table and compares the authority, the vault, both mints, the payout
    /// account and the share source against the request it is answering — so it
    /// fails if any of those slots holds something other than what the app says
    /// it holds. Both instructions, so the claim covers both.
    func testEveryCapturedShapeValidatesAgainstTheRequestItAnswers() throws {
        for shape in Self.shapes {
            try KaminoTransactionValidator.validate(
                transaction: try SolanaV0Transaction(base64Transaction: shape.source),
                intent: Self.intent(for: shape),
                lookupTables: KaminoTransactionFixtures.lookupTables
            )
        }
    }

    /// And it refuses one whose share source has been repointed at the payout
    /// account — so the acceptance above is the map being checked, not the map
    /// being ignored.
    ///
    /// The expected error is asserted WHOLE, role and address, rather than
    /// "something threw". A refusal for an unrelated reason would keep a test
    /// that only asked for a throw green while proving nothing about slot 7, and
    /// slot 7 is the account the shares come out of. The mutation swaps two
    /// account indices the message already carries, so nothing about its length
    /// or structure changes and there is no parse failure to hide behind.
    func testAWithdrawWhoseShareSourceWasRepointedIsRefusedOnThatSlot() throws {
        let shape = KaminoTransactionFixtures.steakhouseWithdrawFromAvailable
        var mutated = try MutableTransaction(base64: shape.source)
        let layout = KaminoInstructionAccounts.KvaultWithdraw.self
        let instruction = mutated.instructions[shape.kvaultPosition]
        let payoutIndex = instruction.accounts[layout.userTokenAccount]
        XCTAssertNotEqual(payoutIndex, instruction.accounts[layout.userShareAccount])
        mutated.instructions[shape.kvaultPosition].accounts[layout.userShareAccount] = payoutIndex

        let transaction = try SolanaV0Transaction(base64Transaction: try mutated.base64())
        let payout = try transaction.resolvedAccountAddresses(
            lookupTables: KaminoTransactionFixtures.lookupTables
        )[Int(payoutIndex)]

        XCTAssertThrowsError(
            try KaminoTransactionValidator.validate(
                transaction: transaction,
                intent: Self.intent(for: shape),
                lookupTables: KaminoTransactionFixtures.lookupTables
            )
        ) { error in
            XCTAssertEqual(
                error as? KaminoValidationError,
                .accountNotOwnedByUser(role: "withdraw share source", actual: payout)
            )
        }
    }

    // MARK: - Still fail-closed

    /// Widening the set of accepted discriminators is not the same as accepting
    /// whatever the kVault program is asked to do. A third one is still nothing
    /// this decoder will describe.
    func testAnUnrecognisedKvaultInstructionIsStillRefused() throws {
        let shape = KaminoTransactionFixtures.steakhouseWithdrawFromAvailable
        var mutated = try MutableTransaction(base64: shape.source)
        // `kvault::deposit_with_min_shares_out` — a real instruction of the same
        // program that this app never asks for.
        mutated.instructions[shape.kvaultPosition].data.replaceSubrange(
            0..<8,
            with: Self.anchorDiscriminator("deposit_with_min_shares_out")
        )
        let refused = try mutated.base64()

        XCTAssertNil(KaminoTransactionDecoder.decode(rawTransactions: [refused]))
        XCTAssertNotNil(KaminoTransactionDecoder.decode(rawTransactions: [shape.source]))
    }

    /// A single flipped byte in the discriminator is not "close enough" either.
    func testAOneByteDiscriminatorEditIsRefused() throws {
        let shape = KaminoTransactionFixtures.steakhouseWithdrawFromAvailable
        var mutated = try MutableTransaction(base64: shape.source)
        mutated.instructions[shape.kvaultPosition].data[0] ^= 0x01
        XCTAssertNil(KaminoTransactionDecoder.decode(rawTransactions: [try mutated.base64()]))
    }

    /// The deposit discriminator is untouched by all of this, and a deposit is
    /// still read as a deposit rather than folded into the withdraw branch.
    func testTheDepositPathIsUnaffected() throws {
        let decoded = try XCTUnwrap(
            KaminoTransactionDecoder.decode(
                rawTransactions: [KaminoTransactionFixtures.usdcDeposit.source]
            )
        )
        XCTAssertEqual(decoded.operation, .deposit)
    }

    // MARK: - Helpers

    private static var shapes: [KaminoTransactionFixtures.WithdrawShape] {
        [
            KaminoTransactionFixtures.steakhouseWithdrawFromAvailable,
            KaminoTransactionFixtures.rwaWithdrawFromAvailable,
            KaminoTransactionFixtures.rwaReserveExitWithdraw
        ]
    }

    private static func anchorDiscriminator(_ name: String) -> [UInt8] {
        [UInt8](SHA256.hash(data: Data("global:\(name)".utf8)).prefix(8))
    }

    /// The request each capture answers. Every one is a whole-position holder
    /// withdrawing from a farm-staked balance, so the unstaked half is zero and
    /// the farms pair is required — which is what the API built.
    ///
    /// Only the live fields are supplied; the mints, their decimals and the farm
    /// come from the registry, which is the point of pinning them there.
    private static func intent(
        for shape: KaminoTransactionFixtures.WithdrawShape
    ) -> KaminoTransactionIntent {
        let descriptor = shape.vault
        return KaminoTransactionIntent(
            operation: .withdraw(
                KaminoWithdrawRequest(
                    shares: KaminoShareAmount(
                        baseUnits: BigInt(shape.shareBaseUnits),
                        decimals: descriptor.sharesDecimals
                    ),
                    unstakedShares: KaminoShareAmount(
                        baseUnits: BigInt(0),
                        decimals: descriptor.sharesDecimals
                    )
                )
            ),
            vault: KaminoVaultInfo(
                descriptor: descriptor,
                name: descriptor.fallbackName,
                minDeposit: KaminoTokenAmount(
                    baseUnits: BigInt(100_000),
                    decimals: descriptor.tokenDecimals
                ),
                minWithdraw: KaminoShareAmount(
                    baseUnits: BigInt(1_000),
                    decimals: descriptor.sharesDecimals
                ),
                lookupTable: shape.lookupTable,
                apy30d: Decimal(string: "0.0391") ?? .zero,
                tokensPerShare: KaminoRate(apiString: "1.0536041812651029025")
                    ?? KaminoRate(apiString: "1")!,
                tokenPriceUsd: 1
            ),
            owner: shape.owner
        )
    }

    private static func kvaultInstruction(
        of shape: KaminoTransactionFixtures.WithdrawShape
    ) throws -> SolanaV0Transaction.Instruction {
        let transaction = try SolanaV0Transaction(base64Transaction: shape.source)
        return transaction.instructions[shape.kvaultPosition]
    }

    /// The kVault instruction's accounts as PUBKEYS, with the lookup table
    /// resolved. An account index is only a position; comparing indices across
    /// two different transactions would compare nothing.
    private static func resolvedKvaultAccounts(
        of shape: KaminoTransactionFixtures.WithdrawShape
    ) throws -> [String] {
        let transaction = try SolanaV0Transaction(base64Transaction: shape.source)
        let accounts = try transaction.resolvedAccountAddresses(
            lookupTables: KaminoTransactionFixtures.lookupTables
        )
        return transaction.instructions[shape.kvaultPosition].accountIndexes.map { accounts[Int($0)] }
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
}
