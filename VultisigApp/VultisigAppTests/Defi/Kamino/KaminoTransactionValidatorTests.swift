//
//  KaminoTransactionValidatorTests.swift
//  VultisigAppTests
//
//  Kamino builds the transaction, the app signs the bytes verbatim, and Blockaid
//  is advisory — so this validator is the only thing between a compromised or
//  buggy API response and a signature over it. A test suite that only proved the
//  happy paths pass would prove nothing about that, so most of what follows takes
//  a transaction that is known to execute on mainnet, changes exactly one thing an
//  attacker would want changed, and asserts a refusal.
//

import BigInt
@testable import VultisigApp
import WalletCore
import XCTest

final class KaminoTransactionValidatorTests: XCTestCase {

    // MARK: - Happy paths

    func testAcceptsTheUsdcDepositAsBuilt() throws {
        try assertValid(KaminoTransactionFixtures.usdcDeposit.source, intent: Self.usdcDepositIntent)
    }

    func testAcceptsTheSolDepositAsBuilt() throws {
        try assertValid(KaminoTransactionFixtures.solDeposit.source, intent: Self.solDepositIntent)
    }

    func testAcceptsTheUsdcWithdrawAsBuilt() throws {
        try assertValid(KaminoTransactionFixtures.usdcWithdraw.source, intent: Self.usdcWithdrawIntent)
    }

    /// The priority fee is injected after validation and the transaction is
    /// re-simulated, so the validator has to accept its own output too — otherwise
    /// it could not be re-run as a final gate before keysign.
    func testAcceptsTheComputeBudgetInjectedTransactions() throws {
        try assertValid(
            KaminoTransactionFixtures.usdcDeposit.injected,
            intent: Self.usdcDepositIntent.replacing(priorityFee: Self.fee(KaminoTransactionFixtures.usdcDeposit))
        )
        try assertValid(
            KaminoTransactionFixtures.solDeposit.injected,
            intent: Self.solDepositIntent.replacing(priorityFee: Self.fee(KaminoTransactionFixtures.solDeposit))
        )
        try assertValid(
            KaminoTransactionFixtures.usdcWithdraw.injected,
            intent: Self.usdcWithdrawIntent.replacing(priorityFee: Self.fee(KaminoTransactionFixtures.usdcWithdraw))
        )
    }

    /// A full withdraw closes the emptied token account. The sampled vector is a
    /// partial withdraw, so the closing instruction is appended here — its rent
    /// destination is the user, which is what makes it acceptable.
    func testAcceptsAWithdrawThatClosesTheUserTokenAccount() throws {
        var mutable = try MutableTransaction(base64: KaminoTransactionFixtures.usdcWithdraw.source)
        let tokenProgram = mutable.appendStaticReadonlyKey(Self.tokenProgramKey)
        mutable.instructions.append(
            .init(
                programIdIndex: tokenProgram,
                accounts: [Self.withdrawUserTokenAccountIndex, Self.ownerIndex, Self.ownerIndex],
                data: [KaminoInstructionDiscriminator.tokenCloseAccount]
            )
        )

        try assertValid(try mutable.base64(), intent: Self.usdcWithdrawIntent)
    }

    // MARK: - The farm-staked withdraw is knowingly unsupported

    /// The refusal `expectedSequence`'s extension point describes, pinned so it
    /// cannot be lost.
    ///
    /// Every deposit into these vaults auto-stakes its shares, so a real
    /// withdraw has to unstake them first — and that transaction has never been
    /// observed. The validator has no template for it and refuses it as an
    /// instruction this operation does not perform. That is the intended
    /// behaviour until the shape is captured rather than guessed: a step written
    /// from a guess would validate the guess.
    ///
    /// Trailing position: the unstake lands after the withdraw.
    func testRefusesAWithdrawCarryingAFarmInstructionAfterIt() throws {
        var mutable = try MutableTransaction(base64: KaminoTransactionFixtures.usdcWithdraw.source)
        let farms = mutable.appendStaticReadonlyKey(Self.farmsProgramKey)
        mutable.instructions.append(
            .init(programIdIndex: farms, accounts: [Self.ownerIndex], data: Self.farmsUnstakeData)
        )

        assertRefused(
            try mutable.base64(),
            intent: Self.usdcWithdrawIntent,
            expected: .unexpectedInstruction(index: 2, program: KaminoVaultRegistry.farmsProgramId)
        )
    }

    /// Leading position: the unstake lands before the withdraw, which is where a
    /// real one most plausibly sits. The refusal is a different one — the
    /// template's required step no longer matches where it was expected — and
    /// that is the point: neither ordering slips through.
    func testRefusesAWithdrawCarryingAFarmInstructionBeforeIt() throws {
        var mutable = try MutableTransaction(base64: KaminoTransactionFixtures.usdcWithdraw.source)
        let farms = mutable.appendStaticReadonlyKey(Self.farmsProgramKey)
        mutable.instructions.insert(
            .init(programIdIndex: farms, accounts: [Self.ownerIndex], data: Self.farmsUnstakeData),
            at: 1
        )

        assertRefused(
            try mutable.base64(),
            intent: Self.usdcWithdrawIntent,
            expected: .missingInstruction("vault withdraw")
        )
    }

    /// The mutations below are only meaningful if re-serialising an unmodified
    /// transaction reproduces it byte for byte — otherwise a refusal could come
    /// from the rebuild rather than from the change under test.
    func testRebuildingAnUnmodifiedTransactionIsByteIdentical() throws {
        for vector in KaminoTransactionFixtures.all {
            let original = try XCTUnwrap(Data(base64Encoded: vector.source))
            let rebuilt = try MutableTransaction(base64: vector.source).bytes()
            XCTAssertEqual(rebuilt, [UInt8](original), vector.name)
        }
    }

