//
//  TransactionHistoryRouter.swift
//  VultisigApp
//

import SwiftUI

struct TransactionHistoryRouter {
    private let viewBuilder = TransactionHistoryRouteBuilder()

    @ViewBuilder
    func build(_ route: TransactionHistoryRoute) -> some View {
        switch route {
        case .list(let pubKeyECDSA, let vaultName, let chainFilter):
            viewBuilder.buildListScreen(
                pubKeyECDSA: pubKeyECDSA,
                vaultName: vaultName,
                chainFilter: chainFilter
            )
        }
    }
}
