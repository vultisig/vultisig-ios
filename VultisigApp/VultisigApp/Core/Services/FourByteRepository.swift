//
//  FourByteRepository.swift
//  VultisigApp
//
//  Created by Enrique Souza Soares on 26/11/24.
//

import Foundation

struct FunctionCallInfo: Codable {
    let functionName: String
    let fullSignature: String
    let parameters: [String: String] // Key: Value (as string)
    let encodedArguments: String // JSON representation of arguments
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

        let paramTypes = ABIDecoder.splitTypes(paramsString)

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

            let encodedArguments = formatJSON(decodedValues)

            return FunctionCallInfo(
                functionName: functionName,
                fullSignature: textSignature,
                parameters: parameters,
                encodedArguments: encodedArguments
            )

        } catch {
            // Return at least the function name if decoding fails
            return FunctionCallInfo(
                functionName: functionName,
                fullSignature: functionName, // Fallback
                parameters: [:],
                encodedArguments: "[]"
            )
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
            return nil
        }
    }

    private func formatJSON(_ value: Any) -> String {
        // Use JSONSerialization for proper escaping of special characters
        if let arrayValue = value as? [Any] {
            // Convert to JSON-serializable format
            do {
                let data = try JSONSerialization.data(withJSONObject: arrayValue, options: [.prettyPrinted, .sortedKeys])
                return String(data: data, encoding: .utf8) ?? "[]"
            } catch {
                return "[]"
            }
        } else if let stringValue = value as? String {
            // Properly escape the string using JSONSerialization
            do {
                let data = try JSONSerialization.data(withJSONObject: [stringValue], options: [])
                let jsonString = String(data: data, encoding: .utf8) ?? "[\"\"]"
                // Extract the escaped string from the array wrapper
                let trimmed = jsonString.dropFirst().dropLast() // Remove [ and ]
                return String(trimmed)
            } catch {
                return "\"\(value)\""
            }
        } else if let boolValue = value as? Bool {
            return boolValue ? "true" : "false"
        } else {
            return "\"\(value)\""
        }
    }
}
