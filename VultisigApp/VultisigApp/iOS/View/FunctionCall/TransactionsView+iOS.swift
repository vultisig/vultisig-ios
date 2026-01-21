//
//  TransactionsView+iOS.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-09-21.
//

#if os(iOS)
import SwiftUI

extension TransactionsView {
    var content: some View {
        ZStack {
            Background()
            main
        }
        .navigationTitle(NSLocalizedString("transactions", comment: "Transactions"))
        .navigationBarTitleDisplayMode(.inline)
    }

    var main: some View {
        view
    }
}
#endif