    // MARK: - Operation, vault and amount

    func testRejectsAWithdrawTransactionOfferedAsADeposit() throws {
        assertRefused(
            KaminoTransactionFixtures.usdcWithdraw.source,
            intent: Self.usdcWithdrawIntent.replacing(operation: .deposit(Self.usdcDepositAmount)),
            expected: .missingInstruction("vault deposit")
        )
    }

    func testRejectsADepositTransactionOfferedAsAWithdraw() throws {
        assertRefused(
            KaminoTransactionFixtures.usdcDeposit.source,
            intent: Self.usdcDepositIntent.replacing(operation: .withdraw(Self.usdcWithdrawShares)),
            expected: .missingInstruction("vault withdraw")
        )
    }

    /// The vault the instruction targets, not the vault the caller said it asked
    /// about. Everything else here is untouched and correct, so only the kvault
    /// instruction's own account can tell the two apart.
    func testRejectsAVaultAccountOtherThanTheOneRequested() throws {
        var mutable = try MutableTransaction(base64: KaminoTransactionFixtures.usdcDeposit.source)
        mutable.instructions[Self.usdcDepositKvaultIndex].accounts[1] = Self.foreignWritableIndex

        assertRefused(
            try mutable.base64(),
            intent: Self.usdcDepositIntent,
            expected: .accountMismatch(
                role: "vault",
                expected: KaminoVaultRegistry.steakhouseUSDC.address,
                actual: Self.foreignWritableAddress
            )
        )
    }

    /// The two USDC vaults share an underlying token but nothing else. Because
    /// the mints and the farm are pinned in the registry rather than read from
    /// the response, asking about one and being handed the other's transaction
    /// diverges at the first account either one names.
    func testRejectsATransactionBuiltForTheOtherUsdcVault() throws {
        let intent = Self.usdcDepositIntent.replacing(descriptor: KaminoVaultRegistry.rwaUSDC)
        assertRefused(
            KaminoTransactionFixtures.usdcDeposit.source,
            intent: intent,
            expected: .accountMismatch(
                role: "created token account mint",
                expected: "\(KaminoVaultRegistry.rwaUSDC.tokenMint) or \(KaminoVaultRegistry.rwaUSDC.sharesMint)",
                actual: KaminoVaultRegistry.steakhouseUSDC.sharesMint
            )
        )
    }

    func testRejectsAVaultOutsideTheRegistryAllowList() throws {
        let unknown = KaminoVaultDescriptor(
            address: "5rGkiF4Jf1rPTJ6nazBgcjewVktXhagwcw5Nux7GccRi",
            tokenMint: KaminoVaultRegistry.usdcMint,
            tokenDecimals: 6,
            sharesMint: "7D8C5pDFxug58L9zkwK7bCiDg4kD4AygzbcZUmf5usHS",
            sharesDecimals: 6,
            farm: nil,
            fallbackName: "Not ours",
            curator: "Unknown",
            riskTier: .conservative
        )
        assertRefused(
            KaminoTransactionFixtures.usdcDeposit.source,
            intent: Self.usdcDepositIntent.replacing(descriptor: unknown),
            expected: .vaultNotAllowed(unknown.address)
        )
    }

    func testRejectsAnAlteredDepositAmount() throws {
        var mutable = try MutableTransaction(base64: KaminoTransactionFixtures.usdcDeposit.source)
        mutable.instructions[Self.usdcDepositKvaultIndex].data = Self.anchorData(
            discriminator: KaminoInstructionDiscriminator.kvaultDeposit,
            argument: 20_000_000
        )

        assertRefused(
            try mutable.base64(),
            intent: Self.usdcDepositIntent,
            expected: .amountMismatch(role: "deposit amount", expected: "10000000", actual: "20000000")
        )
    }

    /// One base unit over is the whole attack: the API rewrites a withdraw above
    /// the user's share balance to `u64::MAX`, which means withdraw everything.
    func testRejectsAWithdrawAmountOffByOneShare() throws {
        var mutable = try MutableTransaction(base64: KaminoTransactionFixtures.usdcWithdraw.source)
        mutable.instructions[Self.usdcWithdrawKvaultIndex].data = Self.anchorData(
            discriminator: KaminoInstructionDiscriminator.kvaultWithdraw,
            argument: 5_500_001
        )

        assertRefused(
            try mutable.base64(),
            intent: Self.usdcWithdrawIntent,
            expected: .amountMismatch(role: "withdraw share amount", expected: "5500000", actual: "5500001")
        )
    }

    /// Deposit takes token base units, withdraw takes SHARE base units. The typed
    /// amounts make confusing them a compile error at the call site; this is the
    /// same confusion arriving from the API side instead.
    func testRejectsAWithdrawSizedInTokensRatherThanShares() throws {
        let tokens = KaminoTokenAmount(baseUnits: BigInt(5_500_000), decimals: 6)
        guard let asShares = tokens.shareAmount(
            tokensPerShare: Self.steakhouseTokensPerShare,
            shareDecimals: 6
        ) else {
            return XCTFail("conversion failed")
        }
        XCTAssertNotEqual(asShares.baseUnits, BigInt(5_500_000), "the rate must actually move the number")

        assertRefused(
            KaminoTransactionFixtures.usdcWithdraw.source,
            intent: Self.usdcWithdrawIntent.replacing(operation: .withdraw(asShares)),
            expected: .amountMismatch(
                role: "withdraw share amount",
                expected: String(describing: asShares.baseUnits),
                actual: "5500000"
            )
        )
    }

