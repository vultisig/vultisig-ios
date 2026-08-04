//
//  SolanaV0TransactionGoldenTests.swift
//  VultisigAppTests
//
//  The Swift ComputeBudget injection against transactions that are known to
//  execute: every `injected` fixture here was simulated on mainnet with
//  `err: null`, so a byte that differs is a byte that is wrong.
//
//  Byte equality alone would not be enough, though. The injection shifts account
//  indices, and an index is only a position — a transaction whose indices all
//  shifted consistently still parses, still re-serializes, and still names a
//  completely different set of accounts. So the load-bearing test resolves both
//  sides through the real address lookup tables and compares the account
//  *pubkeys*, together with their signer and writable privileges, that every
//  instruction actually receives.
//

@testable import VultisigApp
import BigInt
import XCTest

final class SolanaV0TransactionGoldenTests: XCTestCase {

    private let tables = KaminoTransactionFixtures.lookupTables

    // MARK: - Byte-level parity with the mainnet-verified vectors

    func testInjectingComputeBudgetReproducesTheVerifiedBytes() throws {
        for vector in KaminoTransactionFixtures.all {
            let source = try SolanaV0Transaction(base64Transaction: vector.source)

            let injected = try source.injectingComputeBudget(
                price: KaminoTransactionFixtures.unitPriceMicroLamports,
                limit: vector.unitLimit
            )

            XCTAssertEqual(injected.base64EncodedTransaction, vector.injected, vector.name)
        }
    }

    func testSourceVectorsCarryNoPriorityFee() throws {
        for vector in KaminoTransactionFixtures.all {
            let source = try SolanaV0Transaction(base64Transaction: vector.source)
            XCTAssertFalse(source.hasComputeBudgetInstruction, vector.name)
        }
    }

    func testInjectedVectorsStayInsideThePacketLimit() throws {
        for vector in KaminoTransactionFixtures.all {
            let injected = try SolanaV0Transaction(base64Transaction: vector.injected)
            XCTAssertLessThanOrEqual(injected.wireSize, SolanaV0Transaction.maxWireSize, vector.name)
            XCTAssertLessThanOrEqual(injected.totalAccountCount, SolanaV0Transaction.maxAccountCount, vector.name)
        }
    }

    // MARK: - Resolved-account equivalence

    /// The real assertion: after injection every original instruction still
    /// receives the same accounts, with the same privileges, as before.
    func testInjectionPreservesResolvedAccountsForEveryInstruction() throws {
        for vector in KaminoTransactionFixtures.all {
            let source = try SolanaV0Transaction(base64Transaction: vector.source)
            let injected = try source.injectingComputeBudget(
                price: KaminoTransactionFixtures.unitPriceMicroLamports,
                limit: vector.unitLimit
            )

            // The two ComputeBudget instructions are prepended, so instruction
            // `i` of the source is instruction `i + 2` of the result.
            XCTAssertEqual(injected.instructions.count, source.instructions.count + 2, vector.name)

            for position in source.instructions.indices {
                let before = try describe(source, instructionAt: position)
                let after = try describe(injected, instructionAt: position + 2)
                XCTAssertEqual(before, after, "\(vector.name): instruction \(position)")
            }
        }
    }

    /// The keys that were already static must keep their exact index, so the
    /// shift never touches an account that did not move.
    func testInjectionAppendsOnlyTheComputeBudgetKey() throws {
        for vector in KaminoTransactionFixtures.all {
            let source = try SolanaV0Transaction(base64Transaction: vector.source)
            let injected = try source.injectingComputeBudget(
                price: KaminoTransactionFixtures.unitPriceMicroLamports,
                limit: vector.unitLimit
            )

            XCTAssertEqual(
                injected.staticAccountAddresses,
                source.staticAccountAddresses + [SolanaV0Transaction.computeBudgetProgramId],
                vector.name
            )
            XCTAssertEqual(
                injected.numReadonlyUnsignedAccounts,
                source.numReadonlyUnsignedAccounts + 1,
                vector.name
            )
            XCTAssertEqual(injected.numRequiredSignatures, source.numRequiredSignatures, vector.name)
            XCTAssertEqual(injected.numReadonlySignedAccounts, source.numReadonlySignedAccounts, vector.name)
            XCTAssertEqual(injected.addressTableLookups, source.addressTableLookups, vector.name)
            XCTAssertEqual(injected.recentBlockhash, source.recentBlockhash, vector.name)
        }
    }

