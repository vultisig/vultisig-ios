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
    let inputs: [SuiPtbInput]
    let commands: [SuiCommand]

    var inputCount: Int { inputs.count }
    var commandCount: Int { commands.count }
}

/// A PTB argument reference, mirroring the Windows `SuiArgument` union.
enum SuiArgument: Equatable {
    case gasCoin
    case input(index: Int)
    case result(index: Int)
    case nestedResult(commandIndex: Int, resultIndex: Int)
}

/// A decoded PTB input, mirroring the Windows `SuiPtbInput` union. `pure`
/// carries the raw BCS bytes (we don't have the consuming call's ABI offline,
/// so values are rendered best-effort); object inputs carry their id + kind.
enum SuiPtbInput: Equatable {
    enum ObjectKind: String, Equatable {
        case immOrOwnedObject = "ImmOrOwnedObject"
        case sharedObject = "SharedObject"
        case receiving = "Receiving"
    }

    case pure(bytes: Data)
    case object(kind: ObjectKind, objectId: String, mutable: Bool?)
}

/// A decoded PTB command, mirroring the Windows `SuiCommand` union.
enum SuiCommand: Equatable {
    case moveCall(package: String, module: String, function: String, typeArguments: [String], arguments: [SuiArgument])
    case transferObjects(objects: [SuiArgument], address: SuiArgument)
    case splitCoins(coin: SuiArgument, amounts: [SuiArgument])
    case mergeCoins(destination: SuiArgument, sources: [SuiArgument])
    case publish(moduleCount: Int, dependencyCount: Int)
    case makeMoveVec(type: String?, elements: [SuiArgument])
    case upgrade(moduleCount: Int, dependencyCount: Int, package: String, ticket: SuiArgument)
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
        guard let txKind = reader.readULEB128(), txKind == 0 else { return nil }

