//
//  TokenSelectionView+macOS.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-09-19.
//

#if os(macOS)
import SwiftUI

extension TokenSelectionView {
    var content: some View {
        ZStack {
            Background()
            main
            
            if let error = tokenViewModel.error {
                errorView(error: error)
            }
        }
        .navigationBarBackButtonHidden(true)
    }
    
    var main: some View {
        VStack(spacing: 0) {
            headerMac
            view
        }
    }
    
    var headerMac: some View {
        HStack {
            TokenSelectionHeader(title: "chooseTokens", chainDetailView: chainDetailView)
            
            Spacer()
            
            // Add subtle loading indicator in header
            if tokenViewModel.isLoading {
                HStack(spacing: 6) {
                    ProgressView()
                        .scaleEffect(0.6)
                        .progressViewStyle(CircularProgressViewStyle(tint: .neutral0))
                    Text("Loading tokens...")
                        .font(Theme.fonts.caption12)
                        .foregroundColor(.neutral0)
                        .opacity(0.8)
                }
                .padding(.trailing, 40)
            }
        }
    }
    
    var view: some View {
        VStack(alignment: .leading, spacing: 0) {
            search
            addCustomTokenButton
            Separator()
            scrollView
        }
    }
    
    var scrollView: some View {
        ScrollView {
            list
                .scrollContentBackground(.hidden)
                .padding(.top, 24)
                .padding(.horizontal, 40)
                .padding(.bottom, 50)
                .colorScheme(.dark)
        }
    }

    var addCustomTokenButton: some View {
        Button {
            chainDetailView.sheetType = .customToken
        } label: {
            chainDetailView.chooseTokensButton(NSLocalizedString("customToken", comment: "Custom Token"))
        }
        .background(Color.clear)
        .padding(.horizontal, 40)
    }

    var textField: some View {
        TextField(NSLocalizedString("Search", comment: "Search").toFormattedTitleCase(), text: $tokenViewModel.searchText)
            .font(Theme.fonts.bodyMRegular)
            .foregroundColor(.neutral0)
            .submitLabel(.next)
            .disableAutocorrection(true)
            .textContentType(.oneTimeCode)
            .padding(.horizontal, 8)
            .borderlessTextFieldStyle()
            .maxLength( $tokenViewModel.searchText)
            .colorScheme(.dark)
    }
    
    var saveButton: some View {
        Button(action: {
            saveAssets()
            self.chainDetailView.sheetType = nil
            dismiss()
        }) {
            HStack(spacing: 8) {
                if tokenViewModel.isLoading {
                    ProgressView()
                        .scaleEffect(0.6)
                        .progressViewStyle(CircularProgressViewStyle(tint: .neutral0))
                }
                Text("Save")
                    .foregroundColor(Color.neutral0)
            }
        }
        .padding(.horizontal, 32)
        .frame(height: 44)
        .background(Color.blue600)
        .cornerRadius(12)
    }
}
#endif
