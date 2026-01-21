//
//  FastVaultSetPasswordView+macOS.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-09-18.
//

#if os(macOS)
import SwiftUI

extension FastVaultSetHintView {
    var content: some View {
        ZStack {
            Background()
            main
        }
        .crossPlatformToolbar()
    }

    var main: some View {
        view
    }

    var view: some View {
        VStack {
            hintField
            Spacer()
            buttons
        }
        .padding(.horizontal, 25)
    }
}
#endif
