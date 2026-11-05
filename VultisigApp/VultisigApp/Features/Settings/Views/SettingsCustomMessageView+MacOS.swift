//
//  SettingsCustomMessageView+macOS.swift
//  VultisigApp
//
//  Created by Artur Guseinov on 09.12.2024.
//

#if os(macOS)
import SwiftUI

extension SettingsCustomMessageView {

    var main: some View {
        VStack(spacing: 18) {
            switch viewModel.state {
            case .initial:
                customMessage
                    .crossPlatformToolbar(viewModel.state.title)
            case .verify:
                verify
                    .crossPlatformToolbar(viewModel.state.title)
            case .pair:
                pair
            case .keysign, .done:
                keysign
            }
        }
    }

    var customMessageContent: some View {
        VStack(spacing: 16) {
            title(text: "method".localized).padding(.top, 16.0)
            textField(title: "signingMethod", text: $method)
            title(text: "message".localized)
            textField(title: "messageToSign", text: $message)
        }
        .padding()
    }
}
#endif
