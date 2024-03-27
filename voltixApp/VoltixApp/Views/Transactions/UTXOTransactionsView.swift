//
//  UTXOTransactionsView.swift
//  VoltixApp
//
//  Created by Amol Kumar on 2024-03-26.
//

import SwiftUI

struct UTXOTransactionsView: View {
    let coin: Coin?
    
    @StateObject var tx = SendTransaction()
    @StateObject var utxoTransactionsService: UTXOTransactionsService = .init()
    
    @EnvironmentObject var appState: ApplicationState
    
    var body: some View {
        Text("UTXOTransactionsView")
    }
}

#Preview {
    UTXOTransactionsView(coin: Coin.example)
        .environmentObject(ApplicationState.shared)
}
