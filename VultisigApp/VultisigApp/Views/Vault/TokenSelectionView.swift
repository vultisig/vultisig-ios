import SwiftUI

struct TokenSelectionView: View {
    let chainDetailView: ChainDetailView
    let vault: Vault
    @ObservedObject var group: GroupedChain
    
    @StateObject var tokenViewModel = TokenSelectionViewModel()
    @EnvironmentObject var coinViewModel: CoinSelectionViewModel
    
    @Environment(\.dismiss) var dismiss
    
    // Focus state for the search field to force layout update
    @FocusState var isSearchFieldFocused: Bool
    @State private var isSearching = false
    
    var body: some View {
        content
            .onAppear {
                tokenViewModel.loadData(groupedChain: group)
                isSearchFieldFocused = true
            }
            .onDisappear {
                tokenViewModel.cancelLoading()
                saveAssets()
            }
            .onReceive(tokenViewModel.$searchText) {newVault in
                tokenViewModel.updateSearchedTokens(groupedChain: group)
            }
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
            textField
            
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
        .colorScheme(.dark)
    }
    
    func errorView(error: Error) -> some View {
        return VStack(spacing: 16) {
            Text(error.localizedDescription)
                .multilineTextAlignment(.center)
                .font(.body16Menlo)
                .foregroundColor(.neutral0)
                .padding(.horizontal, 16)
            
            if tokenViewModel.showRetry {
                PrimaryButton(title: "Retry") {
                    tokenViewModel.loadData(groupedChain: group)
                }
                .padding(.horizontal, 40)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    var list: some View {
        VStack(alignment: .leading, spacing: 24) {
            if tokenViewModel.searchText.isEmpty {
                if !tokenViewModel.selectedTokens.isEmpty {
                    Section(header: Text(NSLocalizedString("Selected", comment:"Selected"))
                        .font(.body16MenloBold)
                        .foregroundColor(.neutral0)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity, alignment: .leading)) {
                            ForEach(tokenViewModel.selectedTokens, id: \.self) { asset in
                                TokenSelectionCell(chain: group.chain, address: address, asset: asset, isSelected: isTokenSelected(asset: asset))
                                    .listRowBackground(Color.clear)
                                    .listRowSeparator(.hidden)
                            }
                        }
                }

                Section(
                    header:
                        Text(NSLocalizedString("tokens", comment:"Tokens"))
                        .font(.body16MenloBold)
                        .foregroundColor(.neutral0)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                ) {
                    ForEach(tokenViewModel.preExistTokens, id: \.self) { asset in
                        TokenSelectionCell(chain: group.chain, address: address, asset: asset, isSelected: isTokenSelected(asset: asset))
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                    }
                }
            } else {
                Section(header: Text(NSLocalizedString("searchResult", comment:"Search Result"))
                    .font(.body16MenloBold)
                    .foregroundColor(.neutral0)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)) {
                    if !tokenViewModel.searchedTokens.isEmpty {
                        ForEach(tokenViewModel.searchedTokens, id: \.self) { asset in
                            TokenSelectionCell(chain: group.chain, address: address, asset: asset, isSelected: isTokenSelected(asset: asset))
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                        }
                    } else if tokenViewModel.isLoading {
                        // Show loading indicator while searching
                        HStack {
                            ProgressView()
                                .scaleEffect(0.8)
                            Text("Searching...")
                                .font(.body14Menlo)
                                .foregroundColor(.neutral0)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                    }
                }
            }
        }
        .padding(.horizontal, 16)
    }

    var address: String {
        return vault.coins.first(where: { $0.chain == group.chain })?.address ?? .empty
    }

    func isTokenSelected(asset: CoinMeta) -> Binding<Bool> {
        return Binding(get: {
            return coinViewModel.isSelected(asset: asset)
        }) { newValue in
            coinViewModel.handleSelection(isSelected: newValue, asset: asset)
        }
    }

    func saveAssets() {
        Task {
            await CoinService.saveAssets(for: vault, selection: coinViewModel.selection)
        }
    }
}

#Preview {
    TokenSelectionView(
        chainDetailView: ChainDetailView(group: GroupedChain.example, vault: Vault.example),
        vault: Vault.example,
        group: GroupedChain.example
    )
    .environmentObject(CoinSelectionViewModel())
}
