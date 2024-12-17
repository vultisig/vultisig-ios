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
    }
}
#endif
