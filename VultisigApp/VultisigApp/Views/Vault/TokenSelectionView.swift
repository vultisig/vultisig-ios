import SwiftUI

struct TokenSelectionView: View {
    let chainDetailView: ChainDetailView
    let vault: Vault
    @ObservedObject var group: GroupedChain
    
    @StateObject var tokenViewModel = TokenSelectionViewModel()
    @EnvironmentObject var coinViewModel: CoinSelectionViewModel
    
    @Environment(\.dismiss) var dismiss
    
    // Focus state for the search field to force layout update
    @FocusState private var isSearchFieldFocused: Bool
    @State private var isSearching = false
    
    var body: some View {
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
#if os(iOS)
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
#endif
        .task {
            await tokenViewModel.loadData(groupedChain: group)
        }
        .onAppear {
            isSearchFieldFocused = true
        }
        .onDisappear {
            saveAssets()
        }
        .onReceive(tokenViewModel.$searchText) {newVault in
            tokenViewModel.updateSearchedTokens(groupedChain: group)
        }
    }
    
    var main: some View {
        VStack(spacing: 0) {
#if os(macOS)
            headerMac
#endif
            view
        }
    }
    
    var headerMac: some View {
        TokenSelectionHeader(title: "chooseTokens", chainDetailView: chainDetailView)
    }
    
    var addCustomTokenButton: some View {
        Button {
            chainDetailView.sheetType = .customToken
        } label: {
            chainDetailView.chooseTokensButton(NSLocalizedString("customToken", comment: "Custom Token"))
        }
        .background(Color.clear)
#if os(iOS)
        .padding(.horizontal, 25)
#elseif os(macOS)
        .padding(.horizontal, 40)
#endif
    }
    
    var view: some View {
        VStack(alignment: .leading, spacing: 0) {
#if os(macOS)
            search
#endif
            addCustomTokenButton
            
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
#if os(iOS)
                .padding(.horizontal, 25)
                .listStyle(.grouped)
#elseif os(macOS)
                .padding(.horizontal, 40)
                .padding(.bottom, 50)
                .colorScheme(.dark)
#endif
            }
        }
#if os(iOS)
        .padding(.bottom, 50)
#endif
    }
    
    var search: some View {
        HStack {
            searchBar
            saveButton
        }
        .padding(.vertical, 18)
        .padding(.horizontal, 40)
    }
    
    var searchBar: some View {
        HStack(spacing: 0) {
            TextField(NSLocalizedString("Search", comment: "Search").toFormattedTitleCase(), text: $tokenViewModel.searchText)
                .font(.body16Menlo)
                .foregroundColor(.neutral0)
                .submitLabel(.next)
                .disableAutocorrection(true)
                .textContentType(.oneTimeCode)
                .padding(.horizontal, 8)
                .borderlessTextFieldStyle()
                .maxLength( $tokenViewModel.searchText)
#if os(iOS)
                .focused($isSearchFieldFocused)
                .textInputAutocapitalization(.never)
                .keyboardType(.default)
#elseif os(macOS)
                .colorScheme(.dark)
#endif
            
            if isSearching {
                Button("Cancel") {
                    tokenViewModel.searchText = ""
                    isSearchFieldFocused = false
                    isSearching = false
                }
                .foregroundColor(.blue)
                .font(.body12Menlo)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 44)
        .padding(.horizontal, 12)
        .listRowInsets(EdgeInsets())
        .listRowSeparator(.hidden)
        .onChange(of: tokenViewModel.searchText) { oldValue, newValue in
            isSearching = !newValue.isEmpty
        }
        .background(Color.blue600)
        .cornerRadius(12)
    }
    
    var saveButton: some View {
        Button(action: {
            self.chainDetailView.sheetType = nil
            dismiss()
        }) {
            Text("Save")
                .foregroundColor(.blue)
        }
#if os(macOS)
                .padding(.horizontal, 32)
                .frame(height: 44)
                .background(Color.blue600)
                .cornerRadius(12)
#endif
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
                    Task { await tokenViewModel.loadData(groupedChain: group) }
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
            await CoinService.saveAssets(for: vault, selection: coinViewModel.selection)
        }
    }
}
