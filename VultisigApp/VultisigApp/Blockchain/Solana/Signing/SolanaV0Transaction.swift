//
//  SolanaV0Transaction.swift
//  VultisigApp
//

import Foundation
import WalletCore

/// Structural failures of a serialized Solana v0 transaction, and of the two
/// edits this type performs on one. Every case is a refusal to proceed — nothing
/// here degrades to a best-effort result, because the output is signed verbatim.
enum SolanaV0TransactionError: Error, LocalizedError, Equatable {
    case invalidBase64
    case truncated(needed: Int, available: Int)
    case trailingBytes(Int)
    case malformedLengthPrefix
    case legacyMessageUnsupported
    case unsupportedMessageVersion(Int)
    case malformedHeader
    case signatureCountMismatch(header: Int, encoded: Int)
    case notSingleSigner(Int)
    case signaturePlaceholderNotEmpty
    case feePayerMismatch(expected: String, actual: String)
    case invalidBlockhash
    case programIdFromLookupTable(instruction: Int)
    case programIdIsFeePayer(instruction: Int)
    case accountIndexOutOfRange(instruction: Int, index: Int, accountCount: Int)
    case emptyAddressTableLookup
    case tooManyAccounts(Int)
    case oversizedTransaction(Int)
    case computeBudgetAlreadyPresent
    case computeUnitLimitOutOfRange(UInt32)
    case memoAlreadyPresent
    case memoOutOfRange(Int)
    case unknownLookupTable(String)
    case lookupIndexOutOfRange(table: String, index: Int, tableSize: Int)

    var errorDescription: String? {
        switch self {
        case .invalidBase64:
            return "Transaction is not valid base64"
        case .truncated(let needed, let available):
            return "Transaction truncated: needed \(needed) more bytes, \(available) available"
        case .trailingBytes(let count):
            return "Transaction has \(count) unparsed trailing bytes"
        case .malformedLengthPrefix:
            return "Transaction contains a malformed compact-u16 length"
        case .legacyMessageUnsupported:
            return "Transaction uses a legacy message; only versioned (v0) messages are supported"
        case .unsupportedMessageVersion(let version):
            return "Unsupported message version \(version)"
        case .malformedHeader:
            return "Transaction message header is inconsistent with its account keys"
        case .signatureCountMismatch(let header, let encoded):
            return "Header requires \(header) signatures but \(encoded) signature slots are encoded"
        case .notSingleSigner(let count):
            return "Expected exactly one required signature, found \(count)"
        case .signaturePlaceholderNotEmpty:
            return "Transaction already carries a signature; expected an unsigned placeholder"
        case .feePayerMismatch(let expected, let actual):
            return "Transaction fee payer is \(actual), expected \(expected)"
        case .invalidBlockhash:
            return "Blockhash is not 32 bytes of base58"
        case .programIdFromLookupTable(let index):
            return "Instruction \(index) invokes a program that is not a static account key"
        case .programIdIsFeePayer(let index):
            return "Instruction \(index) invokes the fee payer as a program"
        case .accountIndexOutOfRange(let instruction, let index, let count):
            return "Instruction \(instruction) references account index \(index) of \(count)"
        case .emptyAddressTableLookup:
            return "Transaction contains an address lookup that loads no accounts"
        case .tooManyAccounts(let count):
            return "Transaction resolves \(count) accounts, above the 256 an 8-bit index can address"
        case .oversizedTransaction(let size):
            return "Transaction is \(size) bytes, above the 1232-byte packet limit"
        case .computeBudgetAlreadyPresent:
            return "Transaction already carries a Compute Budget instruction"
        case .computeUnitLimitOutOfRange(let limit):
            return "Compute unit limit \(limit) is outside the range the network accepts"
        case .memoAlreadyPresent:
            return "Transaction already carries a Memo instruction"
        case .memoOutOfRange(let count):
            return "Memo of \(count) bytes is outside the range this app injects"
        case .unknownLookupTable(let address):
            return "No contents supplied for address lookup table \(address)"
        case .lookupIndexOutOfRange(let table, let index, let size):
            return "Lookup table \(table) has \(size) addresses; index \(index) is out of range"
        }
    }
}

