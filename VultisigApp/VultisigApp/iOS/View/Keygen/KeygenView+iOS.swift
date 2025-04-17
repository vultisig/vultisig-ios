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
            .navigationTitle(NSLocalizedString("creatingVault", comment: ""))
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
    
    var progressContainer: some View {
        KeygenProgressContainer(progressCounter: progressCounter)
            .padding(.bottom, idiom == .phone ? 10 : 50)
    }
}
#endif
