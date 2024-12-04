//
//  VaultExtension.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-03-04.
//

import SwiftData
import Foundation

// define some functions used for test
extension Vault {
    static func loadTestData(modelContext: ModelContext) {
        modelContext.insert(Vault(name: "test", signers: ["A", "B", "C"], pubKeyECDSA: "ECDSA PubKey", pubKeyEdDSA: "EdDSA PubKey", keyshares: [KeyShare](), localPartyID: "first", hexChainCode: "", resharePrefix: "",libType: 0))
        modelContext.insert(Vault(name: "test 1", signers: ["C", "D", "E"], pubKeyECDSA: "ECDSA PubKey", pubKeyEdDSA: "EdDSA PubKey", keyshares: [KeyShare](), localPartyID: "second", hexChainCode: "", resharePrefix: "",libType: 0))
    }
    
    static var sampleVaults: () throws -> ModelContainer = {
        let schema = Schema([Vault.self])
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        
        Task { @MainActor in
            Vault.loadTestData(modelContext: container.mainContext)
        }
        
        return container
    }
    
    func getExportName() -> String{
        let vaultName = self.name
        let lastFourOfPubKey = String(self.pubKeyECDSA.suffix(4))
        
        let signersCount = self.signers.count
        var signersOrder = 0
        
        for index in 0..<self.signers.count {
            if signers[index] == self.localPartyID {
                signersOrder = index+1
                continue
            }
        }
        let cleanVaultName = vaultName.replacingOccurrences(of: "/", with: "-")
        return "\(cleanVaultName)-\(lastFourOfPubKey)-part\(signersOrder)of\(signersCount)" + ".vult"
    }
}
