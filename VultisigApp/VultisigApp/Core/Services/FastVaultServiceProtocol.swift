//
//  FastVaultServiceProtocol.swift
//  VultisigApp
//
//  Test seam over `FastVaultService.exist(pubKeyECDSA:)` — the only call the
//  Swap pilot makes against the FastVault server. Production wiring stays on
//  `FastVaultService.shared`.
//

import Foundation

protocol FastVaultServiceProtocol {
    func exist(pubKeyECDSA: String) async -> Bool
}

extension FastVaultService: FastVaultServiceProtocol {}
