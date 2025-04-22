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
            Spacer()
            
            if progressCounter < 4 {
                if viewModel.status == .KeygenFailed {
                    retryButton
                } else {
                    progressContainer
                }
            }
        }
    }
    
    var progressContainer: some View {
        KeygenProgressContainer(progressCounter: progressCounter)
    }
}
#endif
