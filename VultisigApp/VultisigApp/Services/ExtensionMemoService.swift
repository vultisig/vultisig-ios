//
//  ExtensionMemoService.swift
//  VultisigApp
//
//  Created by System on 2025-01-16.
//

import Foundation

final class ExtensionMemoService {

    static let shared = ExtensionMemoService()
    
    private init() {}

    func decodeExtensionMemo(_ memo: String) -> String? {
        // Check if this is a Vultisig Extension memo format
        guard isExtensionMemo(memo) else {
            print("🔍 ExtensionMemoService: Memo '\(memo.prefix(50))...' is not recognized as extension memo")
            return nil
        }
        
        print("🔍 ExtensionMemoService: Processing extension memo: '\(memo.prefix(50))...'")
        print("📝 ExtensionMemoService: Original memo text: '\(memo)'")
        
        // Handle different extension memo formats - prioritize JSON over text patterns
        if let decodedContract = decodeContractInteraction(memo) {
            print("✅ ExtensionMemoService: Successfully decoded using CONTRACT INTERACTION method")
            print("🎯 ExtensionMemoService: Final decoded result: '\(decodedContract)'")
            return decodedContract
        }
        
        if let decodedAction = decodeActionMemo(memo) {
            print("✅ ExtensionMemoService: Successfully decoded using ACTION MEMO method")
            print("🎯 ExtensionMemoService: Final decoded result: '\(decodedAction)'")
            return decodedAction
        }
        
        if let decodedTransaction = decodeTransactionMemo(memo) {
            print("✅ ExtensionMemoService: Successfully decoded using TRANSACTION MEMO method")
            print("🎯 ExtensionMemoService: Final decoded result: '\(decodedTransaction)'")
            return decodedTransaction
        }
        
        print("❌ ExtensionMemoService: Failed to decode memo despite being recognized as extension memo")
        return nil
    }

    
    private func isExtensionMemo(_ memo: String) -> Bool {
        // Extension memos typically start with specific patterns or contain encoded data
        // Common patterns for extension memos:
        // - Hex encoded data starting with 0x
        // - Base64 encoded data
        // - JSON-like structures
        // - Contract interaction patterns
        
        if memo.hasPrefix("0x") && memo.count > 10 {
            return true
        }
        
        // Check for common dApp interaction patterns
        if memo.contains("approve") || memo.contains("transfer") || memo.contains("swap") {
            return true
        }
        
        // Check for encoded JSON or structured data
        if memo.contains("{") && memo.contains("}") {
            return true
        }
        
        // Check for base64-like patterns (common in extension memos)
        if isBase64Like(memo) {
            return true
        }
        
        return false
    }
    
    private func decodeActionMemo(_ memo: String) -> String? {
        print("🔍 ExtensionMemoService: Attempting ACTION MEMO decoding...")
        
        // Decode common action-based memos
        if memo.hasPrefix("0x") {
            print("🔍 ExtensionMemoService: Detected hex format, using HEX MEMO decoding")
            return decodeHexMemo(memo)
        }
        
        // Handle specific action patterns
        if memo.lowercased().contains("approve") {
            print("🔍 ExtensionMemoService: Detected approval pattern, using APPROVAL DETAILS extraction")
            return extractApprovalDetails(memo)
        }
        
        if memo.lowercased().contains("transfer") {
            print("🔍 ExtensionMemoService: Detected transfer pattern, using TRANSFER DETAILS extraction")
            return extractTransferDetails(memo)
        }
        
        if memo.lowercased().contains("swap") {
            print("🔍 ExtensionMemoService: Detected swap pattern, using SWAP DETAILS extraction")
            return extractSwapDetails(memo)
        }
        
        print("❌ ExtensionMemoService: No action patterns matched in ACTION MEMO decoding")
        return nil
    }
    
