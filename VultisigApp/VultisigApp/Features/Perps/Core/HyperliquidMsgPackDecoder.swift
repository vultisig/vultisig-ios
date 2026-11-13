//
//  HyperliquidMsgPackDecoder.swift
//  VultisigApp
//
//  The inverse of `HLMsgPack.encode`, for the co-signer: it decodes the raw
//  action bytes an initiator sends (`HyperliquidActionPreimage.actionMsgpack`)
//  so the joiner can show what it signs. Strict on purpose:
//    - only the types `HLValue` models (no floats, bin or ext),
//    - map keys must be strings,
//    - no trailing bytes, bounded depth and lengths,
//    - `decodeCanonical` also requires that re-encoding gives the same bytes,
//      so a non-minimal encoding the venue would re-serialise differently
//      (and therefore hash differently) is refused.
//

import Foundation

enum HLMsgPackDecodeError: Error, Equatable {
    case truncated
    case unsupportedType(UInt8)
    case nonStringKey
    case trailingBytes
    case tooDeep
    case tooLarge
    case invalidUTF8
    /// Decodes, but `HLMsgPack.encode` would not produce these bytes.
    case nonCanonical
}

enum HLMsgPackDecoder {
    static let maxDepth = 16
    /// A Hyperliquid action is a few hundred bytes; a batch of orders a few KB.
    static let maxBytes = 64 * 1024
    static let maxCount = 1_024

    /// Decodes, then refuses any encoding `HLMsgPack.encode` would not produce.
    static func decodeCanonical(_ data: Data) throws -> HLValue {
        let value = try decode(data)
        guard try HLMsgPack.encode(value) == data else { throw HLMsgPackDecodeError.nonCanonical }
        return value
    }

    static func decode(_ data: Data) throws -> HLValue {
        guard data.count <= maxBytes else { throw HLMsgPackDecodeError.tooLarge }
        var reader = Reader(bytes: [UInt8](data))
        let value = try reader.value(depth: 0)
        guard reader.isAtEnd else { throw HLMsgPackDecodeError.trailingBytes }
        return value
    }

    private struct Reader {
        let bytes: [UInt8]
        var offset = 0

        var isAtEnd: Bool { offset == bytes.count }

        mutating func byte() throws -> UInt8 {
            guard offset < bytes.count else { throw HLMsgPackDecodeError.truncated }
            defer { offset += 1 }
            return bytes[offset]
        }

        mutating func take(_ count: Int) throws -> ArraySlice<UInt8> {
            guard count >= 0, bytes.count - offset >= count else { throw HLMsgPackDecodeError.truncated }
            defer { offset += count }
            return bytes[offset ..< offset + count]
        }

        mutating func bigEndian(_ width: Int) throws -> UInt64 {
            try take(width).reduce(UInt64(0)) { ($0 << 8) | UInt64($1) }
        }

        mutating func value(depth: Int) throws -> HLValue {
            guard depth <= HLMsgPackDecoder.maxDepth else { throw HLMsgPackDecodeError.tooDeep }
            let head = try byte()
            switch head {
            case 0x00...0x7f: return .int(Int64(head))
            case 0x80...0x8f: return try map(count: Int(head & 0x0f), depth: depth)
            case 0x90...0x9f: return try array(count: Int(head & 0x0f), depth: depth)
            case 0xa0...0xbf: return try string(count: Int(head & 0x1f))
            case 0xc0: return .null
            case 0xc2: return .bool(false)
            case 0xc3: return .bool(true)
            case 0xcc: return unsigned(try bigEndian(1))
            case 0xcd: return unsigned(try bigEndian(2))
            case 0xce: return unsigned(try bigEndian(4))
            case 0xcf: return unsigned(try bigEndian(8))
            case 0xd0: return .int(Int64(Int8(truncatingIfNeeded: try bigEndian(1))))
            case 0xd1: return .int(Int64(Int16(truncatingIfNeeded: try bigEndian(2))))
            case 0xd2: return .int(Int64(Int32(truncatingIfNeeded: try bigEndian(4))))
            case 0xd3: return .int(Int64(bitPattern: try bigEndian(8)))
            case 0xd9: return try string(count: Int(try bigEndian(1)))
            case 0xda: return try string(count: Int(try bigEndian(2)))
            case 0xdb: return try string(count: Int(try bigEndian(4)))
            case 0xdc: return try array(count: Int(try bigEndian(2)), depth: depth)
            case 0xdd: return try array(count: Int(try bigEndian(4)), depth: depth)
            case 0xde: return try map(count: Int(try bigEndian(2)), depth: depth)
            case 0xdf: return try map(count: Int(try bigEndian(4)), depth: depth)
            case 0xe0...0xff: return .int(Int64(Int8(bitPattern: head)))
            default: throw HLMsgPackDecodeError.unsupportedType(head)
            }
        }

        /// The builders use `.int` for every non-negative value that fits, so
        /// decoded values compare equal to what `HLActions` would build.
        private func unsigned(_ number: UInt64) -> HLValue {
            number <= UInt64(Int64.max) ? .int(Int64(number)) : .uint(number)
        }

        private mutating func string(count: Int) throws -> HLValue {
            guard let text = String(bytes: try take(count), encoding: .utf8) else { throw HLMsgPackDecodeError.invalidUTF8 }
            return .string(text)
        }

        private mutating func array(count: Int, depth: Int) throws -> HLValue {
            guard count <= HLMsgPackDecoder.maxCount else { throw HLMsgPackDecodeError.tooLarge }
            var items: [HLValue] = []
            items.reserveCapacity(count)
            for _ in 0 ..< count { items.append(try value(depth: depth + 1)) }
            return .array(items)
        }

        private mutating func map(count: Int, depth: Int) throws -> HLValue {
            guard count <= HLMsgPackDecoder.maxCount else { throw HLMsgPackDecodeError.tooLarge }
            var entries: [HLEntry] = []
            entries.reserveCapacity(count)
            for _ in 0 ..< count {
                guard case .string(let key) = try value(depth: depth + 1) else { throw HLMsgPackDecodeError.nonStringKey }
                entries.append(HLEntry(key: key, value: try value(depth: depth + 1)))
            }
            return .map(entries)
        }
    }
}
