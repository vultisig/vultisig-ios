//
//  TransactionHistoryRoute.swift
//  VultisigApp
//

import Foundation

enum TransactionHistoryRoute: Hashable {
    case list(pubKeyECDSA: String, vaultName: String, chainFilter: Chain?)
}