    private func decodeContractInteraction(_ memo: String) -> String? {
        print("🔍 ExtensionMemoService: Attempting CONTRACT INTERACTION decoding...")
        
        // Handle contract interaction memos
        if memo.contains("{") && memo.contains("}") {
            print("🔍 ExtensionMemoService: Detected JSON format, attempting JSON parsing")
            if let jsonData = memo.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] {
                print("✅ ExtensionMemoService: Successfully parsed JSON, formatting contract interaction")
                return formatContractInteraction(json)
            } else {
                print("❌ ExtensionMemoService: Failed to parse JSON in CONTRACT INTERACTION decoding")
            }
        }
        
        print("❌ ExtensionMemoService: No JSON structure found in CONTRACT INTERACTION decoding")
        return nil
    }
    
    private func decodeTransactionMemo(_ memo: String) -> String? {
        print("🔍 ExtensionMemoService: Attempting TRANSACTION MEMO decoding...")
        
        // Handle transaction-specific memos
        if let decodedBase64 = decodeBase64Memo(memo) {
            print("✅ ExtensionMemoService: Successfully decoded using BASE64 MEMO method")
            return decodedBase64
        }
        
        print("❌ ExtensionMemoService: No transaction memo patterns matched")
        return nil
    }
    
    private func decodeHexMemo(_ memo: String) -> String? {
        print("🔍 ExtensionMemoService: Starting HEX MEMO decoding...")
        
        guard memo.hasPrefix("0x") && memo.count > 2 else {
            print("❌ ExtensionMemoService: Invalid hex format in HEX MEMO decoding")
            return nil
        }
        
        let hexString = String(memo.dropFirst(2))
        
        // Try to decode as function selector + parameters
        if hexString.count >= 8 {
            let selector = String(hexString.prefix(8))
            let parameters = String(hexString.dropFirst(8))
            
            print("🔍 ExtensionMemoService: Analyzing function selector: \(selector)")
            
            // Common function selectors
            switch selector.lowercased() {
            case "a9059cbb": // transfer(address,uint256)
                print("✅ ExtensionMemoService: Matched TRANSFER function selector (a9059cbb)")
                return "Transfer Token"
            case "095ea7b3": // approve(address,uint256)
                print("✅ ExtensionMemoService: Matched APPROVE function selector (095ea7b3)")
                return "Approve Token Spending"
            case "18160ddd": // totalSupply()
                print("✅ ExtensionMemoService: Matched TOTAL SUPPLY function selector (18160ddd)")
                return "Get Total Supply"
            case "70a08231": // balanceOf(address)
                print("✅ ExtensionMemoService: Matched BALANCE OF function selector (70a08231)")
                return "Get Balance"
            case "dd62ed3e": // allowance(address,address)
                print("✅ ExtensionMemoService: Matched ALLOWANCE function selector (dd62ed3e)")
                return "Get Allowance"
            default:
                print("⚠️ ExtensionMemoService: Unknown function selector (\(selector)), returning generic contract call")
                return "Contract Function Call (\(selector))"
            }
        }
        
        print("🔍 ExtensionMemoService: Attempting to decode hex as UTF-8 text...")
        
        // Try to decode as UTF-8 text
        if let data = Data(hexString: hexString),
           let text = String(data: data, encoding: .utf8),
           !text.isEmpty {
            print("✅ ExtensionMemoService: Successfully decoded hex as UTF-8 text")
            return text
        }
        
        print("⚠️ ExtensionMemoService: Returning truncated hex data")
        return "Hex Data (\(hexString.prefix(16))...)"
    }
    
    private func extractApprovalDetails(_ memo: String) -> String {
        print("🔍 ExtensionMemoService: Extracting APPROVAL DETAILS...")
        
        // Extract approval-specific details
        if let range = memo.range(of: "approve", options: .caseInsensitive) {
            let remainder = String(memo[range.upperBound...])
            let result = "Token Approval\(remainder.isEmpty ? "" : ": \(remainder.trimmingCharacters(in: .whitespaces))")"
            print("✅ ExtensionMemoService: Extracted approval details: '\(result)'")
            return result
        }
        print("⚠️ ExtensionMemoService: Fallback to generic Token Approval")
        return "Token Approval"
    }
    
    private func extractTransferDetails(_ memo: String) -> String {
        print("🔍 ExtensionMemoService: Extracting TRANSFER DETAILS...")
        
        // Extract transfer-specific details
        if let range = memo.range(of: "transfer", options: .caseInsensitive) {
            let remainder = String(memo[range.upperBound...])
            let result = "Token Transfer\(remainder.isEmpty ? "" : ": \(remainder.trimmingCharacters(in: .whitespaces))")"
            print("✅ ExtensionMemoService: Extracted transfer details: '\(result)'")
            return result
        }
        print("⚠️ ExtensionMemoService: Fallback to generic Token Transfer")
        return "Token Transfer"
    }
    
    private func extractSwapDetails(_ memo: String) -> String {
        print("🔍 ExtensionMemoService: Extracting SWAP DETAILS...")
        
        // Extract swap-specific details
        if let range = memo.range(of: "swap", options: .caseInsensitive) {
            let remainder = String(memo[range.upperBound...])
            let result = "Token Swap\(remainder.isEmpty ? "" : ": \(remainder.trimmingCharacters(in: .whitespaces))")"
            print("✅ ExtensionMemoService: Extracted swap details: '\(result)'")
            return result
        }
        print("⚠️ ExtensionMemoService: Fallback to generic Token Swap")
        return "Token Swap"
    }
    
    private func formatContractInteraction(_ json: [String: Any]) -> String {
        print("🔍 ExtensionMemoService: Formatting CONTRACT INTERACTION from JSON...")
        
        // Format JSON contract interaction
        if let method = json["method"] as? String {
            var details = "Contract: \(method)"
            print("✅ ExtensionMemoService: Found contract method: \(method)")
            
            if let params = json["params"] as? [String: Any], !params.isEmpty {
                let paramStrings = params.compactMap { key, value in
                    "\(key): \(value)"
                }
                if !paramStrings.isEmpty {
                    details += "\nParameters: \(paramStrings.joined(separator: ", "))"
                    print("✅ ExtensionMemoService: Added \(paramStrings.count) parameters")
                }
            }
            
            return details
        }
        
        print("⚠️ ExtensionMemoService: No method found in JSON, returning generic Contract Interaction")
        return "Contract Interaction"
    }
    
    private func decodeBase64Memo(_ memo: String) -> String? {
        print("🔍 ExtensionMemoService: Attempting BASE64 MEMO decoding...")
        
        // Try to decode base64 memo
        guard let data = Data(base64Encoded: memo),
              let text = String(data: data, encoding: .utf8),
              !text.isEmpty else {
            print("❌ ExtensionMemoService: Failed to decode as base64 or resulted in empty text")
            return nil
        }
        
        print("✅ ExtensionMemoService: Successfully decoded base64 to: '\(text)'")
        return text
    }
    
    private func isBase64Like(_ string: String) -> Bool {
        // Check if string looks like base64
        let base64Pattern = "^[A-Za-z0-9+/]*={0,2}$"
        let regex = try? NSRegularExpression(pattern: base64Pattern, options: [])
        let range = NSRange(location: 0, length: string.count)
        return regex?.firstMatch(in: string, options: [], range: range) != nil && string.count % 4 == 0
    }
}

// Helper extension for hex decoding
extension Data {
    init?(hexString: String) {
        let len = hexString.count / 2
        var data = Data(capacity: len)
        var i = hexString.startIndex
        for _ in 0..<len {
            let j = hexString.index(i, offsetBy: 2)
            let bytes = hexString[i..<j]
            if var num = UInt8(bytes, radix: 16) {
                data.append(&num, count: 1)
            } else {
                return nil
            }
            i = j
        }
        self = data
    }
} 