/// A span-indexed, byte-level view of a serialized Solana **v0 (versioned)**
/// transaction.
///
/// This exists because third-party-built Solana transactions are signed
/// *verbatim*: the bytes the builder returned are what
/// `SolanaHelper.getPreSignedImageHashForRaw` hashes, and every co-signer hashes
/// the same bytes independently. Feeding them through WalletCore's signing proto
/// and re-serializing produces a message that differs by a byte, which breaks
/// Secure Vault co-signing before any TSS message is emitted. So both edits here
/// work on the bytes directly: the blockhash is spliced in place, and the
/// ComputeBudget injection re-serializes the message field by field from the
/// values it parsed, leaving every other field byte-identical.
///
/// Parsing is deliberately strict — non-canonical length prefixes, trailing
/// bytes, out-of-range account indices and inconsistent headers are all refusals
/// rather than tolerated quirks.
struct SolanaV0Transaction: Equatable {

    /// Maximum size of a Solana transaction packet.
    static let maxWireSize = 1232
    /// An account index is a single byte, so 256 is the ceiling on static keys
    /// plus lookup-table-loaded keys combined.
    static let maxAccountCount = 256
    /// Network ceiling on a `SetComputeUnitLimit` request.
    static let maxComputeUnitLimit: UInt32 = 1_400_000

    static let computeBudgetProgramId = "ComputeBudget111111111111111111111111111111"

    /// SPL Memo v3. The program writes nothing and owns nothing; it logs its
    /// instruction data, which is what makes an on-chain attribution tag
    /// readable by an indexer without changing what the transaction does.
    static let memoProgramId = "MemoSq4gqABAXKb96qnH8TysNcWxMyWCqXgDLGmfcHr"

    /// Bound on an injected memo. Nothing here needs a long one — the tag this
    /// app writes is a handful of bytes — and the ceiling keeps a caller from
    /// spending the transaction's remaining size budget on a note.
    static let maxMemoByteCount = 64

    /// The 32 raw bytes of `computeBudgetProgramId`, decoded once. The input is
    /// a compile-time constant, so a decode failure would mean the base58
    /// decoder itself is broken rather than that the data is bad — hence the
    /// trap rather than a thrown error. `SolanaV0TransactionTests` pins the
    /// decoded bytes so the trap is unreachable in a passing build.
    static let computeBudgetProgramKey: [UInt8] = {
        guard let data = Base58.decodeNoCheck(string: computeBudgetProgramId), data.count == 32 else {
            preconditionFailure("ComputeBudget program id must decode to 32 bytes")
        }
        return [UInt8](data)
    }()

    /// The 32 raw bytes of `memoProgramId`, decoded once — same compile-time
    /// constant argument as `computeBudgetProgramKey`, pinned by the same tests.
    static let memoProgramKey: [UInt8] = {
        guard let data = Base58.decodeNoCheck(string: memoProgramId), data.count == 32 else {
            preconditionFailure("Memo program id must decode to 32 bytes")
        }
        return [UInt8](data)
    }()

    struct Instruction: Equatable {
        /// Index into the **static** account keys. Versioned messages forbid
        /// invoking a program loaded from a lookup table, so this is never a
        /// lookup-derived index — which is exactly why injection leaves it alone.
        let programIdIndex: UInt8
        let accountIndexes: [UInt8]
        let data: [UInt8]
    }

    struct AddressTableLookup: Equatable {
        let tableKey: [UInt8]
        let writableIndexes: [UInt8]
        let readonlyIndexes: [UInt8]

        var tableAddress: String { Base58.encodeNoCheck(data: Data(tableKey)) }
        var loadedAccountCount: Int { writableIndexes.count + readonlyIndexes.count }
    }

