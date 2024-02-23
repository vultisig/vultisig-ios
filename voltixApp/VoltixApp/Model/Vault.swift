//
//  Vault.swift
//  VoltixApp

import Foundation
import SwiftData
import WalletCore

@Model
final class Vault: ObservableObject, Codable {
    @Attribute(.unique) var name: String
    var signers: [String] = [String]()
    var createdAt: Date = Date.now
    var pubKeyECDSA: String = ""
    var pubKeyEdDSA: String = ""
    var hexChainCode: String = ""
    
    var keyshares = [KeyShare]()
    // it is important to record the localPartID of the vault, when the vault is created, the local party id has been record as part of it's local keyshare , and keygen committee
    // thus , when user change their device name , or if they lost the original device , and restore the keyshare to a new device , keysign can still work
    var localPartyID: String = ""
    
    var coins = [Coin]()
    
    enum CodingKeys: CodingKey {
        case name
        case signers
        case createdAt
        case pubKeyECDSA
        case pubKeyEdDSA
        case hexChainCode
        case keyshares
        case localPartyID
    }
    
    required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        signers = try container.decode([String].self, forKey: .signers)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        pubKeyECDSA = try container.decode(String.self, forKey: .pubKeyECDSA)
        pubKeyEdDSA = try container.decode(String.self, forKey: .pubKeyEdDSA)
        hexChainCode = try container.decode(String.self, forKey: .hexChainCode)
        keyshares = try container.decode([KeyShare].self, forKey: .keyshares)
        localPartyID = try container.decode(String.self, forKey: .localPartyID)
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encode(signers, forKey: .signers)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(pubKeyECDSA, forKey: .pubKeyECDSA)
        try container.encode(pubKeyEdDSA, forKey: .pubKeyEdDSA)
        try container.encode(hexChainCode, forKey: .hexChainCode)
        try container.encode(keyshares, forKey: .keyshares)
        try container.encode(localPartyID, forKey: .localPartyID)
    }
    
    init(name: String) {
        self.name = name
    }
    
    init(name: String, signers: [String], pubKeyECDSA: String, pubKeyEdDSA: String, keyshares: [KeyShare], localPartyID: String, hexChainCode: String) {
        self.name = name
        self.signers = signers
        createdAt = Date.now
        self.pubKeyECDSA = pubKeyECDSA
        self.pubKeyEdDSA = pubKeyEdDSA
        self.keyshares = keyshares
        self.localPartyID = localPartyID
        self.hexChainCode = hexChainCode
    }
    
    func addKeyshare(pubkey: String, keyshare: String) {
        let share = KeyShare(pubkey: pubkey, keyshare: keyshare)
        keyshares.append(share)
    }
    
    func getThreshold() -> Int {
        let totalSigners = signers.count
        let threshold = Int(ceil(Double(totalSigners) * 2.0 / 3.0)) - 1
        return threshold
    }
    
    static func predicate(searchName: String) -> Predicate<Vault> {
        return #Predicate<Vault> { vault in
            searchName.isEmpty || vault.name == searchName
        }
    }
}

struct KeyShare: Codable {
    let pubkey: String
    let keyshare: String
}

// define some functions used for test
extension Vault {
    static func loadTestData(modelContext: ModelContext) {
        modelContext.insert(Vault(name: "test", signers: ["A", "B", "C"], pubKeyECDSA: "ECDSA PubKey", pubKeyEdDSA: "EdDSA PubKey", keyshares: [KeyShare](), localPartyID: "first", hexChainCode: ""))
        modelContext.insert(Vault(name: "test 1", signers: ["C", "D", "E"], pubKeyECDSA: "ECDSA PubKey", pubKeyEdDSA: "EdDSA PubKey", keyshares: [KeyShare](), localPartyID: "second", hexChainCode: ""))
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
}
