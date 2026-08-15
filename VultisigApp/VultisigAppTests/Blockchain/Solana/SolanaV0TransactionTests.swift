//
//  SolanaV0TransactionTests.swift
//  VultisigAppTests
//
//  The structural guards on `SolanaV0Transaction`. These matter more than usual:
//  the bytes this type parses come from a third party and are signed verbatim, so
//  anything it tolerates is something the app is willing to sign without
//  understanding.
//

@testable import VultisigApp
import WalletCore
import XCTest

final class SolanaV0TransactionTests: XCTestCase {

    // MARK: - Well-formed baseline

    func testParsesAMinimalVersionedTransaction() throws {
        let transaction = try SolanaV0Transaction(wireBytes: try Builder().bytes())

        XCTAssertEqual(transaction.numRequiredSignatures, 1)
        XCTAssertEqual(transaction.numReadonlySignedAccounts, 0)
        XCTAssertEqual(transaction.numReadonlyUnsignedAccounts, 1)
        XCTAssertEqual(transaction.staticAccountKeys.count, 2)
        XCTAssertEqual(transaction.instructions.count, 1)
        XCTAssertEqual(transaction.totalAccountCount, 2)
        XCTAssertEqual(transaction.signaturesRange, 1..<65)
        XCTAssertEqual(transaction.messageOffset, 65)
        XCTAssertNoThrow(try transaction.validateUnsignedSingleSigner(feePayer: transaction.feePayer))
    }

    func testRoundTripsThroughBase64() throws {
        let bytes = try Builder().bytes()
        let transaction = try SolanaV0Transaction(base64Transaction: Data(bytes).base64EncodedString())
        XCTAssertEqual(transaction.wireSize, bytes.count)
    }

    // MARK: - Parse guards

    func testRejectsInvalidBase64() throws {
        XCTAssertThrowsError(try SolanaV0Transaction(base64Transaction: "not base64 !!")) { error in
            XCTAssertEqual(error as? SolanaV0TransactionError, .invalidBase64)
        }
    }

    /// A legacy message has no version byte; its first byte is
    /// `numRequiredSignatures`, which never has the high bit set. Accepting one
    /// would mean reading the header at the wrong offset.
    func testRejectsLegacyMessage() throws {
        var builder = Builder()
        builder.versionByte = nil

        XCTAssertThrowsError(try SolanaV0Transaction(wireBytes: try builder.bytes())) { error in
            XCTAssertEqual(error as? SolanaV0TransactionError, .legacyMessageUnsupported)
        }
    }

    func testRejectsAFutureMessageVersion() throws {
        var builder = Builder()
        builder.versionByte = 0x81

        XCTAssertThrowsError(try SolanaV0Transaction(wireBytes: try builder.bytes())) { error in
            XCTAssertEqual(error as? SolanaV0TransactionError, .unsupportedMessageVersion(1))
        }
    }

    func testRejectsTrailingBytes() throws {
        var builder = Builder()
        builder.trailing = [0x00]

        XCTAssertThrowsError(try SolanaV0Transaction(wireBytes: try builder.bytes())) { error in
            XCTAssertEqual(error as? SolanaV0TransactionError, .trailingBytes(1))
        }
    }

    func testRejectsTruncatedInput() throws {
        let bytes = try Builder().bytes()

        XCTAssertThrowsError(try SolanaV0Transaction(wireBytes: Array(bytes.dropLast(3)))) { error in
            guard case .truncated? = error as? SolanaV0TransactionError else {
                return XCTFail("expected truncated, got \(error)")
            }
        }
    }

    /// `0x81 0x00` and `0x01` both decode to 1. Accepting the padded form would
    /// mean two different byte strings describe the same transaction — and the
    /// app hashes bytes, not the decoded structure, so a co-signer given the
    /// other form would produce a different pre-image.
    func testRejectsNonCanonicalLengthPrefix() throws {
        var builder = Builder()
        builder.keyCountPrefix = [0x81, 0x00]

        XCTAssertThrowsError(try SolanaV0Transaction(wireBytes: try builder.bytes())) { error in
            XCTAssertEqual(error as? SolanaV0TransactionError, .malformedLengthPrefix)
        }
    }

