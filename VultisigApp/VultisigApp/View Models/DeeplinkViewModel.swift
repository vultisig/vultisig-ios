//
//  DeeplinkViewModel.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-05-01.
//

import SwiftUI

enum DeeplinkFlowType {
    case NewVault
    case SignTransaction
    case Send
    case Unknown
}

@MainActor
class DeeplinkViewModel: ObservableObject {
    @Published var type: DeeplinkFlowType? = nil
    @Published var selectedVault: Vault? = nil
    @Published var tssType: TssType? = nil
    @Published var jsonData: String? = nil
    @Published var receivedUrl: URL? = nil
    @Published var viewID = UUID()
    @Published var address: String? = nil
    
    // Properties for Send deeplink flow
    @Published var assetChain: String? = nil
    @Published var assetTicker: String? = nil
    @Published var sendAmount: String? = nil
    @Published var sendMemo: String? = nil
    @Published var pendingSendDeeplink: Bool = false
    
    func extractParameters(_ url: URL, vaults: [Vault]) {
        // Don't reset type immediately - it needs to persist for onChange to trigger
        // Only reset other fields
        selectedVault = nil
        tssType = nil
        jsonData = nil
        receivedUrl = nil
        address = nil
        assetChain = nil
        assetTicker = nil
        sendAmount = nil
        sendMemo = nil
        pendingSendDeeplink = false
        
        viewID = UUID()
        receivedUrl = url
        
        guard let urlComponents = URLComponents(string: url.absoluteString) else {
            // If URL parsing fails, try to extract address from absolute string
            // Remove vultisig:// scheme
            let addressString = url.absoluteString.replacingOccurrences(of: "vultisig://", with: "")
            address = Utils.sanitizeAddress(address: addressString)
            type = .Unknown
            
            // Send notification for Unknown type as well
            NotificationCenter.default.post(name: NSNotification.Name("ProcessDeeplink"), object: nil)
            return
        }
        
        let queryItems = urlComponents.queryItems
        
        // Check if path or host contains "send" for Send flow
        // For URLs like vultisig://send?param=value, "send" might be in host or path
        // Also check the raw URL string as fallback
        let path = urlComponents.path.lowercased()
        let host = urlComponents.host?.lowercased() ?? ""
        let urlString = url.absoluteString.lowercased()
        
        // Split path by "/" to check path components
        let pathComponents = path.split(separator: "/").map { String($0) }
        
        // Multiple ways to detect "send" path:
        // 1. In path
        // 2. In host
        // 3. In URL string pattern (vultisig://send)
        let isSendPath = path.contains("send") || 
                         pathComponents.contains("send") ||
                         host == "send" ||
                         host.contains("send") ||
                         urlString.contains("://send") ||
                         urlString.hasPrefix("vultisig://send")
        
        if isSendPath {
            // Send deeplink flow
            type = .Send
            
            // Parse Send-specific parameters
            assetChain = queryItems?.first(where: { $0.name == "assetChain" })?.value?.removingPercentEncoding
            assetTicker = queryItems?.first(where: { $0.name == "assetTicker" })?.value?.removingPercentEncoding
            address = queryItems?.first(where: { $0.name == "toAddress" })?.value?.removingPercentEncoding
            sendAmount = queryItems?.first(where: { $0.name == "amount" })?.value?.removingPercentEncoding
            sendMemo = queryItems?.first(where: { $0.name == "memo" })?.value?.removingPercentEncoding
        } else if queryItems == nil {
            // Address-only deeplink (no query params)
            // Extract address from host or path (remove vultisig:// scheme)
            let extractedAddress = urlComponents.host ?? (urlComponents.path.isEmpty ? nil : urlComponents.path)
            // Remove leading "/" if present in path
            let cleanAddress: String?
            if let extracted = extractedAddress {
                cleanAddress = extracted.hasPrefix("/") ? String(extracted.dropFirst()) : extracted
            } else {
                cleanAddress = nil
            }
            address = Utils.sanitizeAddress(address: cleanAddress ?? url.absoluteString.replacingOccurrences(of: "vultisig://", with: ""))
            type = .Unknown
        } else {
            // Existing flows (NewVault, SignTransaction)
        //Flow Type
        let typeData = queryItems?.first(where: { $0.name == "type" })?.value
        type = getFlowType(typeData)
        
        //Tss Type
        let tssData = queryItems?.first(where: { $0.name == "tssType" })?.value
        tssType = getTssType(tssData)
        
        //Vault
        let vaultPubKey = queryItems?.first(where: { $0.name == "vault" })?.value
        selectedVault = getVault(for: vaultPubKey, vaults: vaults)
        
        //JsonData
        jsonData = queryItems?.first(where: { $0.name == "jsonData" })?.value
        }
        
            // Send notification if type is set (for Send and Unknown flows, this ensures processing happens)
            // This is needed because the scanner calls extractParameters directly, not through ContentView
            
            if type == .Send || type == .Unknown {
                NotificationCenter.default.post(name: NSNotification.Name("ProcessDeeplink"), object: nil)
            }
    }
    
    
    
    static func getJsonData(_ url: URL?) -> String? {
        guard let url else {
            return nil
        }
        
        let queryItems = URLComponents(string: url.absoluteString)?.queryItems
        return queryItems?.first(where: { $0.name == "jsonData" })?.value
    }
    
    static func getTssType(_ url: URL?) -> String? {
        guard let url else {
            return nil
        }
        
        let queryItems = URLComponents(string: url.absoluteString)?.queryItems
        return queryItems?.first(where: { $0.name == "tssType" })?.value
    }
    
    func resetData() {
        type = nil
        selectedVault = nil
        tssType = nil
        jsonData = nil
        receivedUrl = nil
        address = nil
        
        // Reset Send deeplink properties
        assetChain = nil
        assetTicker = nil
        sendAmount = nil
        sendMemo = nil
        pendingSendDeeplink = false
    }
    
    private func getFlowType(_ type: String?) -> DeeplinkFlowType {
        switch type {
        case "NewVault":
            return .NewVault
        case "SignTransaction":
            return .SignTransaction
        case "Send":
            return .Send
        default:
            return .Unknown
        }
    }
    
    private func getTssType(_ type: String?) -> TssType {
        switch type {
        case "Reshare":
            return .Reshare
        default:
            return .Keygen
        }
    }
    
    private func getVault(for vaultPubKey: String?, vaults: [Vault]) -> Vault? {
        for vault in vaults {
            if vault.pubKeyECDSA == vaultPubKey {
                return vault
            }
        }
        return nil
    }
    
    /// Finds a coin in a vault by chain and ticker (case-insensitive)
    func findCoin(in vault: Vault) -> Coin? {
        guard let assetChain = assetChain,
              let assetTicker = assetTicker else {
            return nil
        }
        
        // Convert assetChain string to Chain enum (case-insensitive)
        let chainString = assetChain.lowercased()
        
        guard let chain = Chain.allCases.first(where: { $0.rawValue.lowercased() == chainString }) else {
            return nil
        }
        
        // Find coin matching chain and ticker (case-insensitive)
        let tickerUpper = assetTicker.uppercased()
        let foundCoin = vault.coins.first(where: { coin in
            let matches = coin.chain == chain && coin.ticker.uppercased() == tickerUpper
            return matches
        })
        
        return foundCoin
    }
}
