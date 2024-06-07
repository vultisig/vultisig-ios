//
//  TokenSelectionView.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-04-11.
//

import SwiftUI

struct TokenSelectionView: View {
    @Binding var showTokenSelectionSheet: Bool
    let vault: Vault
    let group: GroupedChain
    
    @StateObject var tokenViewModel = TokenSelectionViewModel()
    @EnvironmentObject var coinViewModel: CoinSelectionViewModel
    
    var body: some View {
        ZStack {
            Background()
            view
            
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
                NavigationBackSheetButton(showSheet: $showTokenSelectionSheet)
            }
        }
        .task {
            await tokenViewModel.loadData(chain: group.chain)
            
            do {
                let service = try EvmServiceFactory.getService(forChain: group.chain)
                let (name, symbol, decimals) = try await service.getTokenInfo(contractAddress: "0xc51d94a9936616b90e26abe61921ab3b4e66a149")
                print("Token name \(name), Token symbol \(symbol), Token decimals \(decimals)")
            }catch {
                print("")
            }
        }
        .onDisappear {
            saveAssets()
        }
        .searchable(text: $tokenViewModel.searchText)
    }
    
    var view: some View {
        List {
            let selected = tokenViewModel.selectedTokens(groupedChain: group)
            if !selected.isEmpty {
                Section(header: Text("Selected")) {
                    ForEach(selected, id: \.self) { token in
                        TokenSelectionCell(chain: group.chain, address: address, asset: token, tokenSelectionViewModel: tokenViewModel)
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                    }
                }
            }
            let filtered = tokenViewModel.filteredTokens(groupedChain: group)
            if !filtered.isEmpty {
                Section(header: Text("Search result")) {
                    ForEach(filtered, id: \.self) { token in
                        TokenSelectionCell(chain: group.chain, address: address, asset: token, tokenSelectionViewModel: tokenViewModel)
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
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
