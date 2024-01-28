//
//  Vault.swift
//  VoltixApp

import Foundation
import SwiftData

@Model
final class Vault{
    let name: String
    let pubkey: String
    let signers: [String]
    let createdAt: Date
    
    init(name: String, pubkey: String, signers: [String], createdAt: Date) {
        self.name = name
        self.pubkey = pubkey
        self.signers = signers
        self.createdAt = createdAt
    }
}
