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
                VStack {
                    view
                }
            }
            .navigationBarItems(leading: backButton)
            .navigationBarTitleTextColor(.neutral0)
            .navigationBarTitleDisplayMode(.inline)
            .navigationTitle(NSLocalizedString("password", comment: ""))
        }
    }

    var backButton: some View {
        Button(action: {
            dismiss()
        }) {
            Image("x")
                .font(.body18MenloBold)
                .foregroundColor(Color.neutral0)
        }
    }
}
#endif