    func testRejectsASolWrapForADifferentAmountThanTheDeposit() throws {
        var mutable = try MutableTransaction(base64: KaminoTransactionFixtures.solDeposit.source)
        mutable.instructions[Self.solDepositTransferIndex].data =
            KaminoInstructionDiscriminator.systemTransfer + Self.littleEndian(1_500_000_000)

        assertRefused(
            try mutable.base64(),
            intent: Self.solDepositIntent,
            expected: .amountMismatch(
                role: "wrapped SOL amount",
                expected: "500000000",
                actual: "1500000000"
            )
        )
    }

    // MARK: - Destination

    /// The share account the deposit mints into, replaced with an address the
    /// user does not control. Derivation is what catches it: the ATA is a
    /// function of owner, mint and token program, so it can be recomputed.
    func testRejectsSharesDeliveredToAThirdPartyAccount() throws {
        var mutable = try MutableTransaction(base64: KaminoTransactionFixtures.usdcDeposit.source)
        mutable.keys[Self.usdcDepositShareAccountKeyIndex] = Self.attackerKey

        assertRefused(
            try mutable.base64(),
            intent: Self.usdcDepositIntent,
            expected: .accountMismatch(
                role: "created token account",
                expected: Self.usdcDepositShareAccount,
                actual: Self.attackerAddress
            )
        )
    }

    /// The same substitution done only inside the kvault instruction, so the
    /// account-creation instruction still looks correct. Caught by the deposit's
    /// own destination check rather than by the creation's.
    func testRejectsAShareDestinationRepointedInsideTheVaultInstruction() throws {
        var mutable = try MutableTransaction(base64: KaminoTransactionFixtures.usdcDeposit.source)
        mutable.instructions[Self.usdcDepositKvaultIndex].accounts[7] = Self.foreignWritableIndex

        assertRefused(
            try mutable.base64(),
            intent: Self.usdcDepositIntent,
            expected: .accountNotOwnedByUser(
                role: "deposit share destination",
                actual: Self.foreignWritableAddress
            )
        )
    }

    func testRejectsWrappedSolSentSomewhereOtherThanTheUsersOwnAccount() throws {
        var mutable = try MutableTransaction(base64: KaminoTransactionFixtures.solDeposit.source)
        mutable.instructions[Self.solDepositTransferIndex].accounts[1] = Self.solForeignWritableIndex

        assertRefused(
            try mutable.base64(),
            intent: Self.solDepositIntent,
            expected: .accountNotOwnedByUser(
                role: "SOL transfer destination",
                actual: Self.solForeignWritableAddress
            )
        )
    }

    /// Closing a token account sweeps its lamports. A close whose rent lands
    /// somewhere other than the user is a drain wearing a housekeeping costume.
    func testRejectsACloseWhoseRentGoesToAThirdParty() throws {
        var mutable = try MutableTransaction(base64: KaminoTransactionFixtures.usdcWithdraw.source)
        let tokenProgram = mutable.appendStaticReadonlyKey(Self.tokenProgramKey)
        mutable.instructions.append(
            .init(
                programIdIndex: tokenProgram,
                accounts: [
                    Self.withdrawUserTokenAccountIndex,
                    Self.withdrawForeignWritableIndex,
                    Self.ownerIndex
                ],
                data: [KaminoInstructionDiscriminator.tokenCloseAccount]
            )
        )

        assertRefused(
            try mutable.base64(),
            intent: Self.usdcWithdrawIntent,
            expected: .accountMismatch(
                role: "closed account rent destination",
                expected: Self.withdrawOwner,
                actual: Self.foreignWritableAddress
            )
        )
    }

    /// The stake moves the user's whole share balance into whatever farm the
    /// instruction names. A farm that is not this vault's own would park the
    /// position somewhere the app never looks.
    func testRejectsAStakeIntoAFarmThatIsNotTheVaultsOwn() throws {
        var mutable = try MutableTransaction(base64: KaminoTransactionFixtures.usdcDeposit.source)
        mutable.instructions[Self.farmsStakeIndex].accounts[Self.farmsStakeFarmPosition] =
            Self.foreignWritableIndex

        assertRefused(
            try mutable.base64(),
            intent: Self.usdcDepositIntent,
            expected: .accountMismatch(
                role: "farm",
                expected: Self.steakhouseFarm,
                actual: Self.foreignWritableAddress
            )
        )
    }

    /// The mints and the farm are only trustworthy because they come from the
    /// registry, so a vault that carries an allow-listed address while describing
    /// itself differently would hand back the pinning it is supposed to provide.
    func testRejectsAVaultDescriptorTheRegistryDoesNotRecognise() throws {
        assertRefused(
            KaminoTransactionFixtures.usdcDeposit.source,
            intent: Self.usdcDepositIntent.replacing(farm: Self.allezFarm),
            expected: .vaultDescriptorMismatch(KaminoVaultRegistry.steakhouseUSDC.address)
        )
    }

    // MARK: - Programs

    func testRejectsAnInstructionFromAProgramOutsideTheAllowList() throws {
        var mutable = try MutableTransaction(base64: KaminoTransactionFixtures.usdcDeposit.source)
        mutable.keys[Self.usdcDepositKvaultProgramKeyIndex] = Self.attackerKey

        assertRefused(
            try mutable.base64(),
            intent: Self.usdcDepositIntent,
            expected: .programNotAllowed(instruction: Self.usdcDepositKvaultIndex, program: Self.attackerAddress)
        )
    }

