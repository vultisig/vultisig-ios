//
//  ABIDecoder.swift
//  VultisigApp
//
//  Created by Enrique Souza Soares on 26/11/24.
//

import Foundation
import BigInt

struct ABIDecoder {

    enum DecodingError: Error {
        case invalidHexData
        case indexOutOfBounds
        case unsupportedType(String)
        case decodingFailed(String)
        case offsetOutOfRange(String)
    }

    /// Safely converts BigUInt to Int, throwing an error if the value is too large
    private static func safeIntConversion(_ value: BigUInt, context: String) throws -> Int {
        guard value <= Int.max else {
            throw DecodingError.offsetOutOfRange("\(context): value \(value) exceeds Int.max")
        }
        return Int(value)
    }

    /// Decodes ABI encoded data based on the provided types
    /// - Parameters:
    ///   - types: List of parameter types (e.g., ["address", "uint256"])
    ///   - data: The hex string data (without function selector)
    /// - Returns: A list of decoded values as Any
    static func decode(types: [String], data: String) throws -> [Any] {
        let hexData = data.stripHexPrefix()
        guard let dataBytes = Data(hexString: hexData) else {
            throw DecodingError.invalidHexData
        }

        var decodedValues: [Any] = []
        var offset = 0

        for type in types {
            let (value, newOffset) = try decodeType(type: type, data: dataBytes, offset: offset)
            decodedValues.append(value)
            offset = newOffset
        }

        return decodedValues
    }

    private static func decodeType(type: String, data: Data, offset: Int) throws -> (Any, Int) {

        // Handle dynamic types (string, bytes, arrays, dynamic tuples)
        let isDynamic = isDynamicType(type)

        if isDynamic {
            // Read the offset pointer
            guard offset + 32 <= data.count else { throw DecodingError.indexOutOfBounds }
            let pointerData = data.subdata(in: offset..<offset+32)
            let dataOffset = try safeIntConversion(BigUInt(pointerData), context: "Dynamic type pointer at offset \(offset)")

            if type == "string" {
                let stringValue = try decodeString(data: data, offset: dataOffset)
                return (stringValue, offset + 32)
            } else if type == "bytes" {
                let bytesValue = try decodeBytes(data: data, offset: dataOffset)
                return (bytesValue, offset + 32)
            } else if type.hasSuffix("[]") {
                // Basic support for dynamic arrays (e.g. address[])
                let baseType = String(type.dropLast(2))
                let arrayValue = try decodeArray(baseType: baseType, data: data, offset: dataOffset)
                return (arrayValue, offset + 32)
            } else if type.hasPrefix("(") && type.hasSuffix(")") {
                // Dynamic tuple (because it contains a dynamic type)
                let innerTypes = parseTupleTypes(type)
                let tupleValue = try decodeTuple(types: innerTypes, data: data, offset: dataOffset)
                return (tupleValue, offset + 32)
            }
        }

        // Handle static tuples (in place)
        if type.hasPrefix("(") && type.hasSuffix(")") {
             let innerTypes = parseTupleTypes(type)
             let (tupleValue, newOffset) = try decodeTupleInPlace(types: innerTypes, data: data, offset: offset)
             return (tupleValue, newOffset)
        }

        // Handle static types
        if type == "address" {
            guard offset + 32 <= data.count else {
                throw DecodingError.indexOutOfBounds
            }
            let slice = data.subdata(in: offset..<offset+32)
            // Address is the last 20 bytes of the 32-byte word
            let addressData = slice.suffix(20)
            let address = "0x" + addressData.map { String(format: "%02x", $0) }.joined()
            return (address, offset + 32)
        } else if type.hasPrefix("uint") {
            guard offset + 32 <= data.count else {
                throw DecodingError.indexOutOfBounds
            }
            let slice = data.subdata(in: offset..<offset+32)
            let value = BigUInt(slice)
            return (value.description, offset + 32)
        } else if type.hasPrefix("int") {
            guard offset + 32 <= data.count else {
                 throw DecodingError.indexOutOfBounds
            }
            let slice = data.subdata(in: offset..<offset+32)
            let unsignedValue = BigUInt(slice)

            // Check if the most significant bit is set (negative number in two's complement)
            let isNegative = (slice.first ?? 0) & 0x80 != 0

            if isNegative {
                // Convert from two's complement: signedValue = unsignedValue - 2^256
                let maxValue = BigInt(1) << (slice.count * 8)
                let signedValue = BigInt(unsignedValue) - maxValue
                return (signedValue.description, offset + 32)
            } else {
                return (BigInt(unsignedValue).description, offset + 32)
            }
        } else if type == "bool" {
            guard offset + 32 <= data.count else {
                throw DecodingError.indexOutOfBounds
            }
            let slice = data.subdata(in: offset..<offset+32)
            let value = slice.last != 0
            return (value, offset + 32)
        } else if type.hasPrefix("bytes") {
             // Static bytes like bytes32
             guard offset + 32 <= data.count else {
                throw DecodingError.indexOutOfBounds
             }
             let slice = data.subdata(in: offset..<offset+32)
             return ("0x" + slice.map { String(format: "%02x", $0) }.joined(), offset + 32)
        }

        throw DecodingError.unsupportedType(type)
    }

