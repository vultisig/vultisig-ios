//
//  TransactionsView+macOS.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-09-21.
//

#if os(macOS)
import SwiftUI

extension TransactionsView {
    var content: some View {
        ZStack {
            Background()
            view
        }
        .crossPlatformToolbar("transactions".localized)
    }
}
#endif