    /// The complete wire transaction: the signature vector followed by the
    /// serialized message.
    private let wire: [UInt8]

    /// Byte range of the signature slots, i.e. past the count prefix and up to
    /// the first message byte.
    let signaturesRange: Range<Int>
    /// Offset of the first message byte, i.e. just past the signature vector.
    let messageOffset: Int
    let numRequiredSignatures: UInt8
    let numReadonlySignedAccounts: UInt8
    let numReadonlyUnsignedAccounts: UInt8
    let staticAccountKeys: [[UInt8]]
    /// Byte range of the 32-byte recent-blockhash field within `wire`.
    let blockhashRange: Range<Int>
    let instructions: [Instruction]
    let addressTableLookups: [AddressTableLookup]

    // MARK: - Derived

    var wireSize: Int { wire.count }

    var base64EncodedTransaction: String { Data(wire).base64EncodedString() }

    var staticAccountAddresses: [String] {
        staticAccountKeys.map { Base58.encodeNoCheck(data: Data($0)) }
    }

    /// Signer index 0 — the account that pays the fee.
    var feePayer: String { Base58.encodeNoCheck(data: Data(staticAccountKeys[0])) }

    var recentBlockhash: String { Base58.encodeNoCheck(data: Data(wire[blockhashRange])) }

    /// Static keys plus every account the lookup tables load. This is the space
    /// instruction account indexes address.
    var totalAccountCount: Int {
        staticAccountKeys.count + addressTableLookups.reduce(0) { $0 + $1.loadedAccountCount }
    }

    var hasComputeBudgetInstruction: Bool {
        instructions.contains { staticAccountKeys[Int($0.programIdIndex)] == Self.computeBudgetProgramKey }
    }

    var hasMemoInstruction: Bool {
        instructions.contains { staticAccountKeys[Int($0.programIdIndex)] == Self.memoProgramKey }
    }

    // MARK: - Parsing

    init(base64Transaction: String) throws {
        guard let data = Data(base64Encoded: base64Transaction) else {
            throw SolanaV0TransactionError.invalidBase64
        }
        try self.init(wireBytes: [UInt8](data))
    }

    init(wireBytes: [UInt8]) throws {
        guard wireBytes.count <= Self.maxWireSize else {
            throw SolanaV0TransactionError.oversizedTransaction(wireBytes.count)
        }

        var cursor = Cursor(bytes: wireBytes)

        let signatureCount = try cursor.compactLength()
        let signaturesStart = cursor.offset
        _ = try cursor.take(64 * signatureCount)
        let messageOffset = cursor.offset

        // The high bit of the first message byte marks a versioned message; the
        // low seven carry the version. A legacy message starts with the header's
        // `numRequiredSignatures`, which is always < 128, so the bit is an
        // unambiguous discriminator.
        let versionByte = try cursor.byte()
        guard versionByte & 0x80 != 0 else { throw SolanaV0TransactionError.legacyMessageUnsupported }
        guard versionByte & 0x7F == 0 else {
            throw SolanaV0TransactionError.unsupportedMessageVersion(Int(versionByte & 0x7F))
        }

        let numRequiredSignatures = try cursor.byte()
        let numReadonlySigned = try cursor.byte()
        let numReadonlyUnsigned = try cursor.byte()

        let keyCount = try cursor.compactLength()
        var keys: [[UInt8]] = []
        keys.reserveCapacity(keyCount)
        for _ in 0..<keyCount {
            keys.append(Array(try cursor.take(32)))
        }

        let blockhashStart = cursor.offset
        _ = try cursor.take(32)

        let instructionCount = try cursor.compactLength()
        var instructions: [Instruction] = []
        instructions.reserveCapacity(instructionCount)
        for _ in 0..<instructionCount {
            let programIdIndex = try cursor.byte()
            let accountCount = try cursor.compactLength()
            let accountIndexes = Array(try cursor.take(accountCount))
            let dataLength = try cursor.compactLength()
            let data = Array(try cursor.take(dataLength))
            instructions.append(
                Instruction(programIdIndex: programIdIndex, accountIndexes: accountIndexes, data: data)
            )
        }

        let lookupCount = try cursor.compactLength()
        var lookups: [AddressTableLookup] = []
        lookups.reserveCapacity(lookupCount)
        for _ in 0..<lookupCount {
            let tableKey = Array(try cursor.take(32))
            let writableCount = try cursor.compactLength()
            let writableIndexes = Array(try cursor.take(writableCount))
            let readonlyCount = try cursor.compactLength()
            let readonlyIndexes = Array(try cursor.take(readonlyCount))
            lookups.append(
                AddressTableLookup(
                    tableKey: tableKey,
                    writableIndexes: writableIndexes,
                    readonlyIndexes: readonlyIndexes
                )
            )
        }

        guard cursor.offset == wireBytes.count else {
            throw SolanaV0TransactionError.trailingBytes(wireBytes.count - cursor.offset)
        }

        self.wire = wireBytes
        self.signaturesRange = signaturesStart..<messageOffset
        self.messageOffset = messageOffset
        self.numRequiredSignatures = numRequiredSignatures
        self.numReadonlySignedAccounts = numReadonlySigned
        self.numReadonlyUnsignedAccounts = numReadonlyUnsigned
        self.staticAccountKeys = keys
        self.blockhashRange = blockhashStart..<(blockhashStart + 32)
        self.instructions = instructions
        self.addressTableLookups = lookups

        try validateStructure(encodedSignatureCount: signatureCount)
    }