    /// Two signature slots for a header that requires one. Solana derives the
    /// number of slots from the header, so the extra slot would shift where the
    /// signature splice writes.
    func testRejectsSignatureCountThatDisagreesWithTheHeader() throws {
        var builder = Builder()
        builder.encodedSignatureCount = 2
        builder.signatureBytes = Array(repeating: 0, count: 128)

        XCTAssertThrowsError(try SolanaV0Transaction(wireBytes: try builder.bytes())) { error in
            XCTAssertEqual(
                error as? SolanaV0TransactionError,
                .signatureCountMismatch(header: 1, encoded: 2)
            )
        }
    }

    /// The read-only signer block can never cover every signer: the fee payer is
    /// signer 0 and has to be writable.
    func testRejectsHeaderWithNoWritableSigner() throws {
        var builder = Builder()
        builder.header = [1, 1, 1]

        XCTAssertThrowsError(try SolanaV0Transaction(wireBytes: try builder.bytes())) { error in
            XCTAssertEqual(error as? SolanaV0TransactionError, .malformedHeader)
        }
    }

    func testRejectsHeaderWithOverlappingSignerAndReadonlyBlocks() throws {
        var builder = Builder()
        builder.header = [1, 0, 2]

        XCTAssertThrowsError(try SolanaV0Transaction(wireBytes: try builder.bytes())) { error in
            XCTAssertEqual(error as? SolanaV0TransactionError, .malformedHeader)
        }
    }

    func testRejectsAnAccountIndexBeyondTheAccountSpace() throws {
        var builder = Builder()
        builder.instructions = [(programIdIndex: 1, accounts: [7], data: [9])]

        XCTAssertThrowsError(try SolanaV0Transaction(wireBytes: try builder.bytes())) { error in
            XCTAssertEqual(
                error as? SolanaV0TransactionError,
                .accountIndexOutOfRange(instruction: 0, index: 7, accountCount: 2)
            )
        }
    }

    /// A versioned message may not invoke a program loaded from a lookup table,
    /// which is precisely why the injection can leave `programIdIndex` alone.
    func testRejectsAProgramIdOutsideTheStaticKeys() throws {
        var builder = Builder()
        builder.lookups = [(table: Self.key(9), writable: [0], readonly: [])]
        builder.instructions = [(programIdIndex: 2, accounts: [0], data: [9])]

        XCTAssertThrowsError(try SolanaV0Transaction(wireBytes: try builder.bytes())) { error in
            XCTAssertEqual(error as? SolanaV0TransactionError, .programIdFromLookupTable(instruction: 0))
        }
    }

    /// Solana refuses to invoke the fee payer as a program, so a message that
    /// does is one we would have signed and the network would then drop.
    func testRejectsAnInstructionThatInvokesTheFeePayer() throws {
        var builder = Builder()
        builder.instructions = [(programIdIndex: 0, accounts: [1], data: [9])]

        XCTAssertThrowsError(try SolanaV0Transaction(wireBytes: try builder.bytes())) { error in
            XCTAssertEqual(error as? SolanaV0TransactionError, .programIdIsFeePayer(instruction: 0))
        }
    }

    func testRejectsALookupThatLoadsNothing() throws {
        var builder = Builder()
        builder.lookups = [(table: Self.key(9), writable: [], readonly: [])]

        XCTAssertThrowsError(try SolanaV0Transaction(wireBytes: try builder.bytes())) { error in
            XCTAssertEqual(error as? SolanaV0TransactionError, .emptyAddressTableLookup)
        }
    }

    func testRejectsATransactionAboveThePacketLimit() throws {
        XCTAssertThrowsError(
            try SolanaV0Transaction(wireBytes: Array(repeating: 0, count: 1233))
        ) { error in
            XCTAssertEqual(error as? SolanaV0TransactionError, .oversizedTransaction(1233))
        }
    }

    // MARK: - Signing preconditions

    func testRejectsATransactionThatIsAlreadySigned() throws {
        var builder = Builder()
        builder.signatureBytes = Array(repeating: 0xAB, count: 64)
        let transaction = try SolanaV0Transaction(wireBytes: try builder.bytes())

        XCTAssertThrowsError(
            try transaction.validateUnsignedSingleSigner(feePayer: transaction.feePayer)
        ) { error in
            XCTAssertEqual(error as? SolanaV0TransactionError, .signaturePlaceholderNotEmpty)
        }
    }

