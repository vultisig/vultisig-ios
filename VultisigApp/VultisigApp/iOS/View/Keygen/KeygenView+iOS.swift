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
        VStack {
            fields
            
            if viewModel.status != .KeygenFailed {
                instructions
            }
        }
        .navigationTitle(NSLocalizedString("joinKeygen", comment: ""))
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
    
    var keygenViewInstructions: some View {
        KeygenViewInstructions()
            .padding(.bottom, 30)
    }
}
#endif
