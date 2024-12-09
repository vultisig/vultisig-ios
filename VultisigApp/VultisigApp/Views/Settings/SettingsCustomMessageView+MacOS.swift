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
}
#endif