    // MARK: - Extra instructions

    func testRejectsAnInjectedTransferAppendedToADeposit() throws {
        var mutable = try MutableTransaction(base64: KaminoTransactionFixtures.usdcDeposit.source)
        mutable.instructions.append(
            .init(
                programIdIndex: Self.usdcDepositSystemProgramIndex,
                accounts: [Self.ownerIndex, Self.foreignWritableIndex],
                data: KaminoInstructionDiscriminator.systemTransfer + Self.littleEndian(900_000_000)
            )
        )

        assertRefused(
            try mutable.base64(),
            intent: Self.usdcDepositIntent,
            expected: .unexpectedInstruction(index: 4, program: KaminoSolanaProgram.system.rawValue)
        )
    }

    /// An instruction spliced into the middle rather than appended. It cannot
    /// match the step the walk is on, and nothing downstream re-syncs — so the
    /// sequence fails rather than skipping past it.
    func testRejectsAnInjectedTransferSplicedBeforeTheDeposit() throws {
        var mutable = try MutableTransaction(base64: KaminoTransactionFixtures.usdcDeposit.source)
        mutable.instructions.insert(
            .init(
                programIdIndex: Self.usdcDepositSystemProgramIndex,
                accounts: [Self.ownerIndex, Self.foreignWritableIndex],
                data: KaminoInstructionDiscriminator.systemTransfer + Self.littleEndian(900_000_000)
            ),
            at: Self.usdcDepositKvaultIndex
        )

        assertRefused(
            try mutable.base64(),
            intent: Self.usdcDepositIntent,
            expected: .missingInstruction("vault deposit")
        )
    }

    // MARK: - Priority fee

    /// The fee is `limit × price` lamports out of the user's balance and Kamino
    /// emits no ComputeBudget instruction at all, so one arriving with the
    /// response is a spend nobody asked for.
    func testRejectsAPriorityFeeTheAppDidNotChoose() throws {
        assertRefused(
            KaminoTransactionFixtures.usdcDeposit.injected,
            intent: Self.usdcDepositIntent,
            expected: .unexpectedPriorityFee(index: 0)
        )
    }

    /// The price is the half worth inflating: a `u64` of micro-lamports with
    /// nothing on chain capping the resulting fee below the payer's balance.
    func testRejectsAnInflatedComputeUnitPrice() throws {
        var mutable = try MutableTransaction(base64: KaminoTransactionFixtures.usdcDeposit.injected)
        mutable.instructions[Self.computeUnitPriceIndex].data =
            [ComputeBudgetInstruction.setUnitPrice] + Self.littleEndian(50_000_000_000)

        assertRefused(
            try mutable.base64(),
            intent: Self.usdcDepositIntent.replacing(priorityFee: Self.fee(KaminoTransactionFixtures.usdcDeposit)),
            expected: .amountMismatch(
                role: "compute unit price",
                expected: String(KaminoTransactionFixtures.unitPriceMicroLamports),
                actual: "50000000000"
            )
        )
    }

    func testRejectsAComputeUnitLimitOtherThanTheOneInjected() throws {
        var mutable = try MutableTransaction(base64: KaminoTransactionFixtures.usdcDeposit.injected)
        mutable.instructions[Self.computeUnitLimitIndex].data =
            [ComputeBudgetInstruction.setUnitLimit] + Self.littleEndianUInt32(1_400_000)

        assertRefused(
            try mutable.base64(),
            intent: Self.usdcDepositIntent.replacing(priorityFee: Self.fee(KaminoTransactionFixtures.usdcDeposit)),
            expected: .amountMismatch(
                role: "compute unit limit",
                expected: String(KaminoTransactionFixtures.usdcDeposit.unitLimit),
                actual: "1400000"
            )
        )
    }

    /// A ComputeBudget instruction that is neither of the two priority-fee ones.
    /// A heap-frame request would raise the fee-payer's cost without ever
    /// matching a template step.
    func testRejectsAnUnrecognisedComputeBudgetInstruction() throws {
        var mutable = try MutableTransaction(base64: KaminoTransactionFixtures.usdcDeposit.injected)
        mutable.instructions[Self.computeUnitLimitIndex].data =
            [ComputeBudgetInstruction.requestHeapFrame, 0, 0, 0, 0]

        assertRefused(
            try mutable.base64(),
            intent: Self.usdcDepositIntent.replacing(priorityFee: Self.fee(KaminoTransactionFixtures.usdcDeposit)),
            expected: .missingInstruction("compute unit limit")
        )
    }

    /// A fee was injected, so both instructions have to be there. One alone
    /// would mean a limit priced off the runtime default, or a price applied to
    /// a limit nobody bounded.
    func testRejectsAnInjectedTransactionMissingItsPriceInstruction() throws {
        var mutable = try MutableTransaction(base64: KaminoTransactionFixtures.usdcDeposit.injected)
        mutable.instructions.remove(at: Self.computeUnitPriceIndex)

        assertRefused(
            try mutable.base64(),
            intent: Self.usdcDepositIntent.replacing(priorityFee: Self.fee(KaminoTransactionFixtures.usdcDeposit)),
            expected: .missingInstruction("compute unit price")
        )
    }

    // MARK: - Writable accounts

