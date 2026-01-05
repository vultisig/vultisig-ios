//
//  CosmosSignDirectParser.swift
//  VultisigApp
//
//  Simple parser for extracting memo and fee from Cosmos signDirect protobuf bytes
//  Based on cosmos-sdk/proto/cosmos/tx/v1beta1/tx.proto
//

import Foundation
import WalletCore

/// Lightweight parser for Cosmos signDirect transaction components
enum CosmosSignDirectParser {

    /// Extracts memo from TxBody protobuf bytes
    /// TxBody field 2 is memo (string)
    static func extractMemo(from bodyBytes: Data) -> String? {
        var parser = ProtobufFieldParser(data: bodyBytes)

        while let (fieldNumber, value) = parser.readField() {
            if fieldNumber == 2, case .lengthDelimited(let data) = value {
                return String(data: data, encoding: .utf8)
            }
        }

        return nil
    }

    /// Extracts messages from TxBody protobuf bytes
    /// TxBody field 1 is repeated Any (messages)
    /// Each Any has: field 1 = type_url (string), field 2 = value (bytes)
    static func extractMessages(from bodyBytes: Data) -> [(typeUrl: String, value: String)] {
        var parser = ProtobufFieldParser(data: bodyBytes)
        var messages: [(typeUrl: String, value: String)] = []

        while let (fieldNumber, value) = parser.readField() {
            if fieldNumber == 1, case .lengthDelimited(let msgData) = value {
                if let msg = parseAnyMessage(from: msgData) {
                    messages.append(msg)
                }
            }
        }

        return messages
    }

    /// Parses Any message (type_url + value)
    private static func parseAnyMessage(from data: Data) -> (typeUrl: String, value: String)? {
        var parser = ProtobufFieldParser(data: data)
        var typeUrl = ""
        var valueData = Data()

        while let (fieldNumber, value) = parser.readField() {
            switch fieldNumber {
            case 1: // type_url (string)
                if case .lengthDelimited(let data) = value {
                    typeUrl = String(data: data, encoding: .utf8) ?? ""
                }
            case 2: // value (bytes)
                if case .lengthDelimited(let data) = value {
                    valueData = data
                }
            default:
                break
            }
        }

        guard !typeUrl.isEmpty else { return nil }
        return (typeUrl: typeUrl, value: valueData.base64EncodedString())
    }

    /// Extracts fee information from AuthInfo protobuf bytes
    /// AuthInfo field 2 is Fee message
    /// Fee field 1 is repeated Coin, field 2 is gas_limit (uint64)
    static func extractFee(from authInfoBytes: Data) -> (gasLimit: UInt64, amounts: [(denom: String, amount: String)])? {
        var parser = ProtobufFieldParser(data: authInfoBytes)

        // Find field 2 (Fee message) in AuthInfo
        while let (fieldNumber, value) = parser.readField() {
            if fieldNumber == 2, case .lengthDelimited(let feeData) = value {
                return parseFee(from: feeData)
            }
        }

        return nil
    }

    /// Extracts sequence from AuthInfo protobuf bytes
    /// AuthInfo field 1 is repeated SignerInfo, SignerInfo field 3 is sequence (uint64)
    static func extractSequence(from authInfoBytes: Data) -> UInt64? {
        var parser = ProtobufFieldParser(data: authInfoBytes)

        // Find field 1 (first SignerInfo) in AuthInfo
        while let (fieldNumber, value) = parser.readField() {
            if fieldNumber == 1, case .lengthDelimited(let signerInfoData) = value {
                return parseSequenceFromSignerInfo(from: signerInfoData)
            }
        }

        return nil
    }

    /// Parses sequence from SignerInfo message
    private static func parseSequenceFromSignerInfo(from data: Data) -> UInt64? {
        var parser = ProtobufFieldParser(data: data)

        while let (fieldNumber, value) = parser.readField() {
            if fieldNumber == 3, case .varint(let sequence) = value {
                return sequence
            }
        }

        return nil
    }

    /// Parses Fee message
    private static func parseFee(from data: Data) -> (gasLimit: UInt64, amounts: [(denom: String, amount: String)])? {
        var parser = ProtobufFieldParser(data: data)
        var gasLimit: UInt64 = 0
        var amounts: [(String, String)] = []

        while let (fieldNumber, value) = parser.readField() {
            switch fieldNumber {
            case 1: // amount (repeated Coin)
                if case .lengthDelimited(let coinData) = value,
                   let coin = parseCoin(from: coinData) {
                    amounts.append(coin)
                }
            case 2: // gas_limit (uint64)
                if case .varint(let value) = value {
                    gasLimit = value
                }
            default:
                break
            }
        }

        return (gasLimit: gasLimit, amounts: amounts)
    }

    /// Parses Coin message
    private static func parseCoin(from data: Data) -> (denom: String, amount: String)? {
        var parser = ProtobufFieldParser(data: data)
        var denom = ""
        var amount = ""

        while let (fieldNumber, value) = parser.readField() {
            switch fieldNumber {
            case 1: // denom (string)
                if case .lengthDelimited(let data) = value {
                    denom = String(data: data, encoding: .utf8) ?? ""
                }
            case 2: // amount (string)
                if case .lengthDelimited(let data) = value {
                    amount = String(data: data, encoding: .utf8) ?? ""
                }
            default:
                break
            }
        }

        return denom.isEmpty ? nil : (denom: denom, amount: amount)
    }
}

/// Simple protobuf wire format parser
private struct ProtobufFieldParser {
    let data: Data
    var index: Int = 0

    enum FieldValue {
        case varint(UInt64)
        case lengthDelimited(Data)
        case fixed64(UInt64)
        case fixed32(UInt32)
    }

    mutating func readField() -> (fieldNumber: Int, value: FieldValue)? {
        guard let tag = readVarint() else { return nil }

        let fieldNumber = Int(tag >> 3)
        let wireType = Int(tag & 0x7)

        switch wireType {
        case 0: // Varint
            guard let value = readVarint() else { return nil }
            return (fieldNumber, .varint(value))

        case 1: // 64-bit
            guard let value = readFixed64() else { return nil }
            return (fieldNumber, .fixed64(value))

        case 2: // Length-delimited
            guard let length = readVarint(),
                  let data = readBytes(count: Int(length)) else { return nil }
            return (fieldNumber, .lengthDelimited(data))

        case 5: // 32-bit
            guard let value = readFixed32() else { return nil }
            return (fieldNumber, .fixed32(value))

        default:
            return nil
        }
    }

    private mutating func readVarint() -> UInt64? {
        var result: UInt64 = 0
        var shift: UInt64 = 0

        for _ in 0..<10 {
            guard index < data.count else { return nil }
            let byte = data[index]
            index += 1

            result |= UInt64(byte & 0x7F) << shift
            if (byte & 0x80) == 0 {
                return result
            }
            shift += 7
        }

        return nil
    }

    private mutating func readFixed64() -> UInt64? {
        guard index + 8 <= data.count else { return nil }
        let value = data.subdata(in: index..<index+8).withUnsafeBytes {
            $0.load(as: UInt64.self)
        }
        index += 8
        return value
    }

    private mutating func readFixed32() -> UInt32? {
        guard index + 4 <= data.count else { return nil }
        let value = data.subdata(in: index..<index+4).withUnsafeBytes {
            $0.load(as: UInt32.self)
        }
        index += 4
        return value
    }

    private mutating func readBytes(count: Int) -> Data? {
        guard index + count <= data.count else { return nil }
        let result = data.subdata(in: index..<index+count)
        index += count
        return result
    }
}
