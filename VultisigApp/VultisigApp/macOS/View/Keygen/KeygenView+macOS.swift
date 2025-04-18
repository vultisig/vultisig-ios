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
            .navigationTitle(NSLocalizedString(tssType == .Migrate ? "" : "joinKeygen", comment: ""))
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
            header
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
    
    var header: some View {
        GeneralMacHeader(title: tssType == .Migrate ? "" : "joinKeygen", showActions: false)
    }
    
    var progressContainer: some View {
        KeygenProgressContainer(progressCounter: progressCounter)
    }
}
#endif
