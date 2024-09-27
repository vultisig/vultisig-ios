//
//  ChainDetailView+macOS.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-09-19.
//

#if os(macOS)
import SwiftUI

extension ChainDetailView {
    var content: some View {
        ZStack {
            Background()
            main
            
            if isLoading {
                Loader()
            }
            
            PopupCapsule(text: "addressCopied", showPopup: $showAlert)
        }
        .safeAreaInset(edge: .bottom) {
            if group.chain == .base {
                #if DEBUG
                weweButton()
                #endif
            }
        }
    }
    
    var main: some View {
        VStack {
            headerMac
            view
        }
    }
    
    var headerMac: some View {
        ChainDetailHeader(title: group.name, refreshAction: refreshAction)
    }
    
    var view: some View {
        ScrollView {
            VStack(spacing: 20) {
                actionButtons
                views
                
                if viewModel.hasTokens(chain: group.chain) {
                    addButton
                }
            }
            .buttonStyle(BorderlessButtonStyle())
            .background(Color.backgroundBlue)
            .colorScheme(.dark)
            .padding(.horizontal, 16)
            .padding(.horizontal, 24)
            .padding(.vertical, 8)
        }
    }
    
    var addButton: some View {
        NavigationLink {
            sheetView
                .onAppear {
                    sheetType = .tokenSelection
                }
        } label: {
            chooseTokensButton(NSLocalizedString("chooseTokens", comment: "Choose Tokens"))
        }
    }
    
    func weweButton() -> some View {
        Button {
            viewModel.selectWeweIfNeeded(vault: vault)
            isWeweLinkActive = true
        } label: {
            FilledLabelButton {
                HStack(spacing: 10) {
                    Image("BuyWewe")
                    Text("BUY $WEWE")
                        .foregroundColor(.blue600)
                        .font(.body14MontserratBold)
                }
                .frame(height: 44)
            }
        }
        .padding(40)
    }
}
#endif
