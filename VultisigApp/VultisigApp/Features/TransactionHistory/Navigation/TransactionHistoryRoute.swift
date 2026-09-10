//
//  TransactionHistoryRoute.swift
//  VultisigApp
//

import Foundation

enum TransactionHistoryRoute: Hashable {
    case detail(recordID: UUID)
    case list(pubKeyECDSA: String, vaultName: String, chainFilter: Chain?)
}
