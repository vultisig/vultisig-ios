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
            return nil
        }
        
        // Handle different extension memo formats - prioritize JSON over text patterns
        if let decodedContract = decodedContractInteraction {
            return decodedContract
        }
        
        if let decodedAction = decodedActionMemo {
            return decodedAction
        }
        
        if let decodedTransaction = decodedTransactionMemo {
            return decodedTransaction
        }
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
        // Handle contract interaction memos
        if contains("{") && contains("}") {
            if let jsonData = data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] {
                return json.formattedContractInteraction
            }
        }
        
        return nil
    }
    
    /// Attempts to decode as an action-based memo
    private var decodedActionMemo: String? {
        // Decode common action-based memos
        if hasPrefix("0x") {
            return decodedHexMemo
        }
        
        // Handle specific action patterns
        if lowercased().contains("approve") {
            return extractedApprovalDetails
        }
        
        if lowercased().contains("transfer") {
            return extractedTransferDetails
        }
        
        if lowercased().contains("swap") {
            return extractedSwapDetails
        }
        
        return nil
    }
    
    /// Attempts to decode as a transaction memo
    private var decodedTransactionMemo: String? {
        // Handle transaction-specific memos
        if let decodedBase64 = decodedBase64Memo {
            return decodedBase64
        }
        
        return nil
    }
    
    /// Attempts to decode as hex memo
    private var decodedHexMemo: String? {
        guard hasPrefix("0x") && count > 2 else {
            return nil
        }
        
        let hexString = String(dropFirst(2))
        
        // Try to decode as function selector + parameters
        if hexString.count >= 8 {
            let selector = String(hexString.prefix(8))
            
            // Common function selectors
            switch selector.lowercased() {
            case "a9059cbb": // transfer(address,uint256)
                return "Transfer Token"
            case "095ea7b3": // approve(address,uint256)
                return "Approve Token Spending"
            case "18160ddd": // totalSupply()
                return "Get Total Supply"
            case "70a08231": // balanceOf(address)
                return "Get Balance"
            case "dd62ed3e": // allowance(address,address)
                return "Get Allowance"
            default:
                return "Contract Function Call (\(selector))"
            }
        }
        
        // Skip hex-to-text decoding for now - will implement properly with WalletCore
        // return nil for unknown function selectors
        
        return "Hex Data (\(hexString.prefix(16))...)"
    }
    
    /// Extracts approval details from text
    private var extractedApprovalDetails: String {
        if let range = range(of: "approve", options: .caseInsensitive) {
            let remainder = String(self[range.upperBound...])
            return "Token Approval\(remainder.isEmpty ? "" : ": \(remainder.trimmingCharacters(in: .whitespaces))")"
        }
        return "Token Approval"
    }
    
    /// Extracts transfer details from text
    private var extractedTransferDetails: String {
        if let range = range(of: "transfer", options: .caseInsensitive) {
            let remainder = String(self[range.upperBound...])
            return "Token Transfer\(remainder.isEmpty ? "" : ": \(remainder.trimmingCharacters(in: .whitespaces))")"
        }
        return "Token Transfer"
    }
    
    /// Extracts swap details from text
    private var extractedSwapDetails: String {
        if let range = range(of: "swap", options: .caseInsensitive) {
            let remainder = String(self[range.upperBound...])
            return "Token Swap\(remainder.isEmpty ? "" : ": \(remainder.trimmingCharacters(in: .whitespaces))")"
        }
        return "Token Swap"
    }
    
    /// Attempts to decode as base64
    private var decodedBase64Memo: String? {
        guard let data = Data(base64Encoded: self),
              let text = String(data: data, encoding: .utf8),
              !text.isEmpty else {
            return nil
        }
        
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
        if let method = self["method"] as? String {
            var details = "Contract: \(method)"
            
            if let params = self["params"] as? [String: Any], !params.isEmpty {
                let paramStrings = params.compactMap { key, value in
                    "\(key): \(value)"
                }
                if !paramStrings.isEmpty {
                    details += "\nParameters: \(paramStrings.joined(separator: ", "))"
                }
            }
            
            return details
        }
        
        return "Contract Interaction"
    }
} 