//
//  String+ExtensionMemo.swift
//  VultisigApp
//
//  Created by System on 2025-01-16.
//

import Foundation
import BigInt

extension String {
    
    /// Attempts to decode this string as a Vultisig extension memo
    /// Returns the decoded human-readable description or nil if not an extension memo
    var decodedExtensionMemo: String? {
        // Check if this is a Vultisig Extension memo format
        guard isExtensionMemo else {
            return nil
        }
        
        // Handle different extension memo formats - prioritize detailed parsing over simple patterns
        if let decodedContract = decodedContractInteraction {
            return decodedContract
        }
        
        if let decodedHex = decodedHexMemo {
            return decodedHex
        }
        
        if let decodedAction = decodedActionMemo {
            return decodedAction
        }
        
        if let decodedTransaction = decodedTransactionMemo {
            return decodedTransaction
        }
        
        return nil
    }
    
    /// Async version that can properly handle unknown function selectors via 4byte.directory
    func decodedExtensionMemoAsync() async -> String? {
        // Check if this is a Vultisig Extension memo format
        guard isExtensionMemo else {
            return nil
        }
        
        // Handle different extension memo formats - prioritize detailed parsing over simple patterns
        if let decodedContract = decodedContractInteraction {
            return decodedContract
        }
        
        if let decodedHex = await decodedHexMemoAsync() {
            return decodedHex
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
    public var isExtensionMemo: Bool {
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
        guard hasPrefix("0x") && count > 10 else {
            return nil
        }
        
        let hexString = String(dropFirst(2))
        
        // Try to decode as function selector + parameters
        if hexString.count >= 8 {
            let selector = String(hexString.prefix(8))
            
            // First check known function selectors for immediate response
            if let knownFunction = knownFunctionSelector(selector) {
                // For KyberSwap and other complex swaps, try to decode parameters
                if selector.lowercased() == "e21fd0e9" {
                    if let decoded = decodeKyberSwapParams() {
                        return decoded
                    }
                }
                return knownFunction
            }
            
            // For unknown selectors, return nil to indicate async decoding is needed
            return nil
        }
        
        return "Hex Data (\(hexString.prefix(16))...)"
    }
    
    /// Async version that can handle unknown function selectors via 4byte.directory
    private func decodedHexMemoAsync() async -> String? {
        guard hasPrefix("0x") && count > 10 else {
            return nil
        }
        
        let hexString = String(dropFirst(2))
        
        // Try to decode as function selector + parameters
        if hexString.count >= 8 {
            let selector = String(hexString.prefix(8))
            
            // First check known function selectors for immediate response
            if let knownFunction = knownFunctionSelector(selector) {
                // For KyberSwap and other complex swaps, try to decode parameters
                if selector.lowercased() == "e21fd0e9" {
                    if let decoded = decodeKyberSwapParams() {
                        return decoded
                    }
                }
                return knownFunction
            }
            
            // For unknown selectors, try async decoding via 4byte.directory
            if let parsedMemo = await MemoDecodingService.shared.getParsedMemo(memo: self) {
                var result = parsedMemo.functionSignature
                if !parsedMemo.functionArguments.isEmpty {
                    result += "\n\nParameters:\n" + parsedMemo.functionArguments
                }
                return result
            }
            
            // If async decoding fails, return basic info
            return "Contract Function Call (\(selector))"
        }
        
        return "Hex Data (\(hexString.prefix(16))...)"
    }
    
    /// Returns known function selector descriptions
    private func knownFunctionSelector(_ selector: String) -> String? {
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
        case "e21fd0e9": // KyberSwap main swap function
            return "KyberSwap Token Swap"
        case "7c025200": // 1inch swap function
            return "1inch Token Swap"
        case "38ed1739": // Uniswap swapExactTokensForTokens
            return "Uniswap Token Swap"
        case "8803dbee": // Uniswap swapTokensForExactTokens
            return "Uniswap Token Swap"
        case "fb3bdb41": // Uniswap swapETHForExactTokens
            return "Uniswap ETH to Token Swap"
        case "7ff36ab5": // Uniswap swapExactETHForTokens
            return "Uniswap ETH to Token Swap"
        case "4a25d94a": // Uniswap swapTokensForExactETH
            return "Uniswap Token to ETH Swap"
        case "18cbafe5": // Uniswap swapExactTokensForETH
            return "Uniswap Token to ETH Swap"
        case "b6f9de95": // Uniswap swapExactTokensForTokensSupportingFeeOnTransferTokens
            return "Uniswap Token Swap (Fee on Transfer)"
        case "791ac947": // Uniswap swapExactTokensForETHSupportingFeeOnTransferTokens
            return "Uniswap Token to ETH Swap (Fee on Transfer)"
        case "b52d278d": // Uniswap swapExactETHForTokensSupportingFeeOnTransferTokens
            return "Uniswap ETH to Token Swap (Fee on Transfer)"
        case "ac9650d8": // Multicall (used by many DEXes)
            return "Multi-Function Call"
        case "414bf389": // Uniswap V3 exactInputSingle
            return "Uniswap V3 Token Swap"
        case "c04b8d59": // Uniswap V3 exactInput
            return "Uniswap V3 Multi-Hop Swap"
        case "db3e2198": // Uniswap V3 exactOutputSingle
            return "Uniswap V3 Token Swap"
        case "f28c0498": // Uniswap V3 exactOutput
            return "Uniswap V3 Multi-Hop Swap"
        case "12210e8a": // Uniswap V3 refundETH
            return "Uniswap V3 ETH Refund"
        default:
            return nil
        }
    }
    
    /// Attempts to decode KyberSwap parameters
    private func decodeKyberSwapParams() -> String? {
        guard hasPrefix("0x") && count > 10 else {
            return nil
        }
        
        let hexData = String(dropFirst(2))
        guard hexData.count >= 72 else { return nil }
        
        var result = "KyberSwap Token Swap\n"
        
        // First, try to find and decode embedded JSON data
        if let jsonData = extractEmbeddedJSON(from: hexData) {
            result += formatKyberSwapJSON(jsonData)
            return result.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        
        // Fall back to basic ABI parameter parsing if no JSON found
        let paramData = String(hexData.dropFirst(8))
        let chunks = paramData.chunked(into: 64)
        guard chunks.count >= 4 else { return "KyberSwap Token Swap (insufficient data)" }
        
        // Parameter 1: Source token address (first 32 bytes)
        if let srcTokenAddress = extractAddress(from: chunks[0]) {
            result += "From Token: \(srcTokenAddress)\n"
        }
        
        // Parameter 2: Source amount (second 32 bytes)
        if let srcAmountHex = chunks.count > 1 ? chunks[1] : nil,
           let srcAmount = BigInt(srcAmountHex, radix: 16) {
            let ethAmount = Double(srcAmount) / Double(BigInt(10).power(18))
            if ethAmount > 0.000001 {
                result += "From Amount: \(String(format: "%.6f", ethAmount)) ETH\n"
            } else {
                result += "From Amount: \(srcAmount) wei\n"
            }
        }
        
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    /// Extracts and decodes embedded JSON data from hex transaction
    private func extractEmbeddedJSON(from hexData: String) -> [String: Any]? {
        // Look for JSON start pattern (7b = '{' in hex)
        let jsonStartPattern = "7b22" // '{"' in hex
        
        guard let range = hexData.range(of: jsonStartPattern) else {
            return nil
        }
        
        // Extract hex data starting from the JSON pattern
        let jsonHexStart = hexData[range.lowerBound...]
        
        // Find the end of JSON (look for closing brace followed by padding)
        var jsonHex = ""
        var braceCount = 0
        var foundStart = false
        
        for i in stride(from: 0, to: min(jsonHexStart.count, 4000), by: 2) {
            let startIndex = jsonHexStart.index(jsonHexStart.startIndex, offsetBy: i)
            guard let endIndex = jsonHexStart.index(startIndex, offsetBy: 2, limitedBy: jsonHexStart.endIndex) else { break }
            
            let hexByte = String(jsonHexStart[startIndex..<endIndex])
            guard let byte = UInt8(hexByte, radix: 16),
                  byte < 128 else { continue } // Only ASCII characters
            
            let scalar = UnicodeScalar(byte)
            let char = Character(scalar)
            jsonHex += hexByte
            
            if char == "{" {
                foundStart = true
                braceCount += 1
            } else if char == "}" {
                braceCount -= 1
                if foundStart && braceCount == 0 {
                    break
                }
            }
        }
        
        // Convert hex to JSON string
        var hexDataBytes = Data()
        for i in stride(from: 0, to: jsonHex.count, by: 2) {
            let startIndex = jsonHex.index(jsonHex.startIndex, offsetBy: i)
            let endIndex = jsonHex.index(startIndex, offsetBy: 2)
            let hexByte = String(jsonHex[startIndex..<endIndex])
            if let byte = UInt8(hexByte, radix: 16) {
                hexDataBytes.append(byte)
            }
        }
        
        guard let jsonString = String(data: hexDataBytes, encoding: .utf8),
              let jsonData = jsonString.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
            return nil
        }
        
        return json
    }
    
    /// Formats KyberSwap JSON data into readable string
    private func formatKyberSwapJSON(_ json: [String: Any]) -> String {
        var details: [String] = []
        
        if let source = json["Source"] as? String {
            details.append("Source: \(source)")
        }
        
        if let amountInUSD = json["AmountInUSD"] as? String,
           let amount = Double(amountInUSD) {
            details.append("Amount In: $\(String(format: "%.4f", amount))")
        }
        
        if let amountOutUSD = json["AmountOutUSD"] as? String,
           let amount = Double(amountOutUSD) {
            details.append("Amount Out: $\(String(format: "%.4f", amount))")
        }
        
        if let amountOut = json["AmountOut"] as? String {
            details.append("Raw Amount Out: \(amountOut)")
        }
        
        if let routeID = json["RouteID"] as? String {
            details.append("Route: \(routeID.prefix(20))...")
        }
        
        if let timestamp = json["Timestamp"] as? Int {
            let date = Date(timeIntervalSince1970: TimeInterval(timestamp))
            let formatter = DateFormatter()
            formatter.dateStyle = .short
            formatter.timeStyle = .short
            details.append("Time: \(formatter.string(from: date))")
        }
        
        return details.joined(separator: "\n")
    }
    
    /// Helper to extract a valid Ethereum address from ABI-encoded parameter
    private func extractAddress(from chunk: String) -> String? {
        guard chunk.count == 64 else { return nil }
        
        // Check if this looks like an address (20 bytes with 12 bytes of leading zeros)
        if chunk.hasPrefix("000000000000000000000000") {
            let addressHex = String(chunk.suffix(40))
            // Ensure it's not all zeros and is a valid address format
            if !addressHex.allSatisfy({ $0 == "0" }) && addressHex.count == 40 {
                return "0x" + addressHex
            }
        }
        
        return nil
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

        // e.g. for eth_signTypedData_v4
        if let jsonData = try? JSONSerialization.data(withJSONObject: self, options: [.prettyPrinted, .sortedKeys]),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            return jsonString
        }

        return "Contract Interaction"
    }
}

// MARK: - String Extension for Hex Processing

private extension String {
    
    /// Chunks the string into fixed-size pieces
    func chunked(into size: Int) -> [String] {
        var chunks: [String] = []
        var currentIndex = startIndex
        
        while currentIndex < endIndex {
            let nextIndex = index(currentIndex, offsetBy: size, limitedBy: endIndex) ?? endIndex
            chunks.append(String(self[currentIndex..<nextIndex]))
            currentIndex = nextIndex
        }
        
        return chunks
    }
} 
