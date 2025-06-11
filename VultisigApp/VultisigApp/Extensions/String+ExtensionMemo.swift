//
//  String+ExtensionMemo.swift
//  VultisigApp
//
//  Created by System on 2025-01-16.
//

import Foundation

extension String {
    
    /// Attempts to decode this string as a Vultisig extension memo
    /// Returns the decoded human-readable description or nil if not an extension memo
    var decodedExtensionMemo: String? {
        // Check if this is a Vultisig Extension memo format
        guard isExtensionMemo else {
            print("🔍 ExtensionMemo: Memo '\(prefix(50))...' is not recognized as extension memo")
            return nil
        }
        
        print("🔍 ExtensionMemo: Processing extension memo: '\(prefix(50))...'")
        print("📝 ExtensionMemo: Original memo text: '\(self)'")
        
        // Handle different extension memo formats - prioritize JSON over text patterns
        if let decodedContract = decodedContractInteraction {
            print("✅ ExtensionMemo: Successfully decoded using CONTRACT INTERACTION method")
            print("🎯 ExtensionMemo: Final decoded result: '\(decodedContract)'")
            return decodedContract
        }
        
        if let decodedAction = decodedActionMemo {
            print("✅ ExtensionMemo: Successfully decoded using ACTION MEMO method")
            print("🎯 ExtensionMemo: Final decoded result: '\(decodedAction)'")
            return decodedAction
        }
        
        if let decodedTransaction = decodedTransactionMemo {
            print("✅ ExtensionMemo: Successfully decoded using TRANSACTION MEMO method")
            print("🎯 ExtensionMemo: Final decoded result: '\(decodedTransaction)'")
            return decodedTransaction
        }
        
        print("❌ ExtensionMemo: Failed to decode memo despite being recognized as extension memo")
        return nil
    }
    
    /// Checks if this string appears to be an extension memo format
    private var isExtensionMemo: Bool {
        // Extension memos typically start with specific patterns or contain encoded data
        // Common patterns for extension memos:
        // - Hex encoded data starting with 0x
        // - Base64 encoded data
        // - JSON-like structures
        // - Contract interaction patterns
        
        if hasPrefix("0x") && count > 10 {
            return true
        }
        
        // Check for common dApp interaction patterns
        if contains("approve") || contains("transfer") || contains("swap") {
            return true
        }
        
        // Check for encoded JSON or structured data
        if contains("{") && contains("}") {
            return true
        }
        
        // Check for base64-like patterns (common in extension memos)
        if isBase64Like {
            return true
        }
        
        return false
    }
    
    /// Attempts to decode as a contract interaction memo
    private var decodedContractInteraction: String? {
        print("🔍 ExtensionMemo: Attempting CONTRACT INTERACTION decoding...")
        
        // Handle contract interaction memos
        if contains("{") && contains("}") {
            print("🔍 ExtensionMemo: Detected JSON format, attempting JSON parsing")
            if let jsonData = data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] {
                print("✅ ExtensionMemo: Successfully parsed JSON, formatting contract interaction")
                return json.formattedContractInteraction
            } else {
                print("❌ ExtensionMemo: Failed to parse JSON in CONTRACT INTERACTION decoding")
            }
        }
        