    /// Invariants Solana itself enforces when it sanitizes a message. Checked at
    /// parse time so a malformed transaction is rejected before any edit, rather
    /// than producing edited bytes that only fail at the RPC node.
    private func validateStructure(encodedSignatureCount: Int) throws {
        guard encodedSignatureCount == Int(numRequiredSignatures) else {
            throw SolanaV0TransactionError.signatureCountMismatch(
                header: Int(numRequiredSignatures),
                encoded: encodedSignatureCount
            )
        }
        // The fee payer is signer 0 and must be writable, so the read-only
        // signer block can never cover every signer.
        guard numRequiredSignatures > 0,
              numReadonlySignedAccounts < numRequiredSignatures,
              Int(numRequiredSignatures) + Int(numReadonlyUnsignedAccounts) <= staticAccountKeys.count
        else {
            throw SolanaV0TransactionError.malformedHeader
        }
        // A lookup that loads nothing is a wasted 32-byte reference and is
        // rejected by the runtime.
        guard !addressTableLookups.contains(where: { $0.loadedAccountCount == 0 }) else {
            throw SolanaV0TransactionError.emptyAddressTableLookup
        }

        let accountCount = totalAccountCount
        guard accountCount <= Self.maxAccountCount else {
            throw SolanaV0TransactionError.tooManyAccounts(accountCount)
        }

        for (position, instruction) in instructions.enumerated() {
            guard Int(instruction.programIdIndex) < staticAccountKeys.count else {
                throw SolanaV0TransactionError.programIdFromLookupTable(instruction: position)
            }
            // Solana refuses to invoke the fee payer as a program, so a message
            // that does is one the network would drop after we had signed it.
            guard instruction.programIdIndex != 0 else {
                throw SolanaV0TransactionError.programIdIsFeePayer(instruction: position)
            }
            for index in instruction.accountIndexes where Int(index) >= accountCount {
                throw SolanaV0TransactionError.accountIndexOutOfRange(
                    instruction: position,
                    index: Int(index),
                    accountCount: accountCount
                )
            }
        }
    }

    // MARK: - Fail-closed preconditions

