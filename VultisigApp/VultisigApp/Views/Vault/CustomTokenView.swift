//
//  CustomTokenView.swift
//  VultisigApp
//
//  Created by Enrique Souza Soares on 07/06/24.
//

import Foundation
import SwiftUI
import WalletCore

struct CustomTokenView: View {
    let chainDetailView: ChainDetailView
    let vault: Vault
    @ObservedObject var group: GroupedChain
    
    @State private var contractAddress: String = ""
    @State private var tokenName: String = ""
    @State private var tokenSymbol: String = ""
    @State private var tokenDecimals: Int = 0
    @State private var showTokenInfo: Bool = false
    @State private var isLoading: Bool = false
    @State private var error: Error?
    
    @State private var isValidAddress: Bool = false
    @State private var token: CoinMeta? = nil
    
    @StateObject var tokenViewModel = TokenSelectionViewModel()
    @EnvironmentObject var coinViewModel: CoinSelectionViewModel
    
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        ZStack {
            Background()
            VStack(alignment: .leading) {
                main
                
                if let error = error {
                    errorView(error: error)
                }
                
                if isLoading {
                    Loader()
                }
                
                Spacer()
            }
        }
        .task {
            await tokenViewModel.loadData(groupedChain: group)
        }
        .navigationBarBackButtonHidden(true)
#if os(iOS)
        .navigationTitle(NSLocalizedString("findCustomTokens", comment: "Find Your Custom Token"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: Placement.topBarLeading.getPlacement()) {
                Button(action: {
                    self.chainDetailView.sheetType = nil
                    dismiss()
                }) {
                    Image(systemName: "chevron.backward")
                        .font(.body18Menlo)
                        .foregroundColor(Color.neutral0)
                }
            }
        }
#endif
    }
    
    var main: some View {
        VStack(spacing: 0) {
#if os(macOS)
            headerMac
#endif
            view
                .padding(.top, 16)
                .padding(.horizontal, 16)
        }
    }
    
    var headerMac: some View {
        TokenSelectionHeader(title: "findCustomTokens", chainDetailView: chainDetailView)
    }
    
    var view: some View {
        VStack(alignment: .leading, spacing: 16) {
            
            HStack {
                AddressTextField(
                    contractAddress: $contractAddress,
                    validateAddress: validateAddress,
                    showScanIcon: false,
                    showAddressBookIcon: false
                )
                
                Button(action: {
                    Task {
                        await fetchTokenInfo()
                    }
                }) {
                    CircularFilledButton(icon: "magnifyingglass")
                }
            }
            
            if showTokenInfo {
                
                HStack(spacing: 16) {
                    image
                    text
                    Spacer()
                }
                .frame(height: 72)
                .padding(.horizontal, 16)
                .background(Color.blue600)
                .cornerRadius(10)
                
                Button(action: {
                    saveAssets()
                }) {
                    FilledButton(title: "Add \(tokenSymbol) token")
                }
            }
            
        }
    }
    
    func errorView(error: Error) -> some View {
        return VStack(spacing: 16) {
            Text(error.localizedDescription)
                .multilineTextAlignment(.center)
                .font(.body16Menlo)
                .foregroundColor(.neutral0)
                .padding(.horizontal, 16)
            
            Button {
                Task { await fetchTokenInfo() }
            } label: {
                FilledButton(title: "Retry")
            }
            .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    var image: some View {
        AsyncImageView(logo: token?.logo ?? .empty, size: CGSize(width: 32, height: 32), ticker: token?.ticker ?? .empty, tokenChainLogo: token?.chain.logo)
    }
    
    var text: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(self.token?.ticker ?? .empty)
                .font(.body16MontserratBold)
                .foregroundColor(.neutral0)
            
            Text(self.token?.chain.name ?? .empty)
                .font(.body12MontserratSemiBold)
                .foregroundColor(.neutral0)
            
            Text(contractAddress)
                .font(.body12Menlo)
                .foregroundColor(.turquoise600)
        }
    }
    
    
    private func fetchTokenInfo() async {
        guard !contractAddress.isEmpty else { return }
        isLoading = true
        showTokenInfo = false
        error = nil
        
        do {
            let service = try EvmServiceFactory.getService(forChain: group.chain)
            let (name, symbol, decimals) = try await service.getTokenInfo(contractAddress: contractAddress)
            
            if !name.isEmpty, !symbol.isEmpty, decimals > 0 {
                let nativeTokenOptional = group.coins.first(where: {$0.isNativeToken})
                if let nativeToken = nativeTokenOptional {
                    self.token = CoinMeta(
                        chain: nativeToken.chain,
                        ticker: symbol,
                        logo: .empty,
                        decimals: decimals,
                        priceProviderId: .empty,
                        contractAddress: contractAddress,
                        isNativeToken: false
                    )
                    self.tokenName = name
                    self.tokenSymbol = symbol
                    self.tokenDecimals = decimals
                    self.showTokenInfo = true
                    self.isLoading = false
                }
                
            } else {
                
                self.error = TokenNotFoundError()
                self.isLoading = false
                
            }
        } catch {
            self.error = error
            self.isLoading = false
            
        }
    }
    
    private func validateAddress(_ address: String) {
        isValidAddress = AddressService.validateAddress(address: address, group: group)
    }
    
    private func saveAssets() {
        if let customToken = self.token {
            isLoading = true
            Task {
                coinViewModel.handleSelection(isSelected: true, asset: customToken)
                await CoinService.saveAssets(for: vault, selection: coinViewModel.selection)
                
                try await Task.sleep(nanoseconds: 1_000_000_000)
                isLoading = false
                self.chainDetailView.sheetType = nil
                dismiss()
            }
        }
    }
    
    private struct TokenNotFoundError: LocalizedError {
        var errorDescription: String? {
            return NSLocalizedString("Token Not Found", comment: "Token not found error")
        }
    }
}