    func testRejectsAMultiSignerTransaction() throws {
        var builder = Builder()
        builder.header = [2, 0, 1]
        builder.encodedSignatureCount = 2
        builder.signatureBytes = Array(repeating: 0, count: 128)
        builder.keys = [Self.key(1), Self.key(2), Self.key(3)]
        let transaction = try SolanaV0Transaction(wireBytes: try builder.bytes())

        XCTAssertThrowsError(
            try transaction.validateUnsignedSingleSigner(feePayer: transaction.feePayer)
        ) { error in
            XCTAssertEqual(error as? SolanaV0TransactionError, .notSingleSigner(2))
        }
    }

    // MARK: - Blockhash

    func testReplacingBlockhashRejectsAWrongLengthValue() throws {
        let transaction = try SolanaV0Transaction(wireBytes: try Builder().bytes())
        let short = Base58.encodeNoCheck(data: Data(repeating: 3, count: 31))

        XCTAssertThrowsError(try transaction.replacingBlockhash(short)) { error in
            XCTAssertEqual(error as? SolanaV0TransactionError, .invalidBlockhash)
        }
    }

    func testReplacingBlockhashRejectsNonBase58() throws {
        let transaction = try SolanaV0Transaction(wireBytes: try Builder().bytes())

        XCTAssertThrowsError(try transaction.replacingBlockhash("0OIl-not-base58")) { error in
            XCTAssertEqual(error as? SolanaV0TransactionError, .invalidBlockhash)
        }
    }

    // MARK: - Compute budget

    func testInjectionRejectsAZeroUnitLimit() throws {
        let transaction = try SolanaV0Transaction(wireBytes: try Builder().bytes())

        XCTAssertThrowsError(try transaction.injectingComputeBudget(price: 1, limit: 0)) { error in
            XCTAssertEqual(error as? SolanaV0TransactionError, .computeUnitLimitOutOfRange(0))
        }
    }

    func testInjectionRejectsAUnitLimitAboveTheNetworkCeiling() throws {
        let transaction = try SolanaV0Transaction(wireBytes: try Builder().bytes())
        let limit = SolanaV0Transaction.maxComputeUnitLimit + 1

        XCTAssertThrowsError(try transaction.injectingComputeBudget(price: 1, limit: limit)) { error in
            XCTAssertEqual(error as? SolanaV0TransactionError, .computeUnitLimitOutOfRange(limit))
        }
    }

    /// A ComputeBudget key that is present but unused would still make the append
    /// a duplicate account key.
    func testInjectionRejectsATransactionThatAlreadyCarriesTheProgramKey() throws {
        var builder = Builder()
        builder.header = [1, 0, 2]
        builder.keys = [Self.key(1), Self.key(2), SolanaV0Transaction.computeBudgetProgramKey]
        let transaction = try SolanaV0Transaction(wireBytes: try builder.bytes())

        XCTAssertThrowsError(try transaction.injectingComputeBudget(price: 1, limit: 1000)) { error in
            XCTAssertEqual(error as? SolanaV0TransactionError, .computeBudgetAlreadyPresent)
        }
    }

    func testInjectionRefusesWhenTheAccountSpaceIsFull() throws {
        // Two static keys plus 254 lookup-loaded ones is exactly the 256 an 8-bit
        // index can address; a 257th account could not be referenced at all.
        var builder = Builder()
        builder.lookups = [(
            table: Self.key(255),
            writable: (0..<127).map { UInt8($0) },
            readonly: (0..<127).map { UInt8($0) }
        )]
        let transaction = try SolanaV0Transaction(wireBytes: try builder.bytes())
        XCTAssertEqual(transaction.totalAccountCount, 256)

        XCTAssertThrowsError(try transaction.injectingComputeBudget(price: 1, limit: 1000)) { error in
            XCTAssertEqual(error as? SolanaV0TransactionError, .tooManyAccounts(257))
        }
    }

    /// The synthetic path: a transaction with no lookup tables at all still has
    /// to come out right, since nothing then needs shifting.
    func testInjectionWithoutLookupTablesShiftsNothing() throws {
        let transaction = try SolanaV0Transaction(wireBytes: try Builder().bytes())

        let injected = try transaction.injectingComputeBudget(price: 7, limit: 1234)

        XCTAssertEqual(injected.instructions.count, 3)
        XCTAssertEqual(injected.instructions[2].accountIndexes, transaction.instructions[0].accountIndexes)
        XCTAssertEqual(injected.instructions[2].programIdIndex, transaction.instructions[0].programIdIndex)
        XCTAssertEqual(injected.staticAccountKeys.count, transaction.staticAccountKeys.count + 1)
        XCTAssertEqual(injected.numReadonlyUnsignedAccounts, transaction.numReadonlyUnsignedAccounts + 1)
    }

