//
//  TransactionHistoryRouteBuilder.swift
//  VultisigApp
//

import SwiftUI

struct TransactionHistoryRouteBuilder {

    @ViewBuilder
    func buildListScreen(pubKeyECDSA: String, vaultName: String, chainFilter: Chain?) -> some View {
        TransactionHistoryScreen(
            pubKeyECDSA: pubKeyECDSA,
            vaultName: vaultName,
            chainFilter: chainFilter
        )
    }
}