        print("❌ ExtensionMemo: No JSON structure found in CONTRACT INTERACTION decoding")
        return nil
    }
    
    /// Attempts to decode as an action-based memo
    private var decodedActionMemo: String? {
        print("🔍 ExtensionMemo: Attempting ACTION MEMO decoding...")
        
        // Decode common action-based memos
        if hasPrefix("0x") {
            print("🔍 ExtensionMemo: Detected hex format, using HEX MEMO decoding")
            return decodedHexMemo
        }
        
        // Handle specific action patterns
        if lowercased().contains("approve") {
            print("🔍 ExtensionMemo: Detected approval pattern, using APPROVAL DETAILS extraction")
            return extractedApprovalDetails
        }
        
        if lowercased().contains("transfer") {
            print("🔍 ExtensionMemo: Detected transfer pattern, using TRANSFER DETAILS extraction")
            return extractedTransferDetails
        }
        
        if lowercased().contains("swap") {
            print("🔍 ExtensionMemo: Detected swap pattern, using SWAP DETAILS extraction")
            return extractedSwapDetails
        }
        
        print("❌ ExtensionMemo: No action patterns matched in ACTION MEMO decoding")
        return nil
    }
    
    /// Attempts to decode as a transaction memo
    private var decodedTransactionMemo: String? {
        print("🔍 ExtensionMemo: Attempting TRANSACTION MEMO decoding...")
        
        // Handle transaction-specific memos
        if let decodedBase64 = decodedBase64Memo {
            print("✅ ExtensionMemo: Successfully decoded using BASE64 MEMO method")
            return decodedBase64
        }
        
        print("❌ ExtensionMemo: No transaction memo patterns matched")
        return nil
    }
    
    /// Attempts to decode as hex memo
    private var decodedHexMemo: String? {
        print("🔍 ExtensionMemo: Starting HEX MEMO decoding...")
        
        guard hasPrefix("0x") && count > 2 else {
            print("❌ ExtensionMemo: Invalid hex format in HEX MEMO decoding")
            return nil
        }
        
        let hexString = String(dropFirst(2))
        
        // Try to decode as function selector + parameters
        if hexString.count >= 8 {
            let selector = String(hexString.prefix(8))
            let parameters = String(hexString.dropFirst(8))
            
            print("🔍 ExtensionMemo: Analyzing function selector: \(selector)")
            
            // Common function selectors
            switch selector.lowercased() {
            case "a9059cbb": // transfer(address,uint256)
                print("✅ ExtensionMemo: Matched TRANSFER function selector (a9059cbb)")
                return "Transfer Token"
            case "095ea7b3": // approve(address,uint256)
                print("✅ ExtensionMemo: Matched APPROVE function selector (095ea7b3)")
                return "Approve Token Spending"
            case "18160ddd": // totalSupply()
                print("✅ ExtensionMemo: Matched TOTAL SUPPLY function selector (18160ddd)")
                return "Get Total Supply"
            case "70a08231": // balanceOf(address)
                print("✅ ExtensionMemo: Matched BALANCE OF function selector (70a08231)")
                return "Get Balance"
            case "dd62ed3e": // allowance(address,address)
                print("✅ ExtensionMemo: Matched ALLOWANCE function selector (dd62ed3e)")
                return "Get Allowance"
            default:
                print("⚠️ ExtensionMemo: Unknown function selector (\(selector)), returning generic contract call")
                return "Contract Function Call (\(selector))"
            }
        }
        
        print("🔍 ExtensionMemo: Attempting to decode hex as UTF-8 text...")
        
        // Try to decode as UTF-8 text
        if let data = Data(hexString: hexString),
           let text = String(data: data, encoding: .utf8),
           !text.isEmpty {
            print("✅ ExtensionMemo: Successfully decoded hex as UTF-8 text")
            return text
        }
        
        print("⚠️ ExtensionMemo: Returning truncated hex data")
        return "Hex Data (\(hexString.prefix(16))...)"
    }
    
    /// Extracts approval details from text
    private var extractedApprovalDetails: String {
        print("🔍 ExtensionMemo: Extracting APPROVAL DETAILS...")
        
        if let range = range(of: "approve", options: .caseInsensitive) {
            let remainder = String(self[range.upperBound...])
            let result = "Token Approval\(remainder.isEmpty ? "" : ": \(remainder.trimmingCharacters(in: .whitespaces))")"
            print("✅ ExtensionMemo: Extracted approval details: '\(result)'")
            return result
        }
        print("⚠️ ExtensionMemo: Fallback to generic Token Approval")
        return "Token Approval"
    }
    
    /// Extracts transfer details from text
    private var extractedTransferDetails: String {
        print("🔍 ExtensionMemo: Extracting TRANSFER DETAILS...")
        
        if let range = range(of: "transfer", options: .caseInsensitive) {
            let remainder = String(self[range.upperBound...])
            let result = "Token Transfer\(remainder.isEmpty ? "" : ": \(remainder.trimmingCharacters(in: .whitespaces))")"
            print("✅ ExtensionMemo: Extracted transfer details: '\(result)'")
            return result
        }
        print("⚠️ ExtensionMemo: Fallback to generic Token Transfer")
        return "Token Transfer"
    }
    
    /// Extracts swap details from text
    private var extractedSwapDetails: String {
        print("🔍 ExtensionMemo: Extracting SWAP DETAILS...")
        
        if let range = range(of: "swap", options: .caseInsensitive) {
            let remainder = String(self[range.upperBound...])
            let result = "Token Swap\(remainder.isEmpty ? "" : ": \(remainder.trimmingCharacters(in: .whitespaces))")"
            print("✅ ExtensionMemo: Extracted swap details: '\(result)'")
            return result
        }
        print("⚠️ ExtensionMemo: Fallback to generic Token Swap")
        return "Token Swap"
    }
    
    /// Attempts to decode as base64
    private var decodedBase64Memo: String? {
        print("🔍 ExtensionMemo: Attempting BASE64 MEMO decoding...")
        
        guard let data = Data(base64Encoded: self),
              let text = String(data: data, encoding: .utf8),
              !text.isEmpty else {
            print("❌ ExtensionMemo: Failed to decode as base64 or resulted in empty text")
            return nil
        }
        
        print("✅ ExtensionMemo: Successfully decoded base64 to: '\(text)'")
        return text
    }
    
    /// Checks if string looks like base64
    private var isBase64Like: Bool {
        let base64Pattern = "^[A-Za-z0-9+/]*={0,2}$"
        let regex = try? NSRegularExpression(pattern: base64Pattern, options: [])
        let range = NSRange(location: 0, length: count)
        return regex?.firstMatch(in: self, options: [], range: range) != nil && count % 4 == 0
    }
}

// MARK: - Dictionary Extension for Contract Interaction

private extension Dictionary where Key == String, Value == Any {
    
    /// Formats contract interaction JSON into readable string
    var formattedContractInteraction: String {
        print("🔍 ExtensionMemo: Formatting CONTRACT INTERACTION from JSON...")
        
        if let method = self["method"] as? String {
            var details = "Contract: \(method)"
            print("✅ ExtensionMemo: Found contract method: \(method)")
            
            if let params = self["params"] as? [String: Any], !params.isEmpty {
                let paramStrings = params.compactMap { key, value in
                    "\(key): \(value)"
                }
                if !paramStrings.isEmpty {
                    details += "\nParameters: \(paramStrings.joined(separator: ", "))"
                    print("✅ ExtensionMemo: Added \(paramStrings.count) parameters")
                }
            }
            
            return details
        }
        
        print("⚠️ ExtensionMemo: No method found in JSON, returning generic Contract Interaction")
        return "Contract Interaction"
    }
}

// MARK: - Data Extension for Hex Decoding

private extension Data {
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