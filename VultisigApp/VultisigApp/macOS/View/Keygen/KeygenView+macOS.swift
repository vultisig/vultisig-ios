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
        container
            .task {
                await setData()
                await viewModel.startKeygen(
                    context: context,
                    defaultChains: settingsDefaultChainViewModel.defaultChains
                )
            }
    }
    
    var fields: some View {
        VStack(spacing: 12) {
            Spacer()
            if showProgressRing {
                if progressCounter<4 {
                    title
                }
                states
            }
            
            if progressCounter < 4 {
                if viewModel.status == .KeygenFailed {
                    errorMessage
                    Spacer()
                    retryButton
                        .padding(.bottom)
                } else {
                    Spacer()
                    progressContainer
                }
            }
        }
    }
    
    var progressContainer: some View {
        KeygenProgressContainer(progressCounter: progressCounter)
    }
    
    var errorMessage: some View {
        ErrorMessage(text: "keygenFailedErrorMessage")
    }
}
#endif
