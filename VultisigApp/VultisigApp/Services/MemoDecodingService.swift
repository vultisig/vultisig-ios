//
//  MemoDecodingService.swift
//  VultisigApp
//

import Foundation
import BigInt

struct ParsedMemoParams {
    let functionSignature: String
    let functionArguments: String
}

final class MemoDecodingService {

    static let shared = MemoDecodingService()

    func decode(memo: String) async throws -> String? {
        guard memo.count >= 8 else { return nil }
        
        let hash = memo.stripHexPrefix().prefix(8)
        let endpoint = Endpoint.fetchMemoInfo(hash: String(hash))

        struct Response: Decodable {
            struct Item: Decodable {
                let text: String
            }
            let items: [Item]
        }

        let (data, _) = try await URLSession.shared.data(from: endpoint)
        let response = try JSONDecoder().decode(Response.self, from: data)

        return response.items.first?.text
    }
    
    /// Comprehensive memo parsing similar to Windows implementation
    func getParsedMemo(memo: String?) async -> ParsedMemoParams? {
        guard let memo = memo, !memo.isEmpty, memo != "0x" else {
            return nil
        }
        
        // Extract function selector (first 10 characters: "0x" + 8 hex chars)
        let hexSignature = String(memo.prefix(10))
        
        do {
            // Query 4byte.directory for function signature
            let url = Endpoint.fetchFourByteSignature(hexSignature: hexSignature)
            
            let (data, _) = try await URLSession.shared.data(from: url)
            
            struct FourByteResponse: Decodable {
                struct Result: Decodable {
                    let text_signature: String
                }
                let results: [Result]
            }
            
            let response = try JSONDecoder().decode(FourByteResponse.self, from: data)
            
            guard let firstResult = response.results.first else {
                return nil
            }
            
            let textSignature = firstResult.text_signature
            
            // Extract function name from signature
            guard let functionName = textSignature.components(separatedBy: "(").first else {
                return nil
            }
            
            // Decode function parameters
            let decodedArguments = decodeFunctionData(memo: memo, functionSignature: textSignature)
            
            return ParsedMemoParams(
                functionSignature: textSignature,
                functionArguments: decodedArguments
            )
            
        } catch {
            print("Error parsing memo: \(error)")
            return nil
        }
    }
    
    /// Decode function data similar to ethers.js decodeFunctionData
    private func decodeFunctionData(memo: String, functionSignature: String) -> String {
        guard memo.count > 10 else {
            return "Invalid memo data"
        }
        
        // Remove function selector (first 10 chars: 0x + 8 hex chars)
        let parametersHex = String(memo.dropFirst(10))
        
        // Convert hex to data
        guard let parametersData = Data(hexString: parametersHex) else {
            return "Invalid hex data"
        }
        
        // Basic ABI decoding - this is a simplified version
        return decodeABIParameters(data: parametersData, signature: functionSignature)
    }
    
    /// Basic ABI parameter decoding
    private func decodeABIParameters(data: Data, signature: String) -> String {
        var result: [String: Any] = [:]
        var offset = 0
        
        // Extract parameter types from signature
        guard let paramTypesString = signature.components(separatedBy: "(").last?.components(separatedBy: ")").first else {
            return "Could not parse function signature"
        }
        
        let paramTypes = paramTypesString.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        
        for (index, paramType) in paramTypes.enumerated() {
            if offset + 32 > data.count {
                break
            }
            
            let paramData = data.subdata(in: offset..<offset+32)
            let decodedValue = decodeParameter(data: paramData, type: paramType)
            result["param\(index)"] = decodedValue
            offset += 32
        }
        
        // Convert to JSON string for display
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: result, options: .prettyPrinted)
            return String(data: jsonData, encoding: .utf8) ?? "Could not format parameters"
        } catch {
            return "Error formatting parameters: \(error)"
        }
    }
    
    /// Decode individual parameter based on type
    private func decodeParameter(data: Data, type: String) -> Any {
        switch type {
        case "address":
            // Address is the last 20 bytes
            let addressData = data.suffix(20)
            return "0x" + addressData.map { String(format: "%02x", $0) }.joined()
            
        case let t where t.hasPrefix("uint"):
            // Unsigned integer
            let value = BigUInt(data)
            return value.description
            
        case let t where t.hasPrefix("int"):
            // Signed integer (simplified)
            let value = BigUInt(data)
            return value.description
            
        case "bool":
            // Boolean (last byte)
            return data.last != 0
            
        case let t where t.hasPrefix("bytes"):
            // Bytes type
            return "0x" + data.map { String(format: "%02x", $0) }.joined()
            
        default:
            // Default to hex representation
            return "0x" + data.map { String(format: "%02x", $0) }.joined()
        }
    }
}