    /// Asserts the shape the app is willing to sign: a single required signature
    /// whose slot is still an all-zero placeholder, paid for by `feePayer`.
    ///
    /// The zero-placeholder check is what makes the signature splice at index 0
    /// safe, and the fee-payer check is what stops a builder from handing back a
    /// transaction that another account pays for — or that pays out of an
    /// account the user does not control.
    func validateUnsignedSingleSigner(feePayer expected: String) throws {
        guard numRequiredSignatures == 1 else {
            throw SolanaV0TransactionError.notSingleSigner(Int(numRequiredSignatures))
        }
        guard wire[signaturesRange].allSatisfy({ $0 == 0 }) else {
            throw SolanaV0TransactionError.signaturePlaceholderNotEmpty
        }
        guard feePayer == expected else {
            throw SolanaV0TransactionError.feePayerMismatch(expected: expected, actual: feePayer)
        }
    }

    // MARK: - Edits

    /// Replaces the 32-byte recent blockhash **in place**.
    ///
    /// Nothing else in the transaction moves: the length of the field is fixed,
    /// so the surrounding bytes — including the signature slots — stay exactly
    /// where they were. The result is re-parsed only to re-derive the spans and
    /// re-run the structural guards.
    func replacingBlockhash(_ blockhash: String) throws -> SolanaV0Transaction {
        guard let decoded = Base58.decodeNoCheck(string: blockhash), decoded.count == 32 else {
            throw SolanaV0TransactionError.invalidBlockhash
        }
        var bytes = wire
        bytes.replaceSubrange(blockhashRange, with: [UInt8](decoded))
        return try SolanaV0Transaction(wireBytes: bytes)
    }

    /// Prepends `SetComputeUnitLimit` + `SetComputeUnitPrice`, appending the
    /// ComputeBudget program as a new **static, read-only, unsigned** account key.
    ///
    /// See `injecting(programKey:leading:trailing:)` for the account-key and
    /// index-drift mechanics both injections share.
    func injectingComputeBudget(price: UInt64, limit: UInt32) throws -> SolanaV0Transaction {
        guard limit > 0, limit <= Self.maxComputeUnitLimit else {
            throw SolanaV0TransactionError.computeUnitLimitOutOfRange(limit)
        }
        // Both checks matter. A stray ComputeBudget key with no instruction would
        // make the append a duplicate account; an instruction with no static key
        // is impossible, but checking it keeps the guard honest if the key ever
        // arrives through a lookup table.
        guard !staticAccountKeys.contains(Self.computeBudgetProgramKey), !hasComputeBudgetInstruction else {
            throw SolanaV0TransactionError.computeBudgetAlreadyPresent
        }

        return try injecting(
            programKey: Self.computeBudgetProgramKey,
            leading: { programIdIndex in
                [
                    Instruction(
                        programIdIndex: programIdIndex,
                        accountIndexes: [],
                        data: [ComputeBudgetInstruction.setUnitLimit] + Self.littleEndianBytes(limit)
                    ),
                    Instruction(
                        programIdIndex: programIdIndex,
                        accountIndexes: [],
                        data: [ComputeBudgetInstruction.setUnitPrice] + Self.littleEndianBytes(price)
                    )
                ]
            },
            trailing: { _ in [] }
        )
    }

    /// Appends one SPL Memo instruction carrying `text`, with the Memo program as
    /// a new **static, read-only, unsigned** account key.
    ///
    /// Appended rather than prepended: the memo records who originated the
    /// transaction and takes no part in what it does, so it belongs after the
    /// instructions that move the money — and putting it last keeps every
    /// existing instruction at the position the template already expects, with
    /// only the two compute-budget instructions ahead of them.
    ///
    /// The memo has no accounts and no signer of its own. A memo instruction
    /// listing signer accounts is how the Memo program attests to them, and
    /// attesting is not what this is for.
    func injectingMemo(_ text: String) throws -> SolanaV0Transaction {
        let data = [UInt8](Data(text.utf8))
        guard !data.isEmpty, data.count <= Self.maxMemoByteCount else {
            throw SolanaV0TransactionError.memoOutOfRange(data.count)
        }
        // Same pair of checks as the budget injection, for the same reason: the
        // key and the instruction are two ways for a memo to already be here, and
        // appending a second one would both duplicate the account and leave the
        // transaction carrying two attributions.
        guard !staticAccountKeys.contains(Self.memoProgramKey), !hasMemoInstruction else {
            throw SolanaV0TransactionError.memoAlreadyPresent
        }

        return try injecting(
            programKey: Self.memoProgramKey,
            leading: { _ in [] },
            trailing: { programIdIndex in
                [Instruction(programIdIndex: programIdIndex, accountIndexes: [], data: data)]
            }
        )
    }

