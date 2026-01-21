//
//  FastVaultSetPasswordView+macOS.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-09-18.
//

#if os(macOS)
import SwiftUI

extension FastVaultSetPasswordView {
    var content: some View {
        ZStack {
            Background()
            view

            if isLoading {
                Loader()
            }
        }
        .crossPlatformToolbar()
    }

    var view: some View {
        VStack {
            passwordField
            Spacer()
            button
        }
        .padding(.horizontal, 25)
    }
}
#endif