        // ProgrammableTransaction { inputs: Vec<CallArg>, commands: Vec<Command> }
        guard let inputs = readInputs(&reader),
              let commands = readCommands(&reader) else {
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
            inputs: inputs,
            commands: commands
        )
    }

    // MARK: - Inputs

    private static func readInputs(_ reader: inout BCSReader) -> [SuiPtbInput]? {
        guard let count = reader.readULEB128() else { return nil }
        var inputs: [SuiPtbInput] = []
        inputs.reserveCapacity(Int(count))
        for _ in 0..<Int(count) {
            guard let input = readInput(&reader) else { return nil }
            inputs.append(input)
        }
        return inputs
    }

    /// CallArg = enum { Pure(Vec<u8>)(0), Object(ObjectArg)(1) }.
    private static func readInput(_ reader: inout BCSReader) -> SuiPtbInput? {
        guard let variant = reader.readULEB128() else { return nil }
        switch variant {
        case 0:
            guard let bytes = reader.readBytesVec() else { return nil }
            return .pure(bytes: bytes)
        case 1:
            return readObjectArg(&reader)
        default:
            return nil
        }
    }

    /// ObjectArg = enum {
    ///   ImmOrOwnedObject(ObjectRef)(0),
    ///   SharedObject { id, initial_shared_version: u64, mutable: bool }(1),
    ///   Receiving(ObjectRef)(2)
    /// }
    private static func readObjectArg(_ reader: inout BCSReader) -> SuiPtbInput? {
        guard let objKind = reader.readULEB128() else { return nil }
        switch objKind {
        case 0, 2:
            // ObjectRef = ObjectID(32) + SequenceNumber(u64) + ObjectDigest(vec<u8>)
            guard let objectId = reader.readAddressHex(),
                  reader.skip(8),
                  let digestLen = reader.readULEB128(),
                  reader.skip(Int(digestLen)) else { return nil }
            let kind: SuiPtbInput.ObjectKind = objKind == 0 ? .immOrOwnedObject : .receiving
            return .object(kind: kind, objectId: objectId, mutable: nil)
        case 1:
            // id(32) + initial_shared_version(u64) + mutable(bool)
            guard let objectId = reader.readAddressHex(),
                  reader.skip(8),
                  let mutableByte = reader.readByte() else { return nil }
            return .object(kind: .sharedObject, objectId: objectId, mutable: mutableByte != 0)
        default:
            return nil
        }
    }

    // MARK: - Commands

    private static func readCommands(_ reader: inout BCSReader) -> [SuiCommand]? {
        guard let count = reader.readULEB128() else { return nil }
        var commands: [SuiCommand] = []
        commands.reserveCapacity(Int(count))
        for _ in 0..<Int(count) {
            guard let command = readCommand(&reader) else { return nil }
            commands.append(command)
        }
        return commands
    }

    /// Command enum: MoveCall(0), TransferObjects(1), SplitCoins(2),
    /// MergeCoins(3), Publish(4), MakeMoveVec(5), Upgrade(6).
    private static func readCommand(_ reader: inout BCSReader) -> SuiCommand? {
        guard let variant = reader.readULEB128() else { return nil }
        switch variant {
        case 0:
            return readMoveCall(&reader)
        case 1:
            // TransferObjects { objects: Vec<Argument>, address: Argument }
            guard let objects = readArguments(&reader),
                  let address = readArgument(&reader) else { return nil }
            return .transferObjects(objects: objects, address: address)
        case 2:
            // SplitCoins { coin: Argument, amounts: Vec<Argument> }
            guard let coin = readArgument(&reader),
                  let amounts = readArguments(&reader) else { return nil }
            return .splitCoins(coin: coin, amounts: amounts)
        case 3:
            // MergeCoins { destination: Argument, sources: Vec<Argument> }
            guard let destination = readArgument(&reader),
                  let sources = readArguments(&reader) else { return nil }
            return .mergeCoins(destination: destination, sources: sources)
        case 4:
            // Publish { modules: Vec<Vec<u8>>, dependencies: Vec<address> }
            guard let moduleCount = readByteVectorCount(&reader),
                  let depCount = readAddressVectorCount(&reader) else { return nil }
            return .publish(moduleCount: moduleCount, dependencyCount: depCount)
        case 5:
            // MakeMoveVec { type: Option<TypeTag>, elements: Vec<Argument> }
            guard let type = readOptionTypeTag(&reader),
                  let elements = readArguments(&reader) else { return nil }
            return .makeMoveVec(type: type.tag, elements: elements)
        case 6:
            // Upgrade { modules, dependencies, package: address, ticket: Argument }
            guard let moduleCount = readByteVectorCount(&reader),
                  let depCount = readAddressVectorCount(&reader),
                  let package = reader.readAddressHex(),
                  let ticket = readArgument(&reader) else { return nil }
            return .upgrade(moduleCount: moduleCount, dependencyCount: depCount, package: package, ticket: ticket)
        default:
            return nil
        }
    }

    /// ProgrammableMoveCall { package: address, module: String, function: String,
    /// type_arguments: Vec<TypeTag>, arguments: Vec<Argument> }.
    private static func readMoveCall(_ reader: inout BCSReader) -> SuiCommand? {
        guard let package = reader.readAddressHex(),
              let module = reader.readString(),
              let function = reader.readString(),
              let typeArguments = readTypeTagVector(&reader),
              let arguments = readArguments(&reader) else { return nil }
        return .moveCall(
            package: package,
            module: module,
            function: function,
            typeArguments: typeArguments,
            arguments: arguments
        )
    }

    private static func readByteVectorCount(_ reader: inout BCSReader) -> Int? {
        guard let count = reader.readULEB128() else { return nil }
        for _ in 0..<Int(count) {
            guard let len = reader.readULEB128(), reader.skip(Int(len)) else { return nil }
        }
        return Int(count)
    }

    private static func readAddressVectorCount(_ reader: inout BCSReader) -> Int? {
        guard let count = reader.readULEB128() else { return nil }
        guard reader.skip(Int(count) * 32) else { return nil }
        return Int(count)
    }

    // MARK: - Arguments

    private static func readArguments(_ reader: inout BCSReader) -> [SuiArgument]? {
        guard let count = reader.readULEB128() else { return nil }
        var arguments: [SuiArgument] = []
        arguments.reserveCapacity(Int(count))
        for _ in 0..<Int(count) {
            guard let argument = readArgument(&reader) else { return nil }
            arguments.append(argument)
        }
        return arguments
    }

    /// Argument = enum { GasCoin(0), Input(u16)(1), Result(u16)(2),
    /// NestedResult(u16, u16)(3) }. The indices are u16 LE, not ULEB.
    private static func readArgument(_ reader: inout BCSReader) -> SuiArgument? {
        guard let variant = reader.readULEB128() else { return nil }
        switch variant {
        case 0:
            return .gasCoin
        case 1:
            guard let index = reader.readU16() else { return nil }
            return .input(index: Int(index))
        case 2:
            guard let index = reader.readU16() else { return nil }
            return .result(index: Int(index))
        case 3:
            guard let commandIndex = reader.readU16(), let resultIndex = reader.readU16() else { return nil }
            return .nestedResult(commandIndex: Int(commandIndex), resultIndex: Int(resultIndex))
        default:
            return nil
        }
    }

    // MARK: - TypeTag

    private static func readTypeTagVector(_ reader: inout BCSReader) -> [String]? {
        guard let count = reader.readULEB128() else { return nil }
        var tags: [String] = []
        tags.reserveCapacity(Int(count))
        for _ in 0..<Int(count) {
            guard let tag = readTypeTag(&reader) else { return nil }
            tags.append(tag)
        }
        return tags
    }

    /// Option<TypeTag> = enum { None(0), Some(TypeTag)(1) }. The outer optional
    /// signals a decode failure; the inner `tag` is `nil` for the `None` case.
    private static func readOptionTypeTag(_ reader: inout BCSReader) -> (tag: String?, present: Bool)? {
        guard let variant = reader.readULEB128() else { return nil }
        switch variant {
        case 0:
            return (tag: nil, present: false)
        case 1:
            guard let tag = readTypeTag(&reader) else { return nil }
            return (tag: tag, present: true)
        default:
            return nil
        }
    }

    /// Recursively decodes a `TypeTag` into its canonical
    /// `addr::module::Name<...>` string form (matching the Windows
    /// `typeArguments` strings).
    private static func readTypeTag(_ reader: inout BCSReader) -> String? {
        guard let variant = reader.readULEB128() else { return nil }
        switch variant {
        case 0: return "bool"
        case 1: return "u8"
        case 2: return "u64"
        case 3: return "u128"
        case 4: return "address"
        case 5: return "signer"
        case 6:
            guard let inner = readTypeTag(&reader) else { return nil }
            return "vector<\(inner)>"
        case 7:
            return readStructTag(&reader)
        case 8: return "u16"
        case 9: return "u32"
        case 10: return "u256"
        default: return nil
        }
    }

    /// StructTag { address, module: String, name: String,
    /// type_params: Vec<TypeTag> }.
    private static func readStructTag(_ reader: inout BCSReader) -> String? {
        guard let address = reader.readAddressHex(),
              let module = reader.readString(),
              let name = reader.readString(),
              let typeParams = readTypeTagVector(&reader) else { return nil }
        let base = "\(address)::\(module)::\(name)"
        guard !typeParams.isEmpty else { return base }
        return "\(base)<\(typeParams.joined(separator: ", "))>"
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

    mutating func readU16() -> UInt16? {
        guard remaining >= 2 else { return nil }
        let value = UInt16(bytes[offset]) | (UInt16(bytes[offset + 1]) << 8)
        offset += 2
        return value
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

    /// Reads a ULEB128-length-prefixed byte vector and returns its bytes.
    mutating func readBytesVec() -> Data? {
        guard let len = readULEB128() else { return nil }
        let count = Int(len)
        guard remaining >= count else { return nil }
        let slice = bytes[offset..<offset + count]
        offset += count
        return Data(slice)
    }

    /// Reads a ULEB128-length-prefixed UTF-8 string.
    mutating func readString() -> String? {
        guard let data = readBytesVec() else { return nil }
        return String(data: data, encoding: .utf8)
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