    // MARK: - Multiple address lookup tables

    /// Two tables, each contributing writable and read-only entries. The runtime
    /// concatenates every table's writable accounts first and only then every
    /// table's read-only ones, so with more than one table the loaded accounts do
    /// not appear table by table — a resolver that walked them in table order
    /// would name the wrong account for the same index, silently.
    func testResolutionInterleavesMultipleLookupTablesWritableFirst() throws {
        let transaction = try SolanaV0Transaction(wireBytes: try Self.twoTableBuilder().bytes())

        let resolved = try transaction.resolvedAccountAddresses(lookupTables: Self.twoTables)

        XCTAssertEqual(resolved.count, 8)
        XCTAssertEqual(Array(resolved[0..<2]), transaction.staticAccountAddresses)
        XCTAssertEqual(
            Array(resolved[2...]),
            ["A-w0", "A-w1", "B-w0", "B-w1", "A-r0", "B-r0"]
        )
        // Writability is positional, so the boundary between the two blocks has
        // to fall in the right place.
        XCTAssertTrue((2..<6).allSatisfy { transaction.isWritable(accountIndex: $0) })
        XCTAssertFalse((6..<8).contains { transaction.isWritable(accountIndex: $0) })
    }

    func testInjectionPreservesResolvedAccountsAcrossMultipleLookupTables() throws {
        let source = try SolanaV0Transaction(wireBytes: try Self.twoTableBuilder().bytes())
        let injected = try source.injectingComputeBudget(price: 20_000, limit: 200_000)

        let before = try source.resolvedAccountAddresses(forInstructionAt: 0, lookupTables: Self.twoTables)
        let after = try injected.resolvedAccountAddresses(forInstructionAt: 2, lookupTables: Self.twoTables)

        XCTAssertEqual(before, after)
        XCTAssertEqual(before.count, 8)
        // Every lookup-derived index moved by exactly one; the static ones did not.
        XCTAssertEqual(source.instructions[0].accountIndexes, [0, 1, 2, 3, 4, 5, 6, 7])
        XCTAssertEqual(injected.instructions[2].accountIndexes, [0, 1, 3, 4, 5, 6, 7, 8])
        XCTAssertEqual(injected.addressTableLookups, source.addressTableLookups)

        // Index 2 of the result is the newly appended ComputeBudget key; every
        // other account keeps the privileges it had.
        let privilegesBefore = (0..<8).map { Self.privilege(source, at: $0) }
        let privilegesAfter = (0..<9).filter { $0 != 2 }.map { Self.privilege(injected, at: $0) }
        XCTAssertEqual(privilegesBefore, privilegesAfter)
    }

    // MARK: - Encoding primitives

    func testCompactLengthUsesTheShortestEncoding() throws {
        XCTAssertEqual(try SolanaV0Transaction.encodeCompactLength(0), [0x00])
        XCTAssertEqual(try SolanaV0Transaction.encodeCompactLength(127), [0x7F])
        XCTAssertEqual(try SolanaV0Transaction.encodeCompactLength(128), [0x80, 0x01])
        XCTAssertEqual(try SolanaV0Transaction.encodeCompactLength(16_383), [0xFF, 0x7F])
        XCTAssertEqual(try SolanaV0Transaction.encodeCompactLength(16_384), [0x80, 0x80, 0x01])
        XCTAssertEqual(try SolanaV0Transaction.encodeCompactLength(65_535), [0xFF, 0xFF, 0x03])
    }

    /// Values compact-u16 cannot express have no encoding, so emitting one would
    /// mean writing a length that silently means something else. A negative value
    /// would also never terminate a shift loop.
    func testCompactLengthRefusesValuesOutsideItsDomain() {
        for value in [-1, 65_536, Int.max] {
            XCTAssertThrowsError(try SolanaV0Transaction.encodeCompactLength(value)) { error in
                XCTAssertEqual(error as? SolanaV0TransactionError, .malformedLengthPrefix)
            }
        }
    }