    /// Appends `programKey` as a new **static, read-only, unsigned** account key
    /// and re-serializes the message with `leading` instructions in front of the
    /// existing ones and `trailing` behind them.
    ///
    /// Static keys are ordered by privilege — writable signers, read-only
    /// signers, writable non-signers, read-only non-signers — so the read-only
    /// unsigned block is the tail, and appending there plus incrementing
    /// `numReadonlyUnsignedAccounts` preserves the ordering without moving any
    /// existing key.
    ///
    /// The one consequence is index drift: indexes at or above the old static
    /// count addressed lookup-table-loaded accounts, which now begin one slot
    /// later, so each is shifted by one. `programIdIndex` values are untouched —
    /// a versioned message may not invoke a program loaded from a lookup table,
    /// so every program is already a static key below the insertion point. The
    /// indexes *inside* each `AddressTableLookup` are positions in the table
    /// itself, not in this message, so they are untouched too.
    ///
    /// Both closures receive the index the new key lands at, which is the only
    /// thing an injected instruction needs that it cannot know beforehand.
    private func injecting(
        programKey: [UInt8],
        leading: (UInt8) -> [Instruction],
        trailing: (UInt8) -> [Instruction]
    ) throws -> SolanaV0Transaction {
        // Checked before any index arithmetic: with the new key the message must
        // still address at most 256 accounts, which bounds both the appended
        // key's own index and every shifted index below `UInt8.max`.
        let newAccountCount = totalAccountCount + 1
        guard newAccountCount <= Self.maxAccountCount else {
            throw SolanaV0TransactionError.tooManyAccounts(newAccountCount)
        }

        let oldStaticCount = staticAccountKeys.count
        let programIdIndex = UInt8(oldStaticCount)
        let keys = staticAccountKeys + [programKey]

        let shifted = instructions.map { instruction in
            Instruction(
                programIdIndex: instruction.programIdIndex,
                accountIndexes: instruction.accountIndexes.map {
                    Int($0) >= oldStaticCount ? $0 + 1 : $0
                },
                data: instruction.data
            )
        }

        var message: [UInt8] = [0x80, numRequiredSignatures, numReadonlySignedAccounts]
        message.append(numReadonlyUnsignedAccounts + 1)
        message += try Self.encodeCompactLength(keys.count)
        for key in keys { message += key }
        message += wire[blockhashRange]

        let allInstructions = leading(programIdIndex) + shifted + trailing(programIdIndex)
        message += try Self.encodeCompactLength(allInstructions.count)
        for instruction in allInstructions {
            message.append(instruction.programIdIndex)
            message += try Self.encodeCompactLength(instruction.accountIndexes.count)
            message += instruction.accountIndexes
            message += try Self.encodeCompactLength(instruction.data.count)
            message += instruction.data
        }

        message += try Self.encodeCompactLength(addressTableLookups.count)
        for lookup in addressTableLookups {
            message += lookup.tableKey
            message += try Self.encodeCompactLength(lookup.writableIndexes.count)
            message += lookup.writableIndexes
            message += try Self.encodeCompactLength(lookup.readonlyIndexes.count)
            message += lookup.readonlyIndexes
        }

        // Re-checked by the parse below, but checking here names the injection as
        // the cause instead of reporting a generic malformed transaction.
        let bytes = Array(wire[0..<messageOffset]) + message
        guard bytes.count <= Self.maxWireSize else {
            throw SolanaV0TransactionError.oversizedTransaction(bytes.count)
        }

        return try SolanaV0Transaction(wireBytes: bytes)
    }

