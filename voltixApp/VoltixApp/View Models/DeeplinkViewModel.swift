//
//  DeeplinkViewModel.swift
//  VoltixApp
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
    
    func extractParameters(_ url: URL, vaults: [Vault]) {
        print("App was opened via URL: \(url)")
        let queryItems = URLComponents(string: url.absoluteString)?.queryItems
        
        //Type
        let typeData = queryItems?.first(where: { $0.name == "type" })?.value
        type = getFlowType(typeData)
        
        //Vault
        let vaultPubKey = queryItems?.first(where: { $0.name == "vault" })?.value
        selectedVault = getVault(for: vaultPubKey, vaults: vaults)
        
        let jsonData = queryItems?.first(where: { $0.name == "jsonData" })?.value
        print(String(describing: jsonData))
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
    
    private func getVault(for vaultPubKey: String?, vaults: [Vault]) -> Vault? {
        for vault in vaults {
            if vault.pubKeyECDSA == vaultPubKey {
                return vault
            }
        }
        return nil
    }
}