    /// The appended key must land in the read-only unsigned block. If it were
    /// treated as writable, the accounts either side of the boundary would be
    /// re-privileged even though their indices look untouched.
    func testInjectedComputeBudgetKeyIsReadOnlyAndUnsigned() throws {
        for vector in KaminoTransactionFixtures.all {
            let injected = try SolanaV0Transaction(base64Transaction: vector.injected)
            let index = injected.staticAccountKeys.count - 1

            XCTAssertEqual(injected.staticAccountAddresses[index], SolanaV0Transaction.computeBudgetProgramId)
            XCTAssertFalse(injected.isSigner(accountIndex: index), vector.name)
            XCTAssertFalse(injected.isWritable(accountIndex: index), vector.name)
        }
    }

    /// Independent of the injection: the lookup-table resolution itself has to be
    /// right, or the equivalence test above would compare two identically wrong
    /// answers. These are the accounts the Steakhouse USDC deposit really names.
    func testLookupResolutionNamesTheExpectedAccounts() throws {
        let vector = KaminoTransactionFixtures.usdcDeposit
        let source = try SolanaV0Transaction(base64Transaction: vector.source)

        let resolved = try source.resolvedAccountAddresses(lookupTables: tables)
        XCTAssertEqual(source.staticAccountKeys.count, 9)
        XCTAssertEqual(resolved.count, 27)
        XCTAssertEqual(resolved[0], vector.feePayer)

        // The vault the deposit pays into, reached through the lookup table.
        XCTAssertEqual(resolved[17], KaminoVaultRegistry.steakhouseUSDC.address)
        XCTAssertTrue(source.isWritable(accountIndex: 17))
        XCTAssertEqual(resolved[26], "TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA")
        XCTAssertFalse(source.isWritable(accountIndex: 26))

        // Instruction 0 creates the *shares* ATA, not the token one — the shares
        // mint is the fourth account of an Associated Token Program create.
        let createAta = try source.resolvedAccountAddresses(forInstructionAt: 0, lookupTables: tables)
        XCTAssertEqual(createAta[0], vector.feePayer)
        XCTAssertEqual(createAta[3], "7D8C5pDFxug58L9zkwK7bCiDg4kD4AygzbcZUmf5usHS")

        // The kvault deposit is invoked against the Kamino program with the vault
        // as its second account.
        let deposit = try source.resolvedAccountAddresses(forInstructionAt: 1, lookupTables: tables)
        XCTAssertEqual(
            source.staticAccountAddresses[Int(source.instructions[1].programIdIndex)],
            KaminoVaultRegistry.programId
        )
        XCTAssertEqual(deposit[0], vector.feePayer)
        XCTAssertEqual(deposit[1], KaminoVaultRegistry.steakhouseUSDC.address)
    }

    func testResolutionFailsClosedWithoutTheLookupTable() throws {
        let source = try SolanaV0Transaction(base64Transaction: KaminoTransactionFixtures.usdcDeposit.source)

        XCTAssertThrowsError(try source.resolvedAccountAddresses(lookupTables: [:])) { error in
            XCTAssertEqual(
                error as? SolanaV0TransactionError,
                .unknownLookupTable(KaminoTransactionFixtures.usdcDeposit.lookupTable)
            )
        }
    }

    func testResolutionFailsClosedOnATruncatedLookupTable() throws {
        let vector = KaminoTransactionFixtures.usdcDeposit
        let source = try SolanaV0Transaction(base64Transaction: vector.source)
        let truncated = [vector.lookupTable: Array(tables[vector.lookupTable]?.prefix(4) ?? [])]

        XCTAssertThrowsError(try source.resolvedAccountAddresses(lookupTables: truncated)) { error in
            guard case .lookupIndexOutOfRange(let table, _, let size)? = error as? SolanaV0TransactionError else {
                return XCTFail("expected lookupIndexOutOfRange, got \(error)")
            }
            XCTAssertEqual(table, vector.lookupTable)
            XCTAssertEqual(size, 4)
        }
    }