    // MARK: - Address resolution

    /// Every account key the message addresses, in index order: the static keys,
    /// then the writable accounts each lookup loads, then the read-only ones —
    /// the same order the runtime builds.
    ///
    /// - Parameter lookupTables: table address to that table's full address list.
    func resolvedAccountAddresses(lookupTables: [String: [String]]) throws -> [String] {
        var writable: [String] = []
        var readonly: [String] = []

        for lookup in addressTableLookups {
            let address = lookup.tableAddress
            guard let table = lookupTables[address] else {
                throw SolanaV0TransactionError.unknownLookupTable(address)
            }
            writable += try lookup.writableIndexes.map { try Self.entry($0, in: table, at: address) }
            readonly += try lookup.readonlyIndexes.map { try Self.entry($0, in: table, at: address) }
        }

        return staticAccountAddresses + writable + readonly
    }

    /// The account addresses an instruction passes, resolved through the lookup
    /// tables. Duplicates are preserved — an instruction may legitimately pass
    /// the same account twice.
    func resolvedAccountAddresses(
        forInstructionAt position: Int,
        lookupTables: [String: [String]]
    ) throws -> [String] {
        guard instructions.indices.contains(position) else {
            throw SolanaV0TransactionError.accountIndexOutOfRange(
                instruction: position,
                index: position,
                accountCount: instructions.count
            )
        }
        let resolved = try resolvedAccountAddresses(lookupTables: lookupTables)
        return try instructions[position].accountIndexes.map { index in
            guard Int(index) < resolved.count else {
                throw SolanaV0TransactionError.accountIndexOutOfRange(
                    instruction: position,
                    index: Int(index),
                    accountCount: resolved.count
                )
            }
            return resolved[Int(index)]
        }
    }

    /// Whether the account at `index` has to sign. Signers occupy the first
    /// `numRequiredSignatures` static slots and can never come from a lookup
    /// table.
    func isSigner(accountIndex index: Int) -> Bool {
        guard (0..<totalAccountCount).contains(index) else { return false }
        return index < Int(numRequiredSignatures)
    }

    /// Whether the account at `index` is loaded writable.
    ///
    /// Writability is positional, not stored per account: within the static keys
    /// the read-only accounts are the tail of each of the signer and non-signer
    /// blocks, and among lookup-loaded accounts the writable ones all precede
    /// the read-only ones. That is exactly why injecting a key into the wrong
    /// block — or forgetting to bump `numReadonlyUnsignedAccounts` — would
    /// silently re-privilege unrelated accounts rather than fail to parse.
    func isWritable(accountIndex index: Int) -> Bool {
        // Out of range fails closed: an index nothing addresses is not something
        // the transaction may write to.
        guard (0..<totalAccountCount).contains(index) else { return false }
        let staticCount = staticAccountKeys.count
        if index < Int(numRequiredSignatures) {
            return index < Int(numRequiredSignatures) - Int(numReadonlySignedAccounts)
        }
        if index < staticCount {
            return index < staticCount - Int(numReadonlyUnsignedAccounts)
        }
        let writableLoaded = addressTableLookups.reduce(0) { $0 + $1.writableIndexes.count }
        return index - staticCount < writableLoaded
    }

    private static func entry(_ index: UInt8, in table: [String], at address: String) throws -> String {
        guard Int(index) < table.count else {
            throw SolanaV0TransactionError.lookupIndexOutOfRange(
                table: address,
                index: Int(index),
                tableSize: table.count
            )
        }
        return table[Int(index)]
    }

    // MARK: - compact-u16

    /// The widest value compact-u16 can express.
    static let maxCompactLength = 0xFFFF

