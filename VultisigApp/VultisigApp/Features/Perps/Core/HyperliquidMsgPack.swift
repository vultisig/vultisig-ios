//
//  HyperliquidMsgPack.swift
//  VultisigApp
//
//  A deliberately small msgpack encoder for Hyperliquid L1 actions.
//
//  Hyperliquid's L1 signature commits to `keccak(msgpack(action) ‖ nonce ‖ vault)`,
//  so the encoded bytes must be identical to what the venue (Rust `rmp-serde`),
//  the Python SDK (`msgpack.packb`) and the Vultisig SDK (`@msgpack/msgpack`)
//  produce for the same action. Two properties matter:
//    1. Map key ORDER is part of the bytes, so maps are ordered entry lists,
//       never `Dictionary`.
//    2. Integers use the smallest encoding, strings use fixstr/str8/16/32. That
//       is the default behaviour of all three reference encoders.
//  Floats are intentionally unsupported: Hyperliquid puts prices and sizes on
//  the wire as decimal strings.
//

import Foundation

/// An ordered msgpack value covering exactly what Hyperliquid actions use.
indirect enum HLValue: Equatable, Sendable {
    case null
    case bool(Bool)
    case int(Int64)
    case uint(UInt64)
    case string(String)
    case array([HLValue])
    case map([HLEntry])

    static func object(_ entries: [(String, HLValue)]) -> HLValue {
        .map(entries.map { HLEntry(key: $0.0, value: $0.1) })
    }

    /// Value for a key in a `.map`, nil otherwise.
    subscript(key: String) -> HLValue? {
        guard case let .map(entries) = self else { return nil }
        return entries.first { $0.key == key }?.value
    }
}

struct HLEntry: Equatable, Sendable {
    let key: String
    let value: HLValue
}

enum HLMsgPackError: Error, Equatable {
    case tooLarge
}

enum HLMsgPack {
    static func encode(_ value: HLValue) throws -> Data {
        var out = Data()
        try write(value, into: &out)
        return out
    }

    private static func write(_ value: HLValue, into out: inout Data) throws {
        switch value {
        case .null:
            out.append(0xc0)
        case .bool(let flag):
            out.append(flag ? 0xc3 : 0xc2)
        case .int(let number):
            if number >= 0 {
                writeUnsigned(UInt64(number), into: &out)
            } else {
                writeNegative(number, into: &out)
            }
        case .uint(let number):
            writeUnsigned(number, into: &out)
        case .string(let text):
            let bytes = Data(text.utf8)
            try writeHeader(count: bytes.count, fix: 0xa0, fixMax: 31, eight: 0xd9, sixteen: 0xda, thirtyTwo: 0xdb, into: &out)
            out.append(bytes)
        case .array(let items):
            try writeHeader(count: items.count, fix: 0x90, fixMax: 15, eight: nil, sixteen: 0xdc, thirtyTwo: 0xdd, into: &out)
            for item in items { try write(item, into: &out) }
        case .map(let entries):
            try writeHeader(count: entries.count, fix: 0x80, fixMax: 15, eight: nil, sixteen: 0xde, thirtyTwo: 0xdf, into: &out)
            for entry in entries {
                try write(.string(entry.key), into: &out)
                try write(entry.value, into: &out)
            }
        }
    }

    private static func writeUnsigned(_ number: UInt64, into out: inout Data) {
        switch number {
        case 0..<0x80:
            out.append(UInt8(number))
        case 0x80..<0x100:
            out.append(0xcc)
            out.append(UInt8(number))
        case 0x100..<0x10000:
            out.append(0xcd)
            appendBigEndian(UInt16(number), into: &out)
        case 0x10000..<0x1_0000_0000:
            out.append(0xce)
            appendBigEndian(UInt32(number), into: &out)
        default:
            out.append(0xcf)
            appendBigEndian(number, into: &out)
        }
    }

    private static func writeNegative(_ number: Int64, into out: inout Data) {
        switch number {
        case -32 ..< 0:
            out.append(UInt8(bitPattern: Int8(number)))
        case -128 ..< -32:
            out.append(0xd0)
            out.append(UInt8(bitPattern: Int8(number)))
        case -32768 ..< -128:
            out.append(0xd1)
            appendBigEndian(UInt16(bitPattern: Int16(number)), into: &out)
        case -2_147_483_648 ..< -32768:
            out.append(0xd2)
            appendBigEndian(UInt32(bitPattern: Int32(number)), into: &out)
        default:
            out.append(0xd3)
            appendBigEndian(UInt64(bitPattern: number), into: &out)
        }
    }

    // swiftlint:disable:next function_parameter_count
    private static func writeHeader(
        count: Int,
        fix: UInt8,
        fixMax: Int,
        eight: UInt8?,
        sixteen: UInt8,
        thirtyTwo: UInt8,
        into out: inout Data
    ) throws {
        if count <= fixMax {
            out.append(fix | UInt8(count))
        } else if let eight, count < 0x100 {
            out.append(eight)
            out.append(UInt8(count))
        } else if count < 0x10000 {
            out.append(sixteen)
            appendBigEndian(UInt16(count), into: &out)
        } else if UInt64(count) < 0x1_0000_0000 {
            out.append(thirtyTwo)
            appendBigEndian(UInt32(count), into: &out)
        } else {
            throw HLMsgPackError.tooLarge
        }
    }

    static func appendBigEndian<T: FixedWidthInteger>(_ value: T, into out: inout Data) {
        withUnsafeBytes(of: value.bigEndian) { out.append(contentsOf: $0) }
    }
}

// MARK: - JSON (for the /exchange body and the review sheet's raw view)

extension HLValue {
    /// Compact JSON with key order preserved. Hyperliquid parses the action
    /// from JSON on submit, so this is what a submission body would carry.
    var jsonString: String {
        switch self {
        case .null: return "null"
        case .bool(let flag): return flag ? "true" : "false"
        case .int(let number): return String(number)
        case .uint(let number): return String(number)
        case .string(let text): return HLValue.quote(text)
        case .array(let items): return "[" + items.map(\.jsonString).joined(separator: ",") + "]"
        case .map(let entries):
            return "{" + entries.map { HLValue.quote($0.key) + ":" + $0.value.jsonString }.joined(separator: ",") + "}"
        }
    }

    private static func quote(_ text: String) -> String {
        var out = "\""
        for scalar in text.unicodeScalars {
            switch scalar {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            case let char where char.value < 0x20:
                out += String(format: "\\u%04x", char.value)
            default:
                out.unicodeScalars.append(scalar)
            }
        }
        return out + "\""
    }
}
