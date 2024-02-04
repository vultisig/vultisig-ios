//
//  Vault.swift
//  VoltixApp

import Foundation
import SwiftData

@Model
final class Vault : ObservableObject{
    @Attribute(.unique) var name: String
    var signers: [String] = [String]()
    var createdAt: Date = Date.now
    var pubKeyECDSA: String = ""
    var pubKeyEdDSA: String = ""
    var keyshares = [KeyShare]()
    
    init(name: String){
        self.name = name
    }
    
    init(name: String, signers: [String], pubKeyECDSA: String, pubKeyEdDSA: String, keyshares: [KeyShare]) {
        self.name = name
        self.signers = signers
        self.createdAt = Date.now
        self.pubKeyECDSA = pubKeyECDSA
        self.pubKeyEdDSA = pubKeyEdDSA
        self.keyshares = keyshares
    }
    
    func addKeyshare(pubkey: String, keyshare:String) {
        let share = KeyShare(pubkey: pubkey, keyshare: keyshare)
        modelContext?.insert(share)
        self.keyshares.append(share)
    }
    static func predicate(searchName: String) ->Predicate<Vault>{
        return #Predicate<Vault>{ vault in
            searchName.isEmpty || vault.name == searchName
        }
    }
}

@Model
final class KeyShare {
    @Attribute(.unique) let pubkey: String
    let keyshare: String
    init(pubkey: String, keyshare: String) {
        self.pubkey = pubkey
        self.keyshare = keyshare
    }
}

// define some functions used for test
extension Vault{
    static func loadTestData(modelContext: ModelContext) {
        modelContext.insert(Vault(name: "test", signers:["A","B","C"],  pubKeyECDSA: "ECDSA PubKey", pubKeyEdDSA: "EdDSA PubKey",keyshares: [KeyShare]()))
        modelContext.insert(Vault(name: "test 1", signers:["C","D","E"], pubKeyECDSA: "ECDSA PubKey", pubKeyEdDSA: "EdDSA PubKey",keyshares: [KeyShare]()))
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
