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
    // it is important to record the localPartID of the vault, when the vault is created, the local party id has been record as part of it's local keyshare , and keygen committee
    // thus , when user change their device name , or if they lost the original device , and restore the keyshare to a new device , keysign can still work
    var localPartyID: String = ""
    var coins = [Coin]()
    
    init(name: String){
        self.name = name
    }
    
    init(name: String, signers: [String], pubKeyECDSA: String, pubKeyEdDSA: String, keyshares: [KeyShare], localPartyID: String) {
        self.name = name
        self.signers = signers
        self.createdAt = Date.now
        self.pubKeyECDSA = pubKeyECDSA
        self.pubKeyEdDSA = pubKeyEdDSA
        self.keyshares = keyshares
        self.localPartyID = localPartyID
    }
    
    func addKeyshare(pubkey: String, keyshare:String) {
        let share = KeyShare(pubkey: pubkey, keyshare: keyshare)
        self.keyshares.append(share)
    }
    
    func getThreshold() -> Int {
        let totalSigners = self.signers.count
        let threshold = Int(ceil(Double(totalSigners) * 2.0 / 3.0)) - 1
        return threshold
    }
    
    static func predicate(searchName: String) ->Predicate<Vault>{
        return #Predicate<Vault>{ vault in
            searchName.isEmpty || vault.name == searchName
        }
    }
}

struct KeyShare : Codable {
    let pubkey: String
    let keyshare: String
}

// define some functions used for test
extension Vault{
    static func loadTestData(modelContext: ModelContext) {
        modelContext.insert(Vault(name: "test", signers:["A","B","C"],  pubKeyECDSA: "ECDSA PubKey", pubKeyEdDSA: "EdDSA PubKey",keyshares: [KeyShare](), localPartyID: "first"))
        modelContext.insert(Vault(name: "test 1", signers:["C","D","E"], pubKeyECDSA: "ECDSA PubKey", pubKeyEdDSA: "EdDSA PubKey",keyshares: [KeyShare](), localPartyID: "second"))
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
