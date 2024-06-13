import SwiftUI

struct TokenSelectionView: View {
    let chainDetailView: ChainDetailView
    let vault: Vault
    let group: GroupedChain
    
    @StateObject var tokenViewModel = TokenSelectionViewModel()
    @EnvironmentObject var coinViewModel: CoinSelectionViewModel
    
    // Focus state for the search field to force layout update
    @FocusState private var isSearchFieldFocused: Bool
    @State private var isSearching = false
    
    var body: some View {
        ZStack {
            Background()
            VStack {
                addCustomTokenButton.background(Color.clear).padding()
                view
            }
            
            if let error = tokenViewModel.error {
                errorView(error: error)
            }
            
            if tokenViewModel.isLoading {
                Loader()
            }
        }
        .navigationBarBackButtonHidden(true)
        .navigationTitle(NSLocalizedString("chooseTokens", comment: "Choose Tokens"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button(action: {
                    self.chainDetailView.sheetType = nil
                }) {
                    Image(systemName: "chevron.backward")
                        .font(.body18MenloBold)
                        .foregroundColor(Color.neutral0)
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button(action: {
                    self.chainDetailView.sheetType = nil
                }) {
                    Text("Done")
                        .foregroundColor(.blue)
                }
            }
            ToolbarItem(placement: .principal) {
                ZStack(alignment: .trailing) {
                    HStack {
                        TextField(NSLocalizedString("search", comment: "Search"), text: $tokenViewModel.searchText)
                            .foregroundColor(.neutral0)
                            .submitLabel(.next)
                            .textInputAutocapitalization(.never)
                            .disableAutocorrection(true)
                            .keyboardType(.default)
                            .textContentType(.oneTimeCode)
                            .focused($isSearchFieldFocused)
                            .padding(.horizontal, 8)
                        
                        if isSearching {
                            Button("Cancel") {
                                tokenViewModel.searchText = ""
                                isSearchFieldFocused = false
                                isSearching = false
                            }
                            .foregroundColor(.blue)
                        }
                    }
                    .background(Color.blue600)
                    .cornerRadius(10)
                    .padding(.horizontal, 12)
                    .onChange(of: tokenViewModel.searchText) { oldValue, newValue in
                        isSearching = !newValue.isEmpty
                    }
                }
                .frame(maxWidth: .infinity)
                .font(.body12Menlo)
                .foregroundColor(.neutral0)
                .frame(height: 38)
                .background(Color.blue600)
                .cornerRadius(10)
            }
        }
        .task {
            await tokenViewModel.loadData(chain: group.chain)
        }
        .onAppear {
            isSearchFieldFocused = true
        }
        .onDisappear {
            saveAssets()
        }
    }
    
    var addCustomTokenButton: some View {
        Button {
            chainDetailView.sheetType = .customToken
        } label: {
            chainDetailView.chooseTokensButton(NSLocalizedString("customToken", comment: "Custom Token"))
        }
    }
    
    var view: some View {
        List {
            let selected = tokenViewModel.selectedTokens(groupedChain: group)
            if !selected.isEmpty {
                Section(header: Text(NSLocalizedString("Selected", comment:"Selected"))) {
                    ForEach(selected, id: \.self) { token in
                        TokenSelectionCell(chain: group.chain, address: address, asset: token, tokenSelectionViewModel: tokenViewModel, tokenSelectionView: self)
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                    }
                }
            }
            
            if tokenViewModel.searchText.isEmpty {
                Section(header: Text(NSLocalizedString("tokens", comment:"Tokens"))) {
                    ForEach(tokenViewModel.preExistingTokens(groupedChain: group), id: \.self) { token in
                        TokenSelectionCell(chain: group.chain, address: address, asset: token, tokenSelectionViewModel: tokenViewModel, tokenSelectionView: self)
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                    }
                }
            } else {
                Section(header: Text(NSLocalizedString("searchResult", comment:"Search Result"))) {
                    let filtered = tokenViewModel.filteredTokens(groupedChain: group)
                    if !filtered.isEmpty {
                        ForEach(filtered, id: \.self) { token in
                            TokenSelectionCell(chain: group.chain, address: address, asset: token, tokenSelectionViewModel: tokenViewModel, tokenSelectionView: self)
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                        }
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .listStyle(.grouped)
    }
    
    func errorView(error: Error) -> some View {
        return VStack(spacing: 16) {
            Text(error.localizedDescription)
                .multilineTextAlignment(.center)
                .font(.body16Menlo)
                .foregroundColor(.neutral0)
                .padding(.horizontal, 16)
            
            if tokenViewModel.showRetry {
                Button {
                    Task { await tokenViewModel.loadData(chain: group.chain) }
                } label: {
                    FilledButton(title: "Retry")
                }
                .padding(.horizontal, 40)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    var address: String {
        return vault.coins.first(where: { $0.chain == group.chain })?.address ?? .empty
    }
    
    private func saveAssets() {
        Task {
            await coinViewModel.saveAssets(for: vault)
        }
    }
}
