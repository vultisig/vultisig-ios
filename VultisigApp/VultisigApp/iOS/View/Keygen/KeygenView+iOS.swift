//
//  KeygenView+iOS.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-09-18.
//

#if os(iOS)
import SwiftUI

extension KeygenView {
    private var idiom : UIUserInterfaceIdiom { UIDevice.current.userInterfaceIdiom }
    
    var content: some View {
        container
            .navigationTitle(NSLocalizedString(tssType == .Migrate ? "" : "creatingVault", comment: ""))
            .navigationBarTitleDisplayMode(.inline)
            .task {
                await setData()
                await viewModel.startKeygen(
                    context: context,
                    defaultChains: settingsDefaultChainViewModel.defaultChains
                )
            }
            .onAppear {
                UIApplication.shared.isIdleTimerDisabled = true
            }
            .onDisappear(){
                UIApplication.shared.isIdleTimerDisabled = false
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
            .padding(.bottom, idiom == .phone ? 10 : 50)
    }
}
#endif