    private static func decodeString(data: Data, offset: Int) throws -> String {
        guard offset + 32 <= data.count else { throw DecodingError.indexOutOfBounds }

        // Read length
        let lengthData = data.subdata(in: offset..<offset+32)
        let length = try safeIntConversion(BigUInt(lengthData), context: "String length at offset \(offset)")

        guard offset + 32 + length <= data.count else { throw DecodingError.indexOutOfBounds }

        let stringData = data.subdata(in: offset+32..<offset+32+length)
        guard let string = String(data: stringData, encoding: .utf8) else {
            throw DecodingError.decodingFailed("Invalid UTF-8 string")
        }

        return string
    }

    private static func decodeBytes(data: Data, offset: Int) throws -> String {
        guard offset + 32 <= data.count else { throw DecodingError.indexOutOfBounds }

        // Read length
        let lengthData = data.subdata(in: offset..<offset+32)
        let length = try safeIntConversion(BigUInt(lengthData), context: "Bytes length at offset \(offset)")

        guard offset + 32 + length <= data.count else { throw DecodingError.indexOutOfBounds }

        let bytesData = data.subdata(in: offset+32..<offset+32+length)
        return "0x" + bytesData.map { String(format: "%02x", $0) }.joined()
    }

    private static func decodeArray(baseType: String, data: Data, offset: Int) throws -> [Any] {
        guard offset + 32 <= data.count else { throw DecodingError.indexOutOfBounds }

        // Read array length
        let lengthData = data.subdata(in: offset..<offset+32)
        let length = try safeIntConversion(BigUInt(lengthData), context: "Array length at offset \(offset)")

        var result: [Any] = []
        let arrayDataStart = offset + 32 // Position right after the length
        let elementIsDynamic = isDynamicType(baseType)

        for i in 0..<length {
            let slotOffset = arrayDataStart + (i * 32)

            if elementIsDynamic {
                // For dynamic types, the slot contains a relative pointer
                guard slotOffset + 32 <= data.count else { throw DecodingError.indexOutOfBounds }
                let pointerData = data.subdata(in: slotOffset..<slotOffset+32)
                let relativePointer = try safeIntConversion(BigUInt(pointerData), context: "Array element pointer at slot \(i), offset \(slotOffset)")
                let elementAbsoluteOffset = arrayDataStart + relativePointer

                let (value, _) = try decodeType(type: baseType, data: data, offset: elementAbsoluteOffset)
                result.append(value)
            } else {
                // For static types, decode in place
                let (value, _) = try decodeType(type: baseType, data: data, offset: slotOffset)
                result.append(value)
            }
        }

        return result
    }

    // MARK: - Tuple Helpers

    private static func decodeTuple(types: [String], data: Data, offset: Int) throws -> [Any] {
        let (values, _) = try decodeTupleInPlace(types: types, data: data, offset: offset)
        return values
    }

    private static func decodeTupleInPlace(types: [String], data: Data, offset: Int) throws -> ([Any], Int) {
        var result: [Any] = []
        var currentOffset = offset

        for type in types {
             let (value, newOffset) = try decodeType(type: type, data: data, offset: currentOffset)
             result.append(value)
             currentOffset = newOffset
        }
        return (result, currentOffset)
    }

    private static func isDynamicType(_ type: String) -> Bool {
        if type == "string" || type == "bytes" || type.hasSuffix("[]") {
            return true
        }
        if type.hasPrefix("(") && type.hasSuffix(")") {
             // Recursive check: Tuple is dynamic if ANY component is dynamic
             let innerTypes = parseTupleTypes(type)
             return innerTypes.contains { isDynamicType($0) }
        }
        return false
    }

    private static func parseTupleTypes(_ type: String) -> [String] {
        guard type.hasPrefix("(") && type.hasSuffix(")") else { return [] }
        let content = String(type.dropFirst().dropLast())
        return splitTypes(content)
    }

    static func splitTypes(_ content: String) -> [String] {
        var types: [String] = []
        var currentType = ""
        var depth = 0

        for char in content {
            if char == "(" {
                depth += 1
            } else if char == ")" {
                depth -= 1
            }

            if char == "," && depth == 0 {
                types.append(currentType.trimmingCharacters(in: .whitespaces))
                currentType = ""
            } else {
                currentType.append(char)
            }
        }
        if !currentType.isEmpty {
            types.append(currentType.trimmingCharacters(in: .whitespaces))
        }
        return types
    }
}
