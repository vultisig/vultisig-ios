//
//  Vault.swift
//  VoltixApp

import Foundation
import SwiftData

@Model
final class Vault : ObservableObject,Identifiable{
    @Attribute(.unique) let name: String
    let pubkey: String
    let signers: [String]
    let createdAt: Date
    
    init(name: String, pubkey: String, signers: [String], createdAt: Date) {
        self.name = name
        self.pubkey = pubkey
        self.signers = signers
        self.createdAt = createdAt
    }
    
    static func predicate(searchName: String) ->Predicate<Vault>{
        return #Predicate<Vault>{ vault in
            searchName.isEmpty || vault.name == searchName
        }
    }
}

// define some functions used for test
extension Vault{
    static func loadTestData(modelContext: ModelContext) {
        modelContext.insert(Vault(name: "test", pubkey: "test pubkey", signers:["A","B","C"], createdAt: Date.now))
        modelContext.insert(Vault(name: "test 1", pubkey: "test 1 pubkey", signers:["C","D","E"], createdAt: Date.now))
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
