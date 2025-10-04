//
//  NewWalletNameView+macOS.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-09-21.
//

#if os(macOS)
import SwiftUI

extension NewWalletNameView {
    var content: some View {
        ZStack {
            Background()
            view
                .padding(.horizontal, 24)
        }
        .crossPlatformToolbar()
    }
}
#endif
