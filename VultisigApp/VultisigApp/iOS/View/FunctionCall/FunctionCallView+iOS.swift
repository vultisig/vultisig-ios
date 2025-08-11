//
//  FunctionCallView+iOS.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-09-18.
//

#if os(iOS)
import SwiftUI

extension FunctionCallView {
    var content: some View {
        ZStack {
            Background()
            main
        }
        .navigationBarBackButtonHidden(functionCallViewModel.currentIndex != 1 ? true : false)
        .navigationTitle(NSLocalizedString(functionCallViewModel.currentTitle, comment: "SendCryptoView title"))
        .navigationBarTitleDisplayMode(.inline)
        .ignoresSafeArea(.keyboard)
        .toolbar {
            if functionCallViewModel.currentIndex != 1 {
                ToolbarItem(placement: Placement.topBarLeading.getPlacement()) {
                    backButton
                }
            }
            if functionCallViewModel.currentIndex == 3 {
                    ToolbarItem(placement: Placement.topBarTrailing.getPlacement()) {
                        NavigationQRShareButton(
                            vault: vault,
                            type: .Keysign,
                            viewModel: shareSheetViewModel
                        )
                    }
                }
        }
    }
    
    var main: some View {
        layers
    }
    
    var layers: some View {
        ZStack {
            Background()
            view
            
            if functionCallViewModel.isLoading || functionCallVerifyViewModel.isLoading {
                loader
            }
        }
        .onTapGesture {
            hideKeyboard()
        }
    }
    
    var backButton: some View {
        let isDone = functionCallViewModel.currentIndex==5
        
        return Button {
            functionCallViewModel.handleBackTap()
        } label: {
            NavigationBlankBackButton()
        }
        .opacity(isDone ? 0 : 1)
        .disabled(isDone)
    }
}
#endif