    /// Serializes a length in Solana's compact-u16 ("short vec") form, always in
    /// its shortest encoding.
    ///
    /// Throws outside `0...65535` rather than emitting something: a negative
    /// value has no encoding at all, and a value past `UInt16` would be
    /// serialized as a truncated one that silently means a different length.
    static func encodeCompactLength(_ value: Int) throws -> [UInt8] {
        guard (0...maxCompactLength).contains(value) else {
            throw SolanaV0TransactionError.malformedLengthPrefix
        }
        var remaining = value
        var out: [UInt8] = []
        while true {
            let chunk = UInt8(remaining & 0x7F)
            remaining >>= 7
            if remaining == 0 {
                out.append(chunk)
                return out
            }
            out.append(chunk | 0x80)
        }
    }

    /// Reads a compact-u16 length, rejecting anything but its shortest encoding.
    ///
    /// The strictness matters: a padded encoding of the same number would let two
    /// different byte strings describe the same transaction, and the app hashes
    /// bytes rather than a decoded structure. Solana's own decoder rejects them
    /// too, so accepting one would mean signing something the network won't.
    ///
    /// What is *not* padding is a zero payload chunk in a continuing byte —
    /// 16,384 encodes as `80 80 01`, whose first two bytes carry no value bits at
    /// all yet is the only encoding of that number. The rule is a zero **byte**
    /// past the first, which is what Solana checks.
    ///
    /// - Returns: the value and how many bytes it consumed.
    static func decodeCompactLength(_ bytes: ArraySlice<UInt8>) throws -> (value: Int, byteCount: Int) {
        var value = 0
        var shift = 0
        var consumed = 0

        for index in bytes.indices.prefix(3) {
            let byte = bytes[index]
            consumed += 1
            guard consumed == 1 || byte != 0 else {
                throw SolanaV0TransactionError.malformedLengthPrefix
            }
            value |= Int(byte & 0x7F) << shift
            if byte & 0x80 == 0 {
                guard value <= maxCompactLength else {
                    throw SolanaV0TransactionError.malformedLengthPrefix
                }
                return (value, consumed)
            }
            shift += 7
        }

        // Ran out of input mid-length is truncation; three continuing bytes is a
        // value compact-u16 cannot hold.
        guard consumed == 3 else {
            throw SolanaV0TransactionError.truncated(needed: consumed + 1, available: consumed)
        }
        throw SolanaV0TransactionError.malformedLengthPrefix
    }

    private static func littleEndianBytes(_ value: UInt32) -> [UInt8] {
        withUnsafeBytes(of: value.littleEndian) { [UInt8]($0) }
    }

    private static func littleEndianBytes(_ value: UInt64) -> [UInt8] {
        withUnsafeBytes(of: value.littleEndian) { [UInt8]($0) }
    }
}

/// ComputeBudget program instruction discriminants.
///
/// Note the offset: `RequestUnits` (deprecated) occupies 0, so the limit and
/// price instructions are 2 and 3 — not 1 and 2.
enum ComputeBudgetInstruction {
    static let requestUnitsDeprecated: UInt8 = 0
    static let requestHeapFrame: UInt8 = 1
    static let setUnitLimit: UInt8 = 2
    static let setUnitPrice: UInt8 = 3
}

/// Bounds-checked forward-only reader over the wire bytes.
private struct Cursor {
    let bytes: [UInt8]
    private(set) var offset = 0

    init(bytes: [UInt8]) {
        self.bytes = bytes
    }

    mutating func byte() throws -> UInt8 {
        guard offset < bytes.count else {
            throw SolanaV0TransactionError.truncated(needed: 1, available: 0)
        }
        defer { offset += 1 }
        return bytes[offset]
    }

    mutating func take(_ count: Int) throws -> ArraySlice<UInt8> {
        guard count >= 0, bytes.count - offset >= count else {
            throw SolanaV0TransactionError.truncated(needed: count, available: bytes.count - offset)
        }
        defer { offset += count }
        return bytes[offset..<(offset + count)]
    }

    mutating func compactLength() throws -> Int {
        let (value, byteCount) = try SolanaV0Transaction.decodeCompactLength(bytes[offset...])
        offset += byteCount
        return value
    }
}
