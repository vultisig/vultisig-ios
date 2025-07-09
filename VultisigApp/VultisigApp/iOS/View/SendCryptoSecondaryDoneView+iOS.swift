//
//  SendCryptoSecondaryDoneView+iOS.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2025-07-09.
//

#if os(iOS)
import SwiftUI

extension SendCryptoSecondaryDoneView {
    var container: some View {
        ZStack {
            Background()
            content
        }
        .navigationTitle(NSLocalizedString("transactionDetails", comment: ""))
    }
}
#endif
