//
//  HLJSONKeyScanner.swift
//  VultisigApp
//
//  Finds duplicate keys in a JSON document. The co-sign check reads typed
//  data with `JSONSerialization`, while the digest keysign signs comes from
//  WalletCore's `EthereumAbi.encodeTyped` (a different parser). With a
//  duplicated `domain` or `primaryType` the two could resolve different
//  values, so the check would see "not Hyperliquid" while the signed digest
//  is an `Exchange`/`Agent` one. Typed data with duplicate keys is refused.
//  Keys are compared after unescaping, as both parsers do.
//

import Foundation

enum HLJSONKeyScanner {
    enum ScanError: Error, Equatable {
        case invalidJSON
    }

    static let maxDepth = 64

    /// True when any object in `text` repeats a key. Throws on malformed JSON.
    static func hasDuplicateKeys(_ text: String) throws -> Bool {
        var scanner = Scanner(scalars: Array(text.unicodeScalars))
        scanner.skipWhitespace()
        let duplicate = try scanner.value(depth: 0)
        scanner.skipWhitespace()
        guard scanner.isAtEnd else { throw ScanError.invalidJSON }
        return duplicate
    }

    private struct Scanner {
        let scalars: [Unicode.Scalar]
        var index = 0

        var isAtEnd: Bool { index >= scalars.count }

        mutating func skipWhitespace() {
            while index < scalars.count, [" ", "\n", "\r", "\t"].contains(scalars[index]) { index += 1 }
        }

        mutating func expect(_ scalar: Unicode.Scalar) throws {
            guard index < scalars.count, scalars[index] == scalar else { throw ScanError.invalidJSON }
            index += 1
        }

        /// Returns whether a duplicate key was found anywhere inside the value.
        mutating func value(depth: Int) throws -> Bool {
            guard depth <= HLJSONKeyScanner.maxDepth, index < scalars.count else { throw ScanError.invalidJSON }
            switch scalars[index] {
            case "{": return try object(depth: depth)
            case "[": return try array(depth: depth)
            case "\"":
                _ = try string()
                return false
            default:
                try literal()
                return false
            }
        }

        private mutating func object(depth: Int) throws -> Bool {
            try expect("{")
            var keys = Set<String>()
            var duplicate = false
            skipWhitespace()
            if index < scalars.count, scalars[index] == "}" {
                index += 1
                return false
            }
            while true {
                skipWhitespace()
                let key = try string()
                if !keys.insert(key).inserted { duplicate = true }
                skipWhitespace()
                try expect(":")
                skipWhitespace()
                if try value(depth: depth + 1) { duplicate = true }
                skipWhitespace()
                guard index < scalars.count else { throw ScanError.invalidJSON }
                if scalars[index] == "," {
                    index += 1
                    continue
                }
                try expect("}")
                return duplicate
            }
        }

        private mutating func array(depth: Int) throws -> Bool {
            try expect("[")
            var duplicate = false
            skipWhitespace()
            if index < scalars.count, scalars[index] == "]" {
                index += 1
                return false
            }
            while true {
                skipWhitespace()
                if try value(depth: depth + 1) { duplicate = true }
                skipWhitespace()
                guard index < scalars.count else { throw ScanError.invalidJSON }
                if scalars[index] == "," {
                    index += 1
                    continue
                }
                try expect("]")
                return duplicate
            }
        }

        /// A string, unescaped.
        private mutating func string() throws -> String {
            try expect("\"")
            var out = String.UnicodeScalarView()
            while index < scalars.count {
                let scalar = scalars[index]
                index += 1
                switch scalar {
                case "\"":
                    return String(out)
                case "\\":
                    guard index < scalars.count else { throw ScanError.invalidJSON }
                    let escaped = scalars[index]
                    index += 1
                    switch escaped {
                    case "\"", "\\", "/": out.append(escaped)
                    case "b": out.append("\u{08}")
                    case "f": out.append("\u{0C}")
                    case "n": out.append("\n")
                    case "r": out.append("\r")
                    case "t": out.append("\t")
                    case "u": out.append(try unicodeEscape())
                    default: throw ScanError.invalidJSON
                    }
                default:
                    guard scalar.value >= 0x20 else { throw ScanError.invalidJSON }
                    out.append(scalar)
                }
            }
            throw ScanError.invalidJSON
        }

        private mutating func hex4() throws -> UInt32 {
            guard scalars.count - index >= 4 else { throw ScanError.invalidJSON }
            let text = String(String.UnicodeScalarView(scalars[index ..< index + 4]))
            guard let value = UInt32(text, radix: 16) else { throw ScanError.invalidJSON }
            index += 4
            return value
        }

        private mutating func unicodeEscape() throws -> Unicode.Scalar {
            let high = try hex4()
            if (0xD800...0xDBFF).contains(high) {
                try expect("\\")
                try expect("u")
                let low = try hex4()
                guard (0xDC00...0xDFFF).contains(low),
                      let scalar = Unicode.Scalar(0x10000 + ((high - 0xD800) << 10) + (low - 0xDC00)) else { throw ScanError.invalidJSON }
                return scalar
            }
            guard let scalar = Unicode.Scalar(high) else { throw ScanError.invalidJSON }
            return scalar
        }

        /// Numbers, true, false, null: consumed, not interpreted.
        private mutating func literal() throws {
            let start = index
            while index < scalars.count, !([",", "}", "]", " ", "\n", "\r", "\t"] as [Unicode.Scalar]).contains(scalars[index]) {
                index += 1
            }
            let text = String(String.UnicodeScalarView(scalars[start ..< index]))
            guard ["true", "false", "null"].contains(text) || Double(text) != nil else { throw ScanError.invalidJSON }
        }
    }
}
