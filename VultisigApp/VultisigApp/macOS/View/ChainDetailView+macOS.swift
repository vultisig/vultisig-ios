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
            
            PopupCapsule(text: "addressCopied", showPopup: $showAlert)
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
            .background(Theme.colors.bgPrimary)
            .colorScheme(.dark)
            .padding(.horizontal, 16)
            .padding(.horizontal, 24)
            .padding(.vertical, 8)
        }
    }
    
    var addButton: some View {
        EmptyView()
//        NavigationLink {
//            sheetView
//                .onAppear {
//                    sheetType = .tokenSelection
//                }
//        } label: {
//            chooseTokensButton(NSLocalizedString("chooseTokens", comment: "Choose Tokens"))
//        }
    }
    
}
#endif
