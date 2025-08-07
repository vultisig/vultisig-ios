//
//  FastVaultEnterPasswordView+iOS.swift
//  VultisigApp
//
//  Created by Artur Guseinov on 14.09.2024.
//
#if os(iOS)
import SwiftUI

extension FastVaultEnterPasswordView {
    var body: some View {
        NavigationView {
            ZStack {
                Background()
                view

                if isLoading {
                    Loader()
                }
            }
            .navigationBarItems(leading: backButton)
            .navigationBarTitleTextColor(Theme.colors.textPrimary)
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    var backButton: some View {
        Button(action: {
            dismiss()
        }) {
            Image("x")
                .font(Theme.fonts.bodyLMedium)
                .foregroundColor(Theme.colors.textPrimary)
        }
    }
}
#endif