    /// An extra account handed to an otherwise correct `createIdempotent`. Every
    /// positional check still passes; what refuses it is that a builder-composed
    /// instruction can now write to an account this operation cannot name.
    func testRejectsAnUnexplainedWritableAccountOnABuilderInstruction() throws {
        var mutable = try MutableTransaction(base64: KaminoTransactionFixtures.usdcDeposit.source)
        mutable.instructions[0].accounts.append(Self.foreignWritableIndex)

        assertRefused(
            try mutable.base64(),
            intent: Self.usdcDepositIntent,
            expected: .unattributableWritableAccount(
                program: KaminoSolanaProgram.associatedToken.rawValue,
                account: Self.foreignWritableAddress
            )
        )
    }

    /// The farm's own share vault is written by exactly one instruction. Point
    /// that one slot at an account already in use and the vault stays loaded
    /// writable with nothing touching it — a write privilege no instruction
    /// explains, which is not a shape any honest builder emits.
    func testRejectsAWritableAccountNoInstructionUses() throws {
        var mutable = try MutableTransaction(base64: KaminoTransactionFixtures.usdcDeposit.source)
        mutable.instructions[Self.farmsStakeIndex].accounts[Self.farmsStakeFarmVaultPosition] =
            Self.foreignWritableIndex

        assertRefused(
            try mutable.base64(),
            intent: Self.usdcDepositIntent,
            expected: .unreferencedWritableAccount(Self.steakhouseFarmVault)
        )
    }

    /// The stake is what turns the minted shares into the position the app reads.
    /// A farm-backed deposit that omits it is not the deposit that was requested,
    /// so it cannot be waved through as an optional step.
    func testRejectsAFarmBackedDepositThatDoesNotStake() throws {
        var mutable = try MutableTransaction(base64: KaminoTransactionFixtures.usdcDeposit.source)
        mutable.instructions.removeLast()

        assertRefused(
            try mutable.base64(),
            intent: Self.usdcDepositIntent,
            expected: .missingInstruction("farm stake")
        )
    }

    // MARK: - Shape and lookup tables

    func testRejectsATransactionPaidForBySomeoneElse() throws {
        let intent = Self.usdcDepositIntent.replacing(owner: Self.withdrawOwner)
        XCTAssertThrowsError(
            try KaminoTransactionValidator.validate(
                transaction: try SolanaV0Transaction(base64Transaction: KaminoTransactionFixtures.usdcDeposit.source),
                intent: intent,
                lookupTables: KaminoTransactionFixtures.lookupTables
            )
        ) { error in
            XCTAssertEqual(
                error as? SolanaV0TransactionError,
                .feePayerMismatch(expected: Self.withdrawOwner, actual: Self.depositOwner)
            )
        }
    }

    /// A lookup table decides which pubkey an index names, so a foreign one is
    /// where an account substitution would hide.
    func testRejectsAForeignAddressLookupTable() throws {
        var mutable = try MutableTransaction(base64: KaminoTransactionFixtures.usdcDeposit.source)
        let foreign = try XCTUnwrap(Base58.decodeNoCheck(string: KaminoTransactionFixtures.solDeposit.lookupTable))
        mutable.lookups[0].table = [UInt8](foreign)

        XCTAssertThrowsError(
            try KaminoTransactionValidator.validate(
                transaction: try SolanaV0Transaction(base64Transaction: try mutable.base64()),
                intent: Self.usdcDepositIntent,
                lookupTables: KaminoTransactionFixtures.lookupTables
            )
        ) { error in
            XCTAssertEqual(
                error as? KaminoValidationError,
                .unexpectedLookupTable(
                    expected: KaminoTransactionFixtures.usdcDeposit.lookupTable,
                    actual: KaminoTransactionFixtures.solDeposit.lookupTable
                )
            )
        }
    }

    /// The table contents are the transaction's meaning. Same bytes, one entry
    /// swapped, and every index that pointed at the vault now points elsewhere.
    func testRejectsWhenTheLookupTableResolvesTheVaultToAnotherAccount() throws {
        var tables = KaminoTransactionFixtures.lookupTables
        let table = KaminoTransactionFixtures.usdcDeposit.lookupTable
        var contents = try XCTUnwrap(tables[table])
        XCTAssertEqual(contents[1], KaminoVaultRegistry.steakhouseUSDC.address)
        contents[1] = Self.attackerAddress
        tables[table] = contents

        XCTAssertThrowsError(
            try KaminoTransactionValidator.validate(
                transaction: try SolanaV0Transaction(base64Transaction: KaminoTransactionFixtures.usdcDeposit.source),
                intent: Self.usdcDepositIntent,
                lookupTables: tables
            )
        ) { error in
            XCTAssertEqual(
                error as? KaminoValidationError,
                .accountMismatch(
                    role: "vault",
                    expected: KaminoVaultRegistry.steakhouseUSDC.address,
                    actual: Self.attackerAddress
                )
            )
        }
    }

    func testRefusesWhenALookupTableCannotBeResolved() throws {
        XCTAssertThrowsError(
            try KaminoTransactionValidator.validate(
                transaction: try SolanaV0Transaction(base64Transaction: KaminoTransactionFixtures.usdcDeposit.source),
                intent: Self.usdcDepositIntent,
                lookupTables: [:]
            )
        ) { error in
            XCTAssertEqual(
                error as? SolanaV0TransactionError,
                .unknownLookupTable(KaminoTransactionFixtures.usdcDeposit.lookupTable)
            )
        }
    }

    // MARK: - Resolution through the fetcher

    func testResolvesLookupTablesThroughTheFetcher() async throws {
        let validator = KaminoTransactionValidator(
            lookupTableSource: StubLookupTables(tables: KaminoTransactionFixtures.lookupTables)
        )
        let transaction = try SolanaV0Transaction(
            base64Transaction: KaminoTransactionFixtures.usdcDeposit.source
        )

        try await validator.validate(transaction: transaction, intent: Self.usdcDepositIntent)
    }

