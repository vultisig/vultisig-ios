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
            
            if isLoading {
                Loader()
            }
            
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
            .background(Color.backgroundBlue)
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
                        .font(.body16MontserratBold)
                }
                .frame(height: 44)
            }
        }
        .padding(40)
    }
}
#endif