    /// Every value round-trips, including the three-byte encodings whose leading
    /// bytes carry no value bits at all — `80 80 01` is the *only* encoding of
    /// 16,384, so rejecting it as padded would reject a canonical length.
    func testCompactLengthRoundTripsAcrossTheWholeDomain() throws {
        for value in 0...SolanaV0Transaction.maxCompactLength {
            let encoded = try SolanaV0Transaction.encodeCompactLength(value)
            let decoded = try SolanaV0Transaction.decodeCompactLength(encoded[...])
            XCTAssertEqual(decoded.value, value)
            XCTAssertEqual(decoded.byteCount, encoded.count)
        }
    }

    func testCompactLengthRejectsPaddedEncodings() {
        // `81 00` and `01` both mean 1; `80 80 80 …` never terminates.
        for encoding: [UInt8] in [[0x81, 0x00], [0x80, 0x00], [0x81, 0x80, 0x00], [0x80, 0x80, 0x80]] {
            XCTAssertThrowsError(try SolanaV0Transaction.decodeCompactLength(encoding[...])) { error in
                XCTAssertEqual(error as? SolanaV0TransactionError, .malformedLengthPrefix, "\(encoding)")
            }
        }
    }

    func testCompactLengthReportsTruncationSeparatelyFromMalformedInput() {
        XCTAssertThrowsError(try SolanaV0Transaction.decodeCompactLength([0x80][...])) { error in
            guard case .truncated? = error as? SolanaV0TransactionError else {
                return XCTFail("expected truncated, got \(error)")
            }
        }
    }

    func testComputeBudgetProgramKeyIsTheDecodedProgramId() {
        XCTAssertEqual(SolanaV0Transaction.computeBudgetProgramKey.count, 32)
        XCTAssertEqual(
            Base58.encodeNoCheck(data: Data(SolanaV0Transaction.computeBudgetProgramKey)),
            SolanaV0Transaction.computeBudgetProgramId
        )
    }

    func testMemoProgramKeyIsTheDecodedProgramId() {
        XCTAssertEqual(SolanaV0Transaction.memoProgramKey.count, 32)
        XCTAssertEqual(
            Base58.encodeNoCheck(data: Data(SolanaV0Transaction.memoProgramKey)),
            SolanaV0Transaction.memoProgramId
        )
    }

    // MARK: - Memo injection

    /// The memo goes on the END, carries its text verbatim and attests to
    /// nobody. Position matters as much as content: everything ahead of it keeps
    /// the index it already had, which is what lets the shared instruction
    /// template describe the tagged transaction by appending one step.
    func testMemoInjectionAppendsOneAccountlessInstructionCarryingTheText() throws {
        let transaction = try SolanaV0Transaction(wireBytes: try Builder().bytes())

        let tagged = try transaction.injectingMemo("8k2mz")

        XCTAssertEqual(tagged.instructions.count, transaction.instructions.count + 1)
        let memo = try XCTUnwrap(tagged.instructions.last)
        XCTAssertEqual(memo.data, [UInt8]("8k2mz".utf8))
        XCTAssertTrue(memo.accountIndexes.isEmpty)
        XCTAssertEqual(tagged.staticAccountKeys[Int(memo.programIdIndex)], SolanaV0Transaction.memoProgramKey)
        // Appended to the read-only unsigned block, exactly like the budget key.
        XCTAssertEqual(tagged.staticAccountKeys.count, transaction.staticAccountKeys.count + 1)
        XCTAssertEqual(tagged.numReadonlyUnsignedAccounts, transaction.numReadonlyUnsignedAccounts + 1)
        // And the instruction that was already there is untouched.
        XCTAssertEqual(tagged.instructions[0], transaction.instructions[0])
    }

    /// The whole point of the injection is that it does not disturb which
    /// account any existing instruction addresses — the lookup-loaded ones move
    /// one slot later, and their indexes have to move with them.
    func testMemoInjectionPreservesResolvedAccountsAcrossMultipleLookupTables() throws {
        let source = try SolanaV0Transaction(wireBytes: try Self.twoTableBuilder().bytes())
        let tagged = try source.injectingMemo("8k2mz")

        let before = try source.resolvedAccountAddresses(forInstructionAt: 0, lookupTables: Self.twoTables)
        let after = try tagged.resolvedAccountAddresses(forInstructionAt: 0, lookupTables: Self.twoTables)

        XCTAssertEqual(before, after)
    }

