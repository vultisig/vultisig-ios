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
        view
    }

    var customMessageContent: some View {
        VStack(spacing: 16) {
            title(text: "Method").padding(.top, 16.0)
            methodTextField
            title(text: "Message")
            messageTextField
        }
        .padding()
    }
}
#endif
