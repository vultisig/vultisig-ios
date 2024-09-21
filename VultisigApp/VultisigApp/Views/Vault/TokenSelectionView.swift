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
