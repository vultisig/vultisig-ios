//
//  FourByteRepository.swift
//  VultisigApp
//
//  Created by Enrique Souza Soares on 26/11/24.
//

import Foundation

struct FunctionCallInfo: Codable {
    let functionName: String
    let parameters: [String: String] // Key: Value (as string)
}

struct FourByteRepository {
    
    static let shared = FourByteRepository()
    
    private init() {}
    
    func decode(memo: String) async throws -> FunctionCallInfo? {
        guard memo.count >= 10, memo.hasPrefix("0x") else { return nil }
        
        // Extract function selector (first 4 bytes = 8 hex chars)
        let hexSignature = String(memo.prefix(10))
        let dataHex = String(memo.dropFirst(10))
        
        // 1. Fetch Signature
        guard let textSignature = await fetchSignature(hex: hexSignature) else {
            return nil
        }
        
        // 2. Parse Signature to get function name and param types
        // Example: "transfer(address,uint256)" -> name: "transfer", types: ["address", "uint256"]
        guard let nameEndIndex = textSignature.firstIndex(of: "("),
              let paramsEndIndex = textSignature.lastIndex(of: ")") else {
            return nil
        }
        
        let functionName = String(textSignature[..<nameEndIndex])
        let paramsString = String(textSignature[textSignature.index(after: nameEndIndex)..<paramsEndIndex])
        
        let paramTypes = paramsString.isEmpty ? [] : paramsString.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        
        // 3. Decode Arguments
        do {
            let decodedValues = try ABIDecoder.decode(types: paramTypes, data: dataHex)
            
            var parameters: [String: String] = [:]
            for (index, value) in decodedValues.enumerated() {
                let type = paramTypes[index]
                // Try to give a meaningful name if possible, otherwise use type + index
                let key = "Param \(index + 1) (\(type))"
                parameters[key] = "\(value)"
            }
            
            return FunctionCallInfo(functionName: functionName, parameters: parameters)
            
        } catch {
            print("Failed to decode ABI data: \(error)")
            // Return at least the function name if decoding fails
            return FunctionCallInfo(functionName: functionName, parameters: [:])
        }
    }
    
    private func fetchSignature(hex: String) async -> String? {
        let url = Endpoint.fetchFourByteSignature(hexSignature: hex)
        
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            
            struct FourByteResponse: Decodable {
                struct Result: Decodable {
                    let text_signature: String
                }
                let results: [Result]
            }
            
            let response = try JSONDecoder().decode(FourByteResponse.self, from: data)
            // Return the first matching signature
            return response.results.first?.text_signature
            
        } catch {
            print("Error fetching 4byte signature: \(error)")
            return nil
        }
    }
}