    // MARK: - ComputeBudget instruction contents

    func testInjectedInstructionsCarryTheRequestedLimitAndPrice() throws {
        for vector in KaminoTransactionFixtures.all {
            let injected = try SolanaV0Transaction(base64Transaction: vector.injected)

            let limitInstruction = injected.instructions[0]
            let priceInstruction = injected.instructions[1]
            let programIndex = Int(limitInstruction.programIdIndex)

            XCTAssertEqual(
                injected.staticAccountAddresses[programIndex],
                SolanaV0Transaction.computeBudgetProgramId,
                vector.name
            )
            XCTAssertTrue(limitInstruction.accountIndexes.isEmpty, vector.name)
            XCTAssertTrue(priceInstruction.accountIndexes.isEmpty, vector.name)

            XCTAssertEqual(limitInstruction.data.first, ComputeBudgetInstruction.setUnitLimit, vector.name)
            XCTAssertEqual(littleEndianUInt32(limitInstruction.data.dropFirst()), vector.unitLimit, vector.name)

            XCTAssertEqual(priceInstruction.data.first, ComputeBudgetInstruction.setUnitPrice, vector.name)
            XCTAssertEqual(
                littleEndianUInt64(priceInstruction.data.dropFirst()),
                KaminoTransactionFixtures.unitPriceMicroLamports,
                vector.name
            )
        }
    }

    /// The limits the app ships must clear what the transactions were measured to
    /// consume, and must not be the 100,000 CU transfer constant.
    func testKaminoUnitLimitsClearMeasuredUsage() {
        XCTAssertGreaterThan(KaminoComputeBudget.tokenDepositUnitLimit, 252_146)
        XCTAssertGreaterThan(KaminoComputeBudget.nativeDepositUnitLimit, 287_029)
        XCTAssertGreaterThan(KaminoComputeBudget.withdrawUnitLimit, 174_566)

        // `SolanaHelper.priorityFeeLimit` is the transfer-path constant; every
        // Kamino limit has to sit above it, or the transaction aborts on compute
        // exhaustion before it does anything.
        for limit in [
            KaminoComputeBudget.tokenDepositUnitLimit,
            KaminoComputeBudget.nativeDepositUnitLimit,
            KaminoComputeBudget.withdrawUnitLimit
        ] {
            XCTAssertGreaterThan(BigInt(limit), SolanaHelper.priorityFeeLimit)
            XCTAssertLessThanOrEqual(limit, SolanaV0Transaction.maxComputeUnitLimit)
        }
    }

    // MARK: - Blockhash splice

    func testBlockhashSpliceTouchesOnlyTheBlockhashBytes() throws {
        let vector = KaminoTransactionFixtures.usdcDeposit
        let source = try SolanaV0Transaction(base64Transaction: vector.source)
        let fresh = KaminoTransactionFixtures.usdcWithdraw
        let freshBlockhash = try SolanaV0Transaction(base64Transaction: fresh.source).recentBlockhash

        let spliced = try source.replacingBlockhash(freshBlockhash)

        XCTAssertEqual(spliced.recentBlockhash, freshBlockhash)
        XCTAssertNotEqual(source.recentBlockhash, freshBlockhash)
        XCTAssertEqual(spliced.wireSize, source.wireSize)
        XCTAssertEqual(spliced.blockhashRange, source.blockhashRange)

        let before = try XCTUnwrap(Data(base64Encoded: source.base64EncodedTransaction))
        let after = try XCTUnwrap(Data(base64Encoded: spliced.base64EncodedTransaction))
        let differing = zip(before, after).enumerated().filter { $0.element.0 != $0.element.1 }.map(\.offset)
        XCTAssertFalse(differing.isEmpty)
        XCTAssertTrue(Set(differing).isSubset(of: Set(source.blockhashRange)))
    }

