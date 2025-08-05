//
//  TokenSelectionView+iOS.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-09-19.
//

#if os(iOS)
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
        .navigationTitle(NSLocalizedString("chooseTokens", comment: "Choose Tokens"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: Placement.topBarLeading.getPlacement()) {
                Button(action: {
                    self.chainDetailView.sheetType = nil
                    dismiss()
                }) {
                    Image(systemName: "chevron.backward")
                        .font(Theme.fonts.bodyLMedium)
                        .foregroundColor(Color.neutral0)
                }
            }
            
            // Add subtle loading indicator in navigation bar
            ToolbarItem(placement: Placement.topBarTrailing.getPlacement()) {
                if tokenViewModel.isLoading {
                    ProgressView()
                        .scaleEffect(0.8)
                        .progressViewStyle(CircularProgressViewStyle(tint: .neutral0))
                }
            }
        }
    }
    
    var main: some View {
        view
    }
    
    var view: some View {
        VStack(alignment: .leading, spacing: 0) {
            searchBar
                .padding(.horizontal, 25)
            
            addCustomTokenButton
            scrollView
            saveButton
        }
    }
    
    var scrollView: some View {
        ScrollView {
            list
                .scrollContentBackground(.hidden)
                .padding(.horizontal, 25)
                .listStyle(.grouped)
        }
    }
    
    var addCustomTokenButton: some View {
        Button {
            chainDetailView.sheetType = .customToken
        } label: {
            chainDetailView.chooseTokensButton(NSLocalizedString("customToken", comment: "Custom Token"))
        }
        .background(Color.clear)
        .padding(.horizontal, 25)
        .padding(.top, 25)
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
            .focused($isSearchFieldFocused)
            .textInputAutocapitalization(.never)
            .keyboardType(.default)
    }
    
    var saveButton: some View {
        HStack(spacing: 8) {
            if tokenViewModel.isLoading {
                ProgressView()
                    .scaleEffect(0.8)
                    .progressViewStyle(CircularProgressViewStyle(tint: .neutral0))
            }
            PrimaryButton(title: "save") {
                saveAssets()
                self.chainDetailView.sheetType = nil
                dismiss()
            }
        }
        .padding(.horizontal, 25)
        .padding(.vertical, 12)
    }
}
#endif
