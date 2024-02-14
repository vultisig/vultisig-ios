//
//  CoinsList.swift
//  VoltixApp
//

import SwiftData
import SwiftUI

struct CoinsList: View {
    @Binding var presentationStack: [CurrentScreen]
    @EnvironmentObject var appState: ApplicationState
    @Query var coins: [Coin]
    @State private var selection = Set<Coin>()
    var body: some View {
        ScrollView {
            List(coins, id: \.self, selection: $selection) { c in
                Image(systemName: self.selection.contains(c) ? "checkmark.circle" : "circle")
                Text("\(c.chain.name) - \(c.symbol)")
            }
        }
    }
}

#Preview {
    CoinsList(presentationStack: .constant([]))
}
