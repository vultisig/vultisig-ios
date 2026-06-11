//
//  SuiTransactionDataParser.swift
//  VultisigApp
//

import Foundation

/// A best-effort decode of a Sui `TransactionData` (V1) BCS payload, used only
/// to render a human-readable summary on the keysign verify screen. The bytes
/// themselves are always signed verbatim — this parser never feeds the signing
/// pipeline, so a decode failure degrades gracefully to showing the raw base64.
struct SuiTransactionDataSummary: Equatable {
    let sender: String
    let gasOwner: String
    let gasBudget: UInt64
    let gasPrice: UInt64
    let gasPaymentCount: Int
    let inputCount: Int
    let commandCount: Int
}

enum SuiTransactionDataParser {

    /// Decodes the subset of `TransactionData::V1` we surface to the user.
    /// Returns `nil` for any unexpected shape so callers fall back to raw bytes.
    static func parse(base64TransactionData: String) -> SuiTransactionDataSummary? {
        guard let data = Data(base64Encoded: base64TransactionData) else { return nil }
        var reader = BCSReader(data: data)

        // TransactionData is an enum; V1 is variant 0.
        guard let kind = reader.readULEB128(), kind == 0 else { return nil }

        // TransactionDataV1 { kind: TransactionKind, sender, gas_data, expiration }
        // TransactionKind is an enum; ProgrammableTransaction is variant 0.
        guard let txKind = reader.readULEB128() else { return nil }
        guard txKind == 0 else { return nil }

        // ProgrammableTransaction { inputs: Vec<CallArg>, commands: Vec<Command> }
        // We don't fully decode each input/command (their bodies are
        // variable-length and version-sensitive); we count the top-level
        // vectors and let the signer read the bytes verbatim. To count safely
        // we skip each element by parsing only its discriminant-led length,
        // which is fragile across versions — so on any ambiguity we bail to a
        // partial summary that still carries sender + gas.
        guard let inputCount = reader.readULEB128() else { return nil }
        guard let commands = countCommandsBySkippingInputs(&reader, inputCount: Int(inputCount)) else {
            return nil
        }

        // sender: address (32 bytes)
        guard let sender = reader.readAddressHex() else { return nil }

        // GasData { payment: Vec<ObjectRef>, owner: address, price: u64, budget: u64 }
        guard let paymentCount = reader.readULEB128() else { return nil }
        for _ in 0..<Int(paymentCount) {
            // ObjectRef = (ObjectID(32), SequenceNumber(u64), ObjectDigest(vec<u8>))
            guard reader.skip(32 + 8) else { return nil }
            guard let digestLen = reader.readULEB128(), reader.skip(Int(digestLen)) else { return nil }
        }
        guard let gasOwner = reader.readAddressHex(),
              let gasPrice = reader.readU64(),
              let gasBudget = reader.readU64() else { return nil }

        return SuiTransactionDataSummary(
            sender: sender,
            gasOwner: gasOwner,
            gasBudget: gasBudget,
            gasPrice: gasPrice,
            gasPaymentCount: Int(paymentCount),
            inputCount: Int(inputCount),
            commandCount: commands
        )
    }

    /// Skips the `inputs` vector body, then reads and skips the `commands`
    /// vector, returning the command count. Returns `nil` on any unexpected
    /// element shape so the caller falls back to raw bytes.
    private static func countCommandsBySkippingInputs(_ reader: inout BCSReader, inputCount: Int) -> Int? {
        for _ in 0..<inputCount {
            guard SuiCallArgSkipper.skip(&reader) else { return nil }
        }
        guard let commandCount = reader.readULEB128() else { return nil }
        for _ in 0..<Int(commandCount) {
            guard SuiCommandSkipper.skip(&reader) else { return nil }
        }
        return Int(commandCount)
    }
}

/// Minimal little-endian BCS byte reader.
struct BCSReader {
    private let bytes: [UInt8]
    private(set) var offset: Int = 0

    init(data: Data) {
        self.bytes = [UInt8](data)
    }

    var remaining: Int { bytes.count - offset }

    mutating func skip(_ count: Int) -> Bool {
        guard count >= 0, remaining >= count else { return false }
        offset += count
        return true
    }

    mutating func readByte() -> UInt8? {
        guard remaining >= 1 else { return nil }
        defer { offset += 1 }
        return bytes[offset]
    }

    mutating func readU64() -> UInt64? {
        guard remaining >= 8 else { return nil }
        var value: UInt64 = 0
        for i in 0..<8 {
            value |= UInt64(bytes[offset + i]) << (8 * i)
        }
        offset += 8
        return value
    }

    mutating func readAddressHex() -> String? {
        guard remaining >= 32 else { return nil }
        let slice = bytes[offset..<offset + 32]
        offset += 32
        return "0x" + slice.map { String(format: "%02x", $0) }.joined()
    }