    /// Both injections on one transaction: the budget pair in front, the memo
    /// behind, and the original instruction between them still addressing the
    /// same accounts after being shifted twice.
    func testBudgetAndMemoComposeWithoutDisturbingTheOriginalInstruction() throws {
        let source = try SolanaV0Transaction(wireBytes: try Self.twoTableBuilder().bytes())

        let both = try source
            .injectingComputeBudget(price: 20_000, limit: 200_000)
            .injectingMemo("8k2mz")

        XCTAssertEqual(both.instructions.count, source.instructions.count + 3)
        XCTAssertEqual(both.instructions.last?.data, [UInt8]("8k2mz".utf8))
        XCTAssertEqual(
            try source.resolvedAccountAddresses(forInstructionAt: 0, lookupTables: Self.twoTables),
            try both.resolvedAccountAddresses(forInstructionAt: 2, lookupTables: Self.twoTables)
        )
    }

    func testASecondMemoIsRefused() throws {
        let tagged = try SolanaV0Transaction(wireBytes: try Builder().bytes()).injectingMemo("8k2mz")

        XCTAssertThrowsError(try tagged.injectingMemo("8k2mz")) { error in
            XCTAssertEqual(error as? SolanaV0TransactionError, .memoAlreadyPresent)
        }
    }

    func testAnEmptyOrOversizedMemoIsRefused() throws {
        let transaction = try SolanaV0Transaction(wireBytes: try Builder().bytes())

        XCTAssertThrowsError(try transaction.injectingMemo("")) { error in
            XCTAssertEqual(error as? SolanaV0TransactionError, .memoOutOfRange(0))
        }
        let oversized = String(repeating: "x", count: SolanaV0Transaction.maxMemoByteCount + 1)
        XCTAssertThrowsError(try transaction.injectingMemo(oversized)) { error in
            XCTAssertEqual(error as? SolanaV0TransactionError, .memoOutOfRange(oversized.utf8.count))
        }
    }

    // MARK: - Builder

    private static let tableAKey = key(200)
    private static let tableBKey = key(201)

    /// Two lookup tables that each load writable *and* read-only accounts, so the
    /// resolution order is only right if writables are gathered across all tables
    /// before any read-only one.
    private static let twoTables: [String: [String]] = [
        Base58.encodeNoCheck(data: Data(tableAKey)): ["A-w0", "A-w1", "A-r0"],
        Base58.encodeNoCheck(data: Data(tableBKey)): ["B-w0", "B-w1", "B-r0"]
    ]

    private static func twoTableBuilder() -> Builder {
        var builder = Builder()
        builder.lookups = [
            (table: tableAKey, writable: [0, 1], readonly: [2]),
            (table: tableBKey, writable: [0, 1], readonly: [2])
        ]
        builder.instructions = [(programIdIndex: 1, accounts: [0, 1, 2, 3, 4, 5, 6, 7], data: [9])]
        return builder
    }

    private static func privilege(_ transaction: SolanaV0Transaction, at index: Int) -> String {
        let signer = transaction.isSigner(accountIndex: index) ? "s" : "-"
        let writable = transaction.isWritable(accountIndex: index) ? "w" : "r"
        return signer + writable
    }

    private static func key(_ seed: UInt8) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: 32)
        bytes[31] = seed
        bytes[0] = seed &+ 1
        return bytes
    }

    /// Assembles a v0 transaction byte by byte so individual fields can be made
    /// invalid in isolation.
    private struct Builder {
        var encodedSignatureCount = 1
        var signatureBytes: [UInt8] = Array(repeating: 0, count: 64)
        var versionByte: UInt8? = 0x80
        var header: [UInt8] = [1, 0, 1]
        var keys: [[UInt8]] = [SolanaV0TransactionTests.key(1), SolanaV0TransactionTests.key(2)]
        var keyCountPrefix: [UInt8]?
        var blockhash: [UInt8] = Array(repeating: 7, count: 32)
        var instructions: [(programIdIndex: UInt8, accounts: [UInt8], data: [UInt8])] = [
            (programIdIndex: 1, accounts: [0], data: [9])
        ]
        var lookups: [(table: [UInt8], writable: [UInt8], readonly: [UInt8])] = []
        var trailing: [UInt8] = []

        func bytes() throws -> [UInt8] {
            var out = try SolanaV0Transaction.encodeCompactLength(encodedSignatureCount)
            out += signatureBytes
            if let versionByte { out.append(versionByte) }
            out += header
            out += try keyCountPrefix ?? SolanaV0Transaction.encodeCompactLength(keys.count)
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
            return out + trailing
        }
    }
}
