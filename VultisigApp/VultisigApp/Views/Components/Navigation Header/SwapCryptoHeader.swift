//
//  SwapCryptoHeader.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-08-09.
//

import SwiftUI

struct SwapCryptoHeader: View {
    @ObservedObject var swapViewModel: SwapCryptoViewModel
    @ObservedObject var shareSheetViewModel: ShareSheetViewModel
    
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        HStack {
            leadingAction
            Spacer()
            text
            Spacer()
            trailingAction
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 40)
        .padding(.top, 8)
    }
    
    var leadingAction: some View {
        backButton
    }
    
    var text: some View {
        Text(NSLocalizedString(swapViewModel.currentTitle, comment: "SendCryptoView title"))
            .foregroundColor(.neutral0)
            .font(.title3)
    }
    
    var trailingAction: some View {
        ZStack {
            NavigationQRShareButton(title: "swap", renderedImage: shareSheetViewModel.renderedImage)
                .opacity(swapViewModel.currentIndex==3 ? 1 : 0)
                .disabled(swapViewModel.currentIndex != 3)
        }
    }
    
    var backButton: some View {
        let isDone = swapViewModel.currentIndex==5
        
        return Button {
            handleBackTap()
        } label: {
            NavigationBlankBackButton()
        }
        .opacity(isDone ? 0 : 1)
        .disabled(isDone)
    }
    
    private func handleBackTap() {
        guard swapViewModel.currentIndex>1 else {
            dismiss()
            return
        }
        
        swapViewModel.handleBackTap()
    }
}

#Preview {
    SwapCryptoHeader(swapViewModel: SwapCryptoViewModel(), shareSheetViewModel: ShareSheetViewModel())
}
