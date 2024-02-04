//
//  Vault.swift
//  VoltixApp

import Foundation
import SwiftData

@Model
final class Vault : ObservableObject,Identifiable{
    @Attribute(.unique) let name: String
    var signers: [String] = []
    var createdAt: Date = Date.now
    var pubKeyECDSA: String = ""
    var pubKeyEdDSA: String = ""
    var keyshares: [KeyShare] = []
    
    init(name: String){
        self.name = name
    }
    
    init(name: String, signers: [String], pubKeyECDSA: String, pubKeyEdDSA: String) {
        self.name = name
        self.signers = signers
        self.createdAt = Date.now
        self.pubKeyECDSA = pubKeyECDSA
        self.pubKeyEdDSA = pubKeyEdDSA
    }
    
    static func predicate(searchName: String) ->Predicate<Vault>{
        return #Predicate<Vault>{ vault in
            searchName.isEmpty || vault.name == searchName
        }
    }
}

@Model
final class KeyShare: ObservableObject,Identifiable{
    init(pubkey: String, keyshare: String) {
        self.pubkey = pubkey
        self.keyshare = keyshare
    }
    @Attribute(.unique) let pubkey: String
    let keyshare: String
}

// define some functions used for test
extension Vault{
    static func loadTestData(modelContext: ModelContext) {
        modelContext.insert(Vault(name: "test", signers:["A","B","C"],  pubKeyECDSA: "ECDSA PubKey", pubKeyEdDSA: "EdDSA PubKey"))
        modelContext.insert(Vault(name: "test 1", signers:["C","D","E"], pubKeyECDSA: "ECDSA PubKey", pubKeyEdDSA: "EdDSA PubKey"))
    }
    
    static var sampleVaults: () throws -> ModelContainer =  {
        let schema = Schema([Vault.self])
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        Task { @MainActor in
            Vault.loadTestData(modelContext:container.mainContext)
        }
        return container
    }
}
