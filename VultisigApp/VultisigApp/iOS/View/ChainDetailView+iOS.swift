//
//  ChainDetailView+iOS.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-09-19.
//

#if os(iOS)
import SwiftUI

extension ChainDetailView {
    var content: some View {
        ZStack {
            Background()
            main
            
            PopupCapsule(text: "addressCopied", showPopup: $showAlert)
        }
        .navigationTitle(NSLocalizedString(group.name, comment: ""))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: Placement.topBarTrailing.getPlacement()) {
                NavigationRefreshButton() {
                    refreshAction()
                }
            }
        }
    }
    
    var main: some View {
        view
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
            .padding(.vertical, 30)
        }
    }
    
    var addButton: some View {
        Button {
            sheetType = .tokenSelection
        } label: {
            chooseTokensButton(NSLocalizedString("chooseTokens", comment: "Choose Tokens"))
        }
    }
    
}
#endif