    /// Reads an unsigned LEB128 vector-length / enum-discriminant.
    mutating func readULEB128() -> UInt64? {
        var result: UInt64 = 0
        var shift: UInt64 = 0
        while true {
            guard let byte = readByte() else { return nil }
            result |= UInt64(byte & 0x7f) << shift
            if byte & 0x80 == 0 { break }
            shift += 7
            if shift >= 64 { return nil }
        }
        return result
    }
}

/// Skips a single `CallArg` (an enum) in the BCS stream. CallArg is either a
/// `Pure(Vec<u8>)` (variant 0) or an `Object` (variant 1) whose body is an
/// `ObjectArg` enum. We only need to advance past it, not interpret it.
private enum SuiCallArgSkipper {
    static func skip(_ reader: inout BCSReader) -> Bool {
        guard let variant = reader.readULEB128() else { return false }
        switch variant {
        case 0:
            // Pure(Vec<u8>)
            guard let len = reader.readULEB128() else { return false }
            return reader.skip(Int(len))
        case 1:
            // Object(ObjectArg) — ObjectArg is an enum:
            //   0: ImmOrOwnedObject(ObjectRef)
            //   1: SharedObject { id(32), initial_shared_version(u64), mutable(bool) }
            //   2: Receiving(ObjectRef)
            guard let objKind = reader.readULEB128() else { return false }
            switch objKind {
            case 0, 2:
                // ObjectRef = ObjectID(32) + SequenceNumber(u64) + ObjectDigest(vec<u8>)
                guard reader.skip(32 + 8) else { return false }
                guard let digestLen = reader.readULEB128() else { return false }
                return reader.skip(Int(digestLen))
            case 1:
                // id(32) + initial_shared_version(u64) + mutable(1)
                return reader.skip(32 + 8 + 1)
            default:
                return false
            }
        default:
            return false
        }
    }
}

/// Skips a single `Command` (an enum) in the BCS stream. We don't interpret the
/// command bodies — we only advance past them to reach `sender` / `gas_data`.
/// Argument-bearing commands carry counts we can walk; unknown shapes bail out.
private enum SuiCommandSkipper {
    // Argument = enum { GasCoin, Input(u16), Result(u16), NestedResult(u16,u16) }
    private static func skipArgument(_ reader: inout BCSReader) -> Bool {
        guard let variant = reader.readULEB128() else { return false }
        switch variant {
        case 0: return true                 // GasCoin
        case 1, 2: return reader.skip(2)    // Input(u16) / Result(u16)
        case 3: return reader.skip(4)       // NestedResult(u16, u16)
        default: return false
        }
    }

    private static func skipArguments(_ reader: inout BCSReader) -> Bool {
        guard let count = reader.readULEB128() else { return false }
        for _ in 0..<Int(count) where !skipArgument(&reader) { return false }
        return true
    }

    // TypeTag vector — we only need to skip the serialized bytes. TypeTags are
    // recursive; rather than fully decode them we treat the vector as opaque by
    // bailing out, which forces the raw-bytes fallback for type-heavy PTBs.
    static func skip(_ reader: inout BCSReader) -> Bool {
        guard let variant = reader.readULEB128() else { return false }
        switch variant {
        case 0:
            // MoveCall(Box<ProgrammableMoveCall>) — package(32), module(str),
            // function(str), type_arguments(Vec<TypeTag>), arguments(Vec<Argument>)
            guard reader.skip(32) else { return false }
            guard skipString(&reader), skipString(&reader) else { return false }
            // type_arguments: bail on any non-empty type-tag vector (opaque)
            guard let typeArgs = reader.readULEB128() else { return false }
            guard typeArgs == 0 else { return false }
            return skipArguments(&reader)
        case 1:
            // TransferObjects(Vec<Argument>, Argument)
            guard skipArguments(&reader) else { return false }
            return skipArgument(&reader)
        case 2:
            // SplitCoins(Argument, Vec<Argument>)
            guard skipArgument(&reader) else { return false }
            return skipArguments(&reader)
        case 3:
            // MergeCoins(Argument, Vec<Argument>)
            guard skipArgument(&reader) else { return false }
            return skipArguments(&reader)
        case 5:
            // MakeMoveVec(Option<TypeTag>, Vec<Argument>)
            guard let hasType = reader.readByte() else { return false }
            guard hasType == 0 else { return false } // bail on typed vectors
            return skipArguments(&reader)
        default:
            // Publish / Upgrade and any future variants carry version-sensitive
            // bodies — bail so the caller falls back to raw bytes.
            return false
        }
    }

    private static func skipString(_ reader: inout BCSReader) -> Bool {
        guard let len = reader.readULEB128() else { return false }
        return reader.skip(Int(len))
    }
}
