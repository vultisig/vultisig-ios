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
        VStack {
            headerMac
            view
        }
    }

    var headerMac: some View {
        GeneralMacHeader(title: viewModel.state.title)
    }
    
    var button: some View {
        buttonLabel
            .padding(.horizontal)
            .padding(.bottom)
    }
    
    var customMessageContent: some View {
        VStack(spacing: 16) {
            title(text: "Method").padding(.top, 16.0)
            textField(title: "Signing method", text: $method)
            title(text: "Message")
            textField(title: "Message to sign", text: $message)
        }
        .padding()
    }
}
#endif