    func testPropagatesALookupTableFetchFailure() async throws {
        let validator = KaminoTransactionValidator(lookupTableSource: StubLookupTables(tables: [:], fails: true))
        let transaction = try SolanaV0Transaction(
            base64Transaction: KaminoTransactionFixtures.usdcDeposit.source
        )

        do {
            try await validator.validate(transaction: transaction, intent: Self.usdcDepositIntent)
            XCTFail("expected the fetch failure to propagate")
        } catch {
            XCTAssertEqual(
                error as? SolanaAddressLookupTableError,
                .accountNotFound(KaminoTransactionFixtures.usdcDeposit.lookupTable)
            )
        }
    }

    // MARK: - Discriminator provenance

    /// The four Anchor discriminators are `sha256("global:<name>")[0..<8]`. Pinning
    /// them against the hash rather than against the bytes that were observed
    /// means a typo in a constant that sizes or targets a transaction cannot
    /// survive to runtime.
    func testAnchorDiscriminatorsMatchTheirInstructionNames() throws {
        let expectations: [(String, [UInt8])] = [
            ("global:deposit", KaminoInstructionDiscriminator.kvaultDeposit),
            ("global:withdraw", KaminoInstructionDiscriminator.kvaultWithdraw),
            ("global:initialize_user", KaminoInstructionDiscriminator.farmsInitializeUser),
            ("global:stake", KaminoInstructionDiscriminator.farmsStake)
        ]
        for (name, discriminator) in expectations {
            let digest = Hash.sha256(data: Data(name.utf8))
            XCTAssertEqual([UInt8](digest.prefix(8)), discriminator, name)
        }
    }

    // MARK: - Helpers

    private func assertValid(
        _ base64: String,
        intent: KaminoTransactionIntent,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let transaction = try SolanaV0Transaction(base64Transaction: base64)
        do {
            try KaminoTransactionValidator.validate(
                transaction: transaction,
                intent: intent,
                lookupTables: KaminoTransactionFixtures.lookupTables
            )
        } catch {
            XCTFail("expected the transaction to validate, refused with: \(error)", file: file, line: line)
        }
    }

    private func assertRefused(
        _ base64: @autoclosure () throws -> String,
        intent: KaminoTransactionIntent,
        expected: KaminoValidationError,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        do {
            let transaction = try SolanaV0Transaction(base64Transaction: try base64())
            try KaminoTransactionValidator.validate(
                transaction: transaction,
                intent: intent,
                lookupTables: KaminoTransactionFixtures.lookupTables
            )
            XCTFail("expected \(expected)", file: file, line: line)
        } catch let error as KaminoValidationError {
            XCTAssertEqual(error, expected, file: file, line: line)
        } catch {
            XCTFail("expected \(expected), got \(error)", file: file, line: line)
        }
    }

    private static func anchorData(discriminator: [UInt8], argument: UInt64) -> [UInt8] {
        discriminator + littleEndian(argument)
    }

    private static func littleEndian(_ value: UInt64) -> [UInt8] {
        withUnsafeBytes(of: value.littleEndian) { [UInt8]($0) }
    }

    private static func littleEndianUInt32(_ value: UInt32) -> [UInt8] {
        withUnsafeBytes(of: value.littleEndian) { [UInt8]($0) }
    }

    /// The priority fee the golden vectors were injected with.
    private static func fee(_ vector: KaminoTransactionFixtures.Vector) -> KaminoPriorityFee {
        KaminoPriorityFee(limit: vector.unitLimit, price: KaminoTransactionFixtures.unitPriceMicroLamports)
    }
}

// MARK: - Fixtures

private extension KaminoTransactionValidatorTests {

    // Owners and accounts, read out of the decoded golden vectors.
    static let depositOwner = "9WzDXwBbmkg8ZTbNMqUxvQRAyrZzDsGYdLVL9zYtAWWM"
    static let withdrawOwner = "CXFmQi2eM4Jzt9HZwm9A5JAzGvNpKwRuxo52ua3Jyceh"

    static let ownerIndex: UInt8 = 0

    /// Static key 3 of the USDC deposit: the user's share account.
    static let usdcDepositShareAccountKeyIndex = 3
    static let usdcDepositShareAccount = "pTT7BQ26zy2YkBzNk3m7ywK4E4h4XD6oL2ns5SiJTnA"
    /// Static key 8 of the USDC deposit: the kvault program itself.
    static let usdcDepositKvaultProgramKeyIndex = 8
    static let usdcDepositSystemProgramIndex: UInt8 = 4
    static let usdcDepositKvaultIndex = 1
    static let usdcWithdrawKvaultIndex = 1
    static let solDepositTransferIndex = 1
    static let farmsStakeIndex = 3
    /// Positions inside `farms::stake`: the farm itself, and its share vault.
    static let farmsStakeFarmPosition = 2
    static let farmsStakeFarmVaultPosition = 3
    /// The injected payloads carry the limit then the price, ahead of everything
    /// the API built.
    static let computeUnitLimitIndex = 0
    static let computeUnitPriceIndex = 1

    /// A writable account belonging to the vault, not to the user — the shape an
    /// attacker's account would have if it were substituted in.
    static let foreignWritableIndex: UInt8 = 13
    static let foreignWritableAddress = "CKTEDx5z19CntAB9B66AxuS98S1NuCgMvfpsew7TQwi"
    static let solForeignWritableIndex: UInt8 = 5
    static let solForeignWritableAddress = "HqMuhd4cKWNFbLHc7zMZrThnh1cP39JwqczdBueK1bxj"

