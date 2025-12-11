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

struct MemoDecodingService {

    static let shared = MemoDecodingService()

    func decode(memo: String) async throws -> String? {
        // Legacy support or simple string return
        guard let info = try await FourByteRepository.shared.decode(memo: memo) else {
            return nil
        }
        return info.functionName
    }
    
    /// Comprehensive memo parsing using FourByteRepository
    func getParsedMemo(memo: String?) async -> ParsedMemoParams? {
        guard let memo = memo, !memo.isEmpty, memo != "0x" else {
            return nil
        }
        
        do {
            guard let info = try await FourByteRepository.shared.decode(memo: memo) else {
                return nil
            }
            
            // Convert parameters dictionary to a formatted JSON-like string for display
            let sortedKeys = info.parameters.keys.sorted()
            var argsString = ""
            
            if !info.parameters.isEmpty {
                argsString = "{\n"
                for key in sortedKeys {
                    if let value = info.parameters[key] {
                        argsString += "  \"\(key)\": \"\(value)\",\n"
                    }
                }
                // Remove trailing comma and newline
                if argsString.hasSuffix(",\n") {
                    argsString = String(argsString.dropLast(2))
                    argsString += "\n"
                }
                argsString += "}"
            } else {
                argsString = "{}"
            }
            
            return ParsedMemoParams(
                functionSignature: info.fullSignature,
                functionArguments: info.encodedArguments
            )
            
        } catch {
            return nil
        }
    }
}

