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
    @Published var isInternalDeeplink: Bool = false
    
    func extractParameters(_ url: URL, vaults: [Vault], isInternal: Bool = false) {
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
        isInternalDeeplink = isInternal
        
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
        let pathComponents = url.pathComponents.filter { $0 != "/" }
        let isSendFlow = urlComponents.host == "send" || pathComponents.contains("send")
        
        if isSendFlow {
            processSendDeeplink(url: url, queryItems: queryItems, vaults: vaults)
        } else {
            processKeysignOrKeygenDeeplink(url: url, queryItems: queryItems, vaults: vaults)
        }
    }
    
    private func processSendDeeplink(url: URL, queryItems: [URLQueryItem]?, vaults: [Vault]) {
        type = .Send
        
        // Extract address (required)
        if let addressQuery = queryItems?.first(where: { $0.name == "address" })?.value {
            address = Utils.sanitizeAddress(address: addressQuery)
        }
        
        // Extract chain (optional)
        assetChain = queryItems?.first(where: { $0.name == "chain" })?.value
        
        // Extract asset/ticker (optional)
        assetTicker = queryItems?.first(where: { $0.name == "asset" })?.value
        
        // Extract amount (optional)
        sendAmount = queryItems?.first(where: { $0.name == "amount" })?.value
        
        // Extract memo (optional)
        sendMemo = queryItems?.first(where: { $0.name == "memo" })?.value
        
        // Set flag to indicate there's a pending send deeplink to be processed
        pendingSendDeeplink = true
        
        // Validate extracted parameters
        if address == nil || address?.isEmpty == true {
            print("⚠️ Send deeplink missing required address parameter")
            type = .Unknown
            return
        }
        
        // Try to match vault by chain if provided
        if let chainName = assetChain {
            selectedVault = vaults.first { vault in
                vault.coins.contains { $0.chain.name.lowercased() == chainName.lowercased() }
            }
        }
        
        // If no vault matched or no chain specified, use first vault with any coin
        if selectedVault == nil && !vaults.isEmpty {
            selectedVault = vaults.first
        }
    }
    
    private func processKeysignOrKeygenDeeplink(url: URL, queryItems: [URLQueryItem]?, vaults: [Vault]) {
        guard let tssTypeString = queryItems?.first(where: { $0.name == "type" })?.value,
              let tssType = TssType(rawValue: tssTypeString) else {
            return
        }
        
        self.tssType = tssType
        
        switch tssType {
        case .Keygen:
            type = .NewVault
        case .Reshare, .Migrate, .KeyImport:
            type = .SignTransaction
        }
        
        if let hexString = queryItems?.first(where: { $0.name == "jsonData" })?.value {
            jsonData = hexString
        }
        
        if let vaultHex = queryItems?.first(where: { $0.name == "vault" })?.value {
            selectedVault = vaults.first(where: { $0.pubKeyECDSA == vaultHex })
        }
    }
    
    // Static helper methods for direct URL parsing
    static func getJsonData(_ url: URL) -> String? {
        guard let urlComponents = URLComponents(string: url.absoluteString) else {
            return nil
        }
        return urlComponents.queryItems?.first(where: { $0.name == "jsonData" })?.value
    }
    
    static func getTssType(_ url: URL) -> String? {
        guard let urlComponents = URLComponents(string: url.absoluteString) else {
            return nil
        }
        return urlComponents.queryItems?.first(where: { $0.name == "type" })?.value
    }
    
    func resetData() {
        type = nil
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
        isInternalDeeplink = false
        viewID = UUID()
    }
    
    func findCoin(in vault: Vault) -> Coin? {
        // Try to find by both chain and ticker if available
        if let chainName = assetChain, let ticker = assetTicker {
            return vault.coins.first { coin in
                coin.chain.name.lowercased() == chainName.lowercased() &&
                coin.ticker.lowercased() == ticker.lowercased()
            }
        }
        
        // Try to find by chain only
        if let chainName = assetChain {
            return vault.coins.first { coin in
                coin.chain.name.lowercased() == chainName.lowercased() &&
                coin.isNativeToken
            }
        }
        
        // Try to find by ticker only
        if let ticker = assetTicker {
            return vault.coins.first { coin in
                coin.ticker.lowercased() == ticker.lowercased()
            }
        }
        
        return nil
    }
}