    static let withdrawUserTokenAccountIndex: UInt8 = 1
    /// `foreignWritableIndex` as it reads in the withdraw vector after a static
    /// key has been appended, which shifts every lookup-derived index by one.
    static let withdrawForeignWritableIndex: UInt8 = foreignWritableIndex + 1

    static let steakhouseFarm = "9FVjHqduhDPMVqvu3cXiEBjU6nvxvGdCCLRwd9WpVRZj"
    static let steakhouseFarmVault = "CRsf9nPkGBUT1HDytxfoYe3PBa5CZc9Nsh9a5aoBbGnb"
    static let allezFarm = "H6kauPaHmNqpdKtD5U2zw3Eb28ZB7iMeBdHVfLq1i4Kh"

    static let attackerKey = [UInt8](repeating: 0x11, count: 32)
    static var attackerAddress: String { Base58.encodeNoCheck(data: Data(attackerKey)) }

    static var tokenProgramKey: [UInt8] {
        guard let data = Base58.decodeNoCheck(string: SolanaTokenProgram.token.rawValue) else { return [] }
        return [UInt8](data)
    }

    static var farmsProgramKey: [UInt8] {
        guard let data = Base58.decodeNoCheck(string: KaminoVaultRegistry.farmsProgramId) else { return [] }
        return [UInt8](data)
    }

    /// A plausible farm unstake, derived rather than pinned: `unstake` is the
    /// counterpart of the `stake` this app already decodes, and its Anchor
    /// discriminator is `sha256("global:unstake")[0..<8]`. Computed here, in a
    /// test, precisely because the real instruction has never been observed —
    /// nothing in production asserts against it.
    static var farmsUnstakeData: [UInt8] {
        let digest = Hash.sha256(data: Data("global:unstake".utf8))
        return [UInt8](digest.prefix(8)) + littleEndian(1_000_000)
    }

    static let steakhouseTokensPerShare = KaminoRate(apiString: "1.0536041812651029025") ?? KaminoRate(apiString: "1")!

    static let usdcDepositAmount = KaminoTokenAmount(baseUnits: BigInt(10_000_000), decimals: 6)
    static let solDepositAmount = KaminoTokenAmount(baseUnits: BigInt(500_000_000), decimals: 9)
    static let usdcWithdrawShares = KaminoShareAmount(baseUnits: BigInt(5_500_000), decimals: 6)

    static var steakhouseVault: KaminoVaultInfo {
        vaultInfo(descriptor: KaminoVaultRegistry.steakhouseUSDC, lookupTable: KaminoTransactionFixtures.usdcDeposit.lookupTable)
    }

    static var allezVault: KaminoVaultInfo {
        vaultInfo(descriptor: KaminoVaultRegistry.allezSOL, lookupTable: KaminoTransactionFixtures.solDeposit.lookupTable)
    }

    /// Only the live fields are supplied here — the mints, their decimals and the
    /// farm come from the registry, which is the point of pinning them.
    static func vaultInfo(descriptor: KaminoVaultDescriptor, lookupTable: String) -> KaminoVaultInfo {
        KaminoVaultInfo(
            descriptor: descriptor,
            name: descriptor.fallbackName,
            minDeposit: KaminoTokenAmount(baseUnits: BigInt(100_000), decimals: descriptor.tokenDecimals),
            minWithdraw: KaminoShareAmount(baseUnits: BigInt(1_000), decimals: descriptor.sharesDecimals),
            lookupTable: lookupTable,
            apy30d: Decimal(string: "0.0391") ?? .zero,
            tokensPerShare: steakhouseTokensPerShare,
            tokenPriceUsd: 1
        )
    }

    static var usdcDepositIntent: KaminoTransactionIntent {
        KaminoTransactionIntent(operation: .deposit(usdcDepositAmount), vault: steakhouseVault, owner: depositOwner)
    }

    static var solDepositIntent: KaminoTransactionIntent {
        KaminoTransactionIntent(operation: .deposit(solDepositAmount), vault: allezVault, owner: depositOwner)
    }

    static var usdcWithdrawIntent: KaminoTransactionIntent {
        KaminoTransactionIntent(operation: .withdraw(usdcWithdrawShares), vault: steakhouseVault, owner: withdrawOwner)
    }
}

// MARK: - Intent editing

private extension KaminoTransactionIntent {

    func replacing(operation: KaminoOperation) -> KaminoTransactionIntent {
        KaminoTransactionIntent(operation: operation, vault: vault, owner: owner, priorityFee: priorityFee)
    }

    func replacing(owner: String) -> KaminoTransactionIntent {
        KaminoTransactionIntent(operation: operation, vault: vault, owner: owner, priorityFee: priorityFee)
    }

    func replacing(priorityFee: KaminoPriorityFee?) -> KaminoTransactionIntent {
        KaminoTransactionIntent(operation: operation, vault: vault, owner: owner, priorityFee: priorityFee)
    }

    func replacing(descriptor: KaminoVaultDescriptor) -> KaminoTransactionIntent {
        KaminoTransactionIntent(
            operation: operation,
            vault: vault.replacing(descriptor: descriptor),
            owner: owner,
            priorityFee: priorityFee
        )
    }

    func replacing(farm: String?) -> KaminoTransactionIntent {
        replacing(descriptor: vault.descriptor.replacing(farm: farm))
    }
}

private extension KaminoVaultDescriptor {