    /// Splicing and injecting have to commute: the pre-keysign blockhash refresh
    /// runs after the transaction is built, but a re-simulation may happen either
    /// side of it.
    func testSpliceAndInjectionCommute() throws {
        let fresh = try SolanaV0Transaction(base64Transaction: KaminoTransactionFixtures.usdcWithdraw.source)
            .recentBlockhash

        for vector in KaminoTransactionFixtures.all {
            let source = try SolanaV0Transaction(base64Transaction: vector.source)

            let injectFirst = try source
                .injectingComputeBudget(price: KaminoTransactionFixtures.unitPriceMicroLamports, limit: vector.unitLimit)
                .replacingBlockhash(fresh)
            let spliceFirst = try source
                .replacingBlockhash(fresh)
                .injectingComputeBudget(price: KaminoTransactionFixtures.unitPriceMicroLamports, limit: vector.unitLimit)

            XCTAssertEqual(injectFirst.base64EncodedTransaction, spliceFirst.base64EncodedTransaction, vector.name)
        }
    }

    func testInjectingTwiceIsRefused() throws {
        for vector in KaminoTransactionFixtures.all {
            let injected = try SolanaV0Transaction(base64Transaction: vector.injected)

            XCTAssertThrowsError(
                try injected.injectingComputeBudget(
                    price: KaminoTransactionFixtures.unitPriceMicroLamports,
                    limit: vector.unitLimit
                )
            ) { error in
                XCTAssertEqual(error as? SolanaV0TransactionError, .computeBudgetAlreadyPresent, vector.name)
            }
        }
    }

    // MARK: - Fee payer

    func testGoldenVectorsAreUnsignedSingleSignerTransactionsForTheirOwner() throws {
        for vector in KaminoTransactionFixtures.all {
            let source = try SolanaV0Transaction(base64Transaction: vector.source)
            XCTAssertEqual(source.feePayer, vector.feePayer, vector.name)
            XCTAssertNoThrow(try source.validateUnsignedSingleSigner(feePayer: vector.feePayer), vector.name)
        }
    }

    func testFeePayerGuardRejectsAnotherWallet() throws {
        let vector = KaminoTransactionFixtures.usdcDeposit
        let source = try SolanaV0Transaction(base64Transaction: vector.source)
        let other = KaminoTransactionFixtures.usdcWithdraw.feePayer

        XCTAssertThrowsError(try source.validateUnsignedSingleSigner(feePayer: other)) { error in
            XCTAssertEqual(
                error as? SolanaV0TransactionError,
                .feePayerMismatch(expected: other, actual: vector.feePayer)
            )
        }
    }

    // MARK: - Helpers

    /// Everything an instruction actually does, in resolved terms: which program
    /// runs, which accounts it receives with which privileges, and its data.
    private func describe(
        _ transaction: SolanaV0Transaction,
        instructionAt position: Int
    ) throws -> String {
        let instruction = transaction.instructions[position]
        let resolved = try transaction.resolvedAccountAddresses(
            forInstructionAt: position,
            lookupTables: tables
        )
        let program = transaction.staticAccountAddresses[Int(instruction.programIdIndex)]
        let accounts = zip(instruction.accountIndexes, resolved).map { index, address in
            let signer = transaction.isSigner(accountIndex: Int(index)) ? "s" : "-"
            let writable = transaction.isWritable(accountIndex: Int(index)) ? "w" : "r"
            return "\(address)/\(signer)\(writable)"
        }
        let data = instruction.data.map { String(format: "%02x", $0) }.joined()
        return "\(program)(\(accounts.joined(separator: ","))) data=\(data)"
    }

    private func littleEndianUInt32(_ bytes: ArraySlice<UInt8>) -> UInt32? {
        guard bytes.count == 4 else { return nil }
        return bytes.reversed().reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
    }

    private func littleEndianUInt64(_ bytes: ArraySlice<UInt8>) -> UInt64? {
        guard bytes.count == 8 else { return nil }
        return bytes.reversed().reduce(UInt64(0)) { ($0 << 8) | UInt64($1) }
    }
}
