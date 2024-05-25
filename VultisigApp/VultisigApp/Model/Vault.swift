//
//  Vault.swift
//  VultisigApp

import Foundation
import SwiftData
import WalletCore

@Model
final class Vault: ObservableObject, Codable {
    @Attribute(.unique) var name: String
    @Attribute(.unique) var pubKeyECDSA: String = ""
    @Attribute(.unique) var pubKeyEdDSA: String = ""
    
    var signers: [String] = []
    var createdAt: Date = Date.now
    var hexChainCode: String = ""
    var keyshares = [KeyShare]()

/// Note: it is important to record the localPartID of the vault, when the vault is created, the local party id has been record as part of it's local keyshare , and keygen committee thus , when user change their device name , or if they lost the original device , and restore the keyshare to a new device , keysign can still work
    var localPartyID: String = ""
    var resharePrefix: String? = nil
    var order: Int = 0
    @Relationship(deleteRule: .cascade) var coins = [Coin]()
    
    enum CodingKeys: CodingKey {
        case name
        case signers
        case createdAt
        case pubKeyECDSA
        case pubKeyEdDSA
        case hexChainCode
        case keyshares
        case localPartyID
        case resharePrefix
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
        resharePrefix = try container.decodeIfPresent(String.self, forKey: .resharePrefix)
    }
    
    init(name: String) {
        self.name = name
    }
    
    init(name: String, signers: [String], pubKeyECDSA: String, pubKeyEdDSA: String, keyshares: [KeyShare], localPartyID: String, hexChainCode: String, resharePrefix: String?) {
        self.name = name
        self.signers = signers
        self.createdAt = Date.now
        self.pubKeyECDSA = pubKeyECDSA
        self.pubKeyEdDSA = pubKeyEdDSA
        self.keyshares = keyshares
        self.localPartyID = localPartyID
        self.hexChainCode = hexChainCode
        self.resharePrefix = resharePrefix
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
        try container.encodeIfPresent(resharePrefix, forKey: .resharePrefix)
    }
    
    func addKeyshare(pubkey: String, keyshare: String) {
        let share = KeyShare(pubkey: pubkey, keyshare: keyshare)
        keyshares.append(share)
    }
    
    func setOrder(_ index: Int) {
        order = index
    }
    
    func getThreshold() -> Int {
        let totalSigners = signers.count
        let threshold = Int(ceil(Double(totalSigners) * 2.0 / 3.0)) - 1
        return threshold
    }

    static func predicate(searchName: String) -> Predicate<Vault> {
        #Predicate<Vault> { vault in
            searchName.isEmpty || vault.name == searchName
        }
    }
    
    static let example = Vault(name: "Bitcoin", signers: [], pubKeyECDSA: "ECDSAKey", pubKeyEdDSA: "EdDSAKey", keyshares: [], localPartyID: "partyID", hexChainCode: "hexCode", resharePrefix: nil)
}