    func replacing(farm: String?) -> KaminoVaultDescriptor {
        KaminoVaultDescriptor(
            address: address,
            tokenMint: tokenMint,
            tokenDecimals: tokenDecimals,
            sharesMint: sharesMint,
            sharesDecimals: sharesDecimals,
            farm: farm,
            fallbackName: fallbackName,
            curator: curator,
            riskTier: riskTier
        )
    }
}

private extension KaminoVaultInfo {

    func replacing(descriptor: KaminoVaultDescriptor) -> KaminoVaultInfo {
        KaminoVaultInfo(
            descriptor: descriptor,
            name: name,
            minDeposit: minDeposit,
            minWithdraw: minWithdraw,
            lookupTable: lookupTable,
            apy30d: apy30d,
            tokensPerShare: tokensPerShare,
            tokenPriceUsd: tokenPriceUsd
        )
    }
}

// MARK: - Test doubles

private struct StubLookupTables: SolanaAddressLookupTableFetching {
    let tables: [String: [String]]
    var fails = false

    func fetchAddressLookupTables(addresses: [String]) async throws -> [String: [String]] {
        // A real fetch suspends; yielding keeps the stub from resolving
        // synchronously and hiding an ordering bug in the caller.
        await Task.yield()
        if fails, let first = addresses.first {
            throw SolanaAddressLookupTableError.accountNotFound(first)
        }
        return tables
    }
}

// MARK: - Mutation

/// A decoded v0 transaction that can be edited and re-serialized.
///
/// `SolanaV0Transaction` deliberately offers only the two edits production needs,
/// so the adversarial cases build their bytes here instead. Round-tripping an
/// untouched transaction is asserted byte-for-byte above, which is what makes a
/// refusal in these tests attributable to the mutation rather than to the rebuild.
/// A decoded v0 message that can be edited and re-serialized.
///
/// Internal rather than file-private: the verify-screen suite drives the same
/// "take bytes known to execute, change exactly one thing" pattern against the
/// decoder, and two copies of a serializer would let the two suites disagree
/// about what a malformed transaction even is.
struct MutableTransaction {

    struct Instruction {
        var programIdIndex: UInt8
        var accounts: [UInt8]
        var data: [UInt8]
    }

    struct Lookup {
        var table: [UInt8]
        var writable: [UInt8]
        var readonly: [UInt8]
    }

    var numRequiredSignatures: UInt8
    var numReadonlySignedAccounts: UInt8
    var numReadonlyUnsignedAccounts: UInt8
    var keys: [[UInt8]]
    var blockhash: [UInt8]
    var instructions: [Instruction]
    var lookups: [Lookup]

    init(base64: String) throws {
        let transaction = try SolanaV0Transaction(base64Transaction: base64)
        guard let blockhash = Base58.decodeNoCheck(string: transaction.recentBlockhash) else {
            throw SolanaV0TransactionError.invalidBlockhash
        }
        self.numRequiredSignatures = transaction.numRequiredSignatures
        self.numReadonlySignedAccounts = transaction.numReadonlySignedAccounts
        self.numReadonlyUnsignedAccounts = transaction.numReadonlyUnsignedAccounts
        self.keys = transaction.staticAccountKeys
        self.blockhash = [UInt8](blockhash)
        self.instructions = transaction.instructions.map {
            Instruction(programIdIndex: $0.programIdIndex, accounts: $0.accountIndexes, data: $0.data)
        }
        self.lookups = transaction.addressTableLookups.map {
            Lookup(table: $0.tableKey, writable: $0.writableIndexes, readonly: $0.readonlyIndexes)
        }
    }

    /// Appends a static read-only unsigned key, shifting every account index that
    /// addressed a lookup-loaded account. This is the same insertion the compute
    /// budget injection performs, reused so a Token instruction can be added to a
    /// transaction whose token program only exists inside a lookup table.
    ///
    /// - Returns: the new key's index.
    mutating func appendStaticReadonlyKey(_ key: [UInt8]) -> UInt8 {
        let oldStaticCount = keys.count
        keys.append(key)
        numReadonlyUnsignedAccounts += 1
        instructions = instructions.map { instruction in
            var shifted = instruction
            shifted.accounts = instruction.accounts.map { Int($0) >= oldStaticCount ? $0 + 1 : $0 }
            return shifted
        }
        return UInt8(oldStaticCount)
    }

    func bytes() throws -> [UInt8] {
        var out = try SolanaV0Transaction.encodeCompactLength(Int(numRequiredSignatures))
        out += [UInt8](repeating: 0, count: 64 * Int(numRequiredSignatures))
        out += [0x80, numRequiredSignatures, numReadonlySignedAccounts, numReadonlyUnsignedAccounts]
        out += try SolanaV0Transaction.encodeCompactLength(keys.count)
        for key in keys { out += key }
        out += blockhash
        out += try SolanaV0Transaction.encodeCompactLength(instructions.count)
        for instruction in instructions {
            out.append(instruction.programIdIndex)
            out += try SolanaV0Transaction.encodeCompactLength(instruction.accounts.count)
            out += instruction.accounts
            out += try SolanaV0Transaction.encodeCompactLength(instruction.data.count)
            out += instruction.data
        }
        out += try SolanaV0Transaction.encodeCompactLength(lookups.count)
        for lookup in lookups {
            out += lookup.table
            out += try SolanaV0Transaction.encodeCompactLength(lookup.writable.count)
            out += lookup.writable
            out += try SolanaV0Transaction.encodeCompactLength(lookup.readonly.count)
            out += lookup.readonly
        }
        return out
    }

    func base64() throws -> String {
        Data(try bytes()).base64EncodedString()
    }
}
