//
//  KeygenView+imacOS.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-09-18.
//

#if os(macOS)
import SwiftUI

extension KeygenView {
    var content: some View {
        VStack {
            fields
            
            if viewModel.status != .KeygenFailed {
                instructions
            }
        }
        .navigationTitle(NSLocalizedString("joinKeygen", comment: ""))
        .task {
            await setData()
            await viewModel.startKeygen(
                context: context,
                defaultChains: settingsDefaultChainViewModel.defaultChains
            )
        }
    }
    
    var keygenViewInstructions: some View {
        KeygenViewInstructionsMac()
            .padding(.vertical, 30)
    }
}
#endif
