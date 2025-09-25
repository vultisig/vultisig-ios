//
//  SendCryptoDoneContentView.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 22/07/2025.
//

import SwiftUI
import RiveRuntime

struct SendCryptoDoneContentView: View {
    let input: SendCryptoContent
    @Binding var showAlert: Bool
    var onDone: () -> Void = {}
    
    @State var navigateToHome = false
    @State var animationVM: RiveViewModel? = nil
    @EnvironmentObject var homeViewModel: HomeViewModel
    
    var body: some View {
        VStack {
            ScrollView {
                VStack(spacing: 8) {
                    animation
                    SendCryptoDoneHeaderView(
                        coin: input.coin,
                        cryptoAmount: input.amountCrypto,
                        fiatAmount: input.amountFiat.formatToFiat(includeCurrencySymbol: true)
                    )
                    VStack(spacing: 16) {
                        Group {
                            SendCryptoTransactionHashRowView(
                                hash: input.hash,
                                explorerLink: input.explorerLink,
                                showCopy: true,
                                showAlert: $showAlert
                            )
                            Separator()
                                .opacity(0.8)
                        }
                        .showIf(input.hash.isNotEmpty)
                        
                        transactionDetailsButton
                    }
                    .font(Theme.fonts.bodySMedium)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 16)
                    .foregroundColor(Theme.colors.textLight)
                    .background(Theme.colors.bgSecondary)
                    .cornerRadius(16)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(Theme.colors.bgTertiary, lineWidth: 1)
                    )
                }
            }
            
            PrimaryButton(title: "done") {
                onDoneButtonPressed()
            }
        }
        .navigationDestination(isPresented: $navigateToHome) {
            if let vault = homeViewModel.selectedVault {
                HomeScreen(initialVault: vault)
            }
        }
        .onLoad {
            animationVM = RiveViewModel(fileName: "vaultCreatedAnimation", autoPlay: true)
        }
    }
    
    private func onDoneButtonPressed() {
        onDone()
        navigateToHome = true
    }
    
    var transactionDetailsButton: some View {
        NavigationLink {
            SendCryptoSecondaryDoneView(input: input) {
                onDoneButtonPressed()
            }
        } label: {
            HStack {
                Text(NSLocalizedString("transactionDetails", comment: ""))
                Spacer()
                Image(systemName: "chevron.right")
            }
        }
    }
    
    var animation: some View {
        ZStack {
            animationVM?.view()
                .frame(width: 280, height: 280)
            
            animationText
                .offset(y: 50)
        }
    }
    
    var animationText: some View {
        Text(NSLocalizedString("transactionSuccessful", comment: ""))
            .foregroundStyle(LinearGradient.primaryGradient)
            .font(Theme.fonts.bodyLMedium)
    }
}

#Preview {
    SendCryptoDoneView(
        vault: .example,
        hash: "294FF0BCDDA7E79140782FB3F5F759FFEE1C11639194FF500BAB6D92012C615C",
        approveHash: "",
        chain: .thorChain,
        sendTransaction: nil,
        swapTransaction: nil
    )
}
