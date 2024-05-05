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
    case Unknown
}

@MainActor
class DeeplinkViewModel: ObservableObject {
    @Published var type: DeeplinkFlowType? = nil
    @Published var selectedVault: Vault? = nil
    @Published var joinVaultActive: Bool = false
    @Published var tssType: TssType? = nil
    @Published var jsonData: String? = nil
    @Published var viewID = UUID()
    
    func extractParameters(_ url: URL, vaults: [Vault]) {
        resetData()
        viewID = UUID()
        
        let queryItems = URLComponents(string: url.absoluteString)?.queryItems
        
        //Flow Type
        let typeData = queryItems?.first(where: { $0.name == "type" })?.value
        type = getFlowType(typeData)
        
        //Tss Type
        let tssData = queryItems?.first(where: { $0.name == "tssType" })?.value
        tssType = getTssType(tssData)
        
        //Vault
        let vaultPubKey = queryItems?.first(where: { $0.name == "vault" })?.value
        selectedVault = getVault(for: vaultPubKey, vaults: vaults)
    }
    
    static func getJsonData(_ url: URL?) -> String? {
        guard let url else {
            return nil
        }
        
        let queryItems = URLComponents(string: url.absoluteString)?.queryItems
        return queryItems?.first(where: { $0.name == "jsonData" })?.value
    }
    
    private func resetData() {
        type = nil
        tssType = nil
        selectedVault = nil
        joinVaultActive = false
    }
    
    private func getFlowType(_ type: String?) -> DeeplinkFlowType {
        switch type {
        case "NewVault":
            return .NewVault
        case "SignTransaction":
            return .SignTransaction
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
}
