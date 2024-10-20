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
            
            if tokenViewModel.isLoading {
                Loader()
            }
        }
        .navigationBarBackButtonHidden(true)
        .navigationTitle(NSLocalizedString("chooseTokens", comment: "Choose Tokens"))
        .toolbar {
            ToolbarItem(placement: Placement.topBarLeading.getPlacement()) {
                Button(action: {
                    self.chainDetailView.sheetType = nil
                    dismiss()
                }) {
                    Image(systemName: "chevron.backward")
                        .font(.body18MenloBold)
                        .foregroundColor(Color.neutral0)
                }
            }
            ToolbarItem(placement: Placement.topBarTrailing.getPlacement()) {
                saveButton
            }
            
            ToolbarItem(placement: Placement.principal.getPlacement()) {
                searchBar
            }
        }
    }
    
    var main: some View {
        view
    }
    
    var addCustomTokenButton: some View {
        Button {
            chainDetailView.sheetType = .customToken
        } label: {
            chainDetailView.chooseTokensButton(NSLocalizedString("customToken", comment: "Custom Token"))
        }
        .background(Color.clear)
        .padding(.horizontal, 25)
    }
    
    var view: some View {
        VStack(alignment: .leading, spacing: 0) {
            addCustomTokenButton
            scrollView
        }
        .padding(.bottom, 50)
    }
    
    var scrollView: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 24, pinnedViews: []) {
                let selected = tokenViewModel.selectedTokens
                if !selected.isEmpty {
                    Section(header: Text(NSLocalizedString("Selected", comment:"Selected")).background(Color.backgroundBlue)) {
                        ForEach(selected, id: \.self) { token in
                            TokenSelectionCell(chain: group.chain, address: address, asset: token, tokenSelectionViewModel: tokenViewModel)
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                        }
                    }
                }
                
                if tokenViewModel.searchText.isEmpty {
                    Section(header: Text(NSLocalizedString("tokens", comment:"Tokens"))) {
                        ForEach(tokenViewModel.preExistTokens, id: \.self) { token in
                            TokenSelectionCell(chain: group.chain, address: address, asset: token, tokenSelectionViewModel: tokenViewModel)
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                        }
                    }
                } else {
                    Section(header: Text(NSLocalizedString("searchResult", comment:"Search Result"))) {
                        let filtered = tokenViewModel.searchedTokens
                        if !filtered.isEmpty {
                            ForEach(filtered, id: \.self) { token in
                                TokenSelectionCell(chain: group.chain, address: address, asset: token, tokenSelectionViewModel: tokenViewModel)
                                    .listRowBackground(Color.clear)
                                    .listRowSeparator(.hidden)
                            }
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .padding(.horizontal, 25)
            .listStyle(.grouped)
        }
    }
    
    var textField: some View {
        TextField(NSLocalizedString("Search", comment: "Search").toFormattedTitleCase(), text: $tokenViewModel.searchText)
            .font(.body16Menlo)
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
        Button(action: {
            self.chainDetailView.sheetType = nil
            dismiss()
        }) {
            Text("Save")
                .foregroundColor(.blue)
        }
    }
}
#endif
