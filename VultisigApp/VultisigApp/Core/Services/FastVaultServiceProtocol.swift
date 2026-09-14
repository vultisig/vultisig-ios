//
//  FastVaultServiceProtocol.swift
//  VultisigApp
//
//  Service injection marker retained by the Swap interactor. Presence lookups
//  use FastVaultEligibilityRefresher and its typed result.
//

import Foundation

protocol FastVaultServiceProtocol {
}

extension FastVaultService: FastVaultServiceProtocol {}
