//
//  SettingsCustomMessageView+iOS.swift
//  VultisigApp
//
//  Created by Artur Guseinov on 09.12.2024.
//

#if os(iOS)
import SwiftUI

extension SettingsCustomMessageView {

    var main: some View {
        VStack {
            view
        }
        .navigationTitle(NSLocalizedString(viewModel.state.title, comment: ""))
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(viewModel.state != .initial)
        .toolbar {
            if viewModel.state != .initial {
                ToolbarItem(placement: Placement.topBarLeading.getPlacement()) {
                    backButton
                }
            }
        }
    }

    var customMessageContent: some View {
        VStack(spacing: 16) {
            textField(title: "Signing method", text: $method)
            textField(title: "Message to sign", text: $message)
        }
        .padding(.top, 12)
    }
}
#endif
