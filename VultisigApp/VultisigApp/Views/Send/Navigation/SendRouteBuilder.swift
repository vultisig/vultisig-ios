//
//  SendRouteBuilder.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 13/08/2025.
//

import SwiftUI

struct SendRouteBuilder {
    
    @ViewBuilder
    func buildDetailsScreen(
        tx: SendTransaction,
        sendCryptoViewModel: SendCryptoViewModel,
        sendDetailsViewModel: SendDetailsViewModel,
        vault: Vault
    ) -> some View {
        SendDetailsScreen(
            tx: tx,
            sendCryptoViewModel: sendCryptoViewModel,
            sendDetailsViewModel: sendDetailsViewModel,
            vault: vault
        )
    }
}
