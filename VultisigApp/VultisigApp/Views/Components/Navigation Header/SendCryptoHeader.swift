//
//  SendCryptoHeader.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-08-09.
//

import SwiftUI

struct SendCryptoHeader: View {
    let tx: SendTransaction
    let vault: Vault
    let showFeeSettings: Bool
    @Binding var settingsPresented: Bool
    @ObservedObject var sendCryptoViewModel: SendCryptoViewModel
    @ObservedObject var shareSheetViewModel: ShareSheetViewModel
    
    @State var animate: Bool = false
    @State var enableTransition: Bool = true
    
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
        Text(NSLocalizedString(sendCryptoViewModel.currentTitle, comment: ""))
            .foregroundColor(.neutral0)
            .font(.title3)
    }
    
    var trailingAction: some View {
        ZStack {
            NavigationQRShareButton(
                vault: vault, 
                type: .Keysign,
                renderedImage: shareSheetViewModel.renderedImage
            )
            .opacity(sendCryptoViewModel.currentIndex == 3 ? 1 : 0)
            .disabled(sendCryptoViewModel.currentIndex != 3)

            HStack(spacing: 32) {
                Button {
                    refreshData()
                } label: {
                    Image(systemName: "arrow.clockwise.circle")
                        .rotationEffect(.degrees(animate ? 360 : 0))
                        .animation(enableTransition ? .easeInOut(duration: 1) : nil, value: animate)
                }
                
                if showFeeSettings {
                    Button {
                        settingsPresented = true
                    } label: {
                        Image(systemName: "fuelpump")
                    }
                }
            }
            .foregroundColor(.neutral0)
            .font(.body16Menlo)
            .opacity(sendCryptoViewModel.currentIndex == 1 ? 1 : 0)
            .disabled(sendCryptoViewModel.currentIndex != 1)
        }
    }
    
    var backButton: some View {
        let isDone = sendCryptoViewModel.currentIndex==5
        
        return Button {
            handleBackTap()
        } label: {
            NavigationBlankBackButton()
        }
        .opacity(isDone ? 0 : 1)
        .disabled(isDone)
    }
    
    private func handleBackTap() {
        guard sendCryptoViewModel.currentIndex>1 else {
            dismiss()
            return
        }
        
        sendCryptoViewModel.handleBackTap(dismiss)
    }
    
    private func refreshData() {
        Task {
            await sendCryptoViewModel.loadGasInfoForSending(tx: tx)
        }
        
        animate = true
        enableTransition = true
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            enableTransition = false
            animate = false
        }
    }
}

#Preview {
    ZStack {
        Background()
        SendCryptoHeader(
            tx: SendTransaction(),
            vault: Vault.example,
            showFeeSettings: true,
            settingsPresented: .constant(false),
            sendCryptoViewModel: SendCryptoViewModel(),
            shareSheetViewModel: ShareSheetViewModel()
        )
    }
}
