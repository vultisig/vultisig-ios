//
//  JoinKeygenView+iOS.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-09-18.
//

#if os(iOS)
import SwiftUI
import CodeScanner

extension JoinKeygenView {
    var content: some View {
        ZStack {
            Background()
            shadow
                .showIf(viewModel.status != .KeygenStarted)
            
            if viewModel.areVaultsMismatched {
                vaultsMismatchedError
            } else {
                main
            }
        }
        .navigationTitle(NSLocalizedString("joinKeygen", comment: "Join keygen/reshare"))
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(hideBackButton)
        .toolbar {
            ToolbarItem(placement: Placement.topBarTrailing.getPlacement()) {
                NavigationHelpButton()
            }
        }
    }

    var main: some View {
        VStack(spacing: .zero) {
            Spacer()
            states
            Spacer()
        }
    }
}
#endif
