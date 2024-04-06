//
//  VaultExtension.swift
//  VoltixApp
//
//  Created by Amol Kumar on 2024-03-04.
//

import SwiftData
import Foundation

// define some functions used for test
extension Vault {
    static func loadTestData(modelContext: ModelContext) {
        modelContext.insert(Vault(name: "test", signers: ["A", "B", "C"], pubKeyECDSA: "ECDSA PubKey", pubKeyEdDSA: "EdDSA PubKey", keyshares: [KeyShare](), localPartyID: "first", hexChainCode: "", resharePrefix: ""))
        modelContext.insert(Vault(name: "test 1", signers: ["C", "D", "E"], pubKeyECDSA: "ECDSA PubKey", pubKeyEdDSA: "EdDSA PubKey", keyshares: [KeyShare](), localPartyID: "second", hexChainCode: "", resharePrefix: ""))
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
        let currentDate = Date()
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM"
        let formattedDate = formatter.string(from: currentDate)
        let totalSigners = self.signers.count
        let threshold = getThreshold()
        let lastFourOfPubKey = String(self.pubKeyECDSA.suffix(4))
        return "voltix-\(self.name)-\(formattedDate)-\(threshold+1)of\(totalSigners)-\(lastFourOfPubKey).dat"
    }
}
