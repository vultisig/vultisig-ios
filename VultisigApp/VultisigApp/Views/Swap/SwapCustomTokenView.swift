//
//  SwapCustomTokenView.swift
//  VultisigApp
//
//  Created by Assistant on 2025-01-27.
//

import SwiftUI
import WalletCore

struct SwapCustomTokenView: View {
    let vault: Vault
    let chain: Chain
    @Binding var showSheet: Bool
    @Binding var selectedCoin: Coin
    
    @State private var contractAddress: String = ""
    @State private var tokenName: String = ""
    @State private var tokenSymbol: String = ""
    @State private var tokenDecimals: Int = 0
    @State private var showTokenInfo: Bool = false
    @State var isLoading: Bool = false
    @State var error: Error?
    
    @State private var isValidAddress: Bool = false
    @State private var token: CoinMeta? = nil
    
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        content
    }
    
    var content: some View {
        ZStack {
            Background()
            main
            
            if let error = error {
                errorView(error: error)
            }
            
            if isLoading {
                Loader()
            }
        }
        .navigationBarBackButtonHidden(true)
        .navigationTitle(NSLocalizedString("findCustomTokens", comment: "Find Your Custom Token"))
        .toolbar {
            ToolbarItem(placement: Placement.topBarLeading.getPlacement()) {
                Button(action: {
                    showSheet = false
                }) {
                    Image(systemName: "chevron.backward")
                        .font(Theme.fonts.bodyLRegular)
                        .foregroundColor(Theme.colors.textPrimary)
                }
            }
        }
    }
    
    var main: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                AddressTextField(
                    contractAddress: $contractAddress,
                    validateAddress: validateAddress,
                    showScanIcon: false,
                    showAddressBookIcon: false
                )
                
                IconButton(icon: "magnifyingglass", size: .mini) {
                    Task {
                        await fetchTokenInfo()
                    }
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
                .background(Theme.colors.bgSecondary)
                .cornerRadius(10)
                
                PrimaryButton(title: "Add \(tokenSymbol) token") {
                    saveToken()
                }
            }
            
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
    }
    
    func errorView(error: Error) -> some View {
        return VStack(spacing: 16) {
            Text(error.localizedDescription)
                .multilineTextAlignment(.center)
                .font(Theme.fonts.bodyMRegular)
                .foregroundColor(Theme.colors.textPrimary)
                .padding(.horizontal, 16)
            
            if !(error is RateLimitError) {
                PrimaryButton(title: "Retry") {
                    Task { await fetchTokenInfo() }
                }
                .padding(.horizontal, 40)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    var image: some View {
        AsyncImageView(logo: token?.logo ?? .empty, size: CGSize(width: 32, height: 32), ticker: token?.ticker ?? .empty, tokenChainLogo: token?.chain.logo)
    }
    
    var text: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(self.token?.ticker ?? .empty)
                .font(Theme.fonts.bodyMMedium)
                .foregroundColor(Theme.colors.textPrimary)
            
            Text(self.token?.chain.name ?? .empty)
                .font(Theme.fonts.caption12)
                .foregroundColor(Theme.colors.textPrimary)
            
            Text(contractAddress)
                .font(Theme.fonts.caption12)
                .foregroundColor(Theme.colors.bgButtonPrimary)
        }
    }
    
    private func fetchTokenInfo() async {
        guard !contractAddress.isEmpty else { return }
        isLoading = true
        showTokenInfo = false
        error = nil
        
        do {
            if chain.chainType == .EVM {
                let service = try EvmServiceFactory.getService(forChain: chain)
                let (name, symbol, decimals) = try await service.getTokenInfo(contractAddress: contractAddress)
                
                if !name.isEmpty, !symbol.isEmpty, decimals > 0 {
                    self.token = CoinMeta(
                        chain: chain,
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
                } else {
                    self.error = TokenNotFoundError()
                    self.isLoading = false
                }
            } else if chain == .solana {
                let jupiterTokenInfos = try await SolanaService.shared.fetchTokensInfos(for: [contractAddress])
                
                if let jupiterTokenInfo = jupiterTokenInfos.first(where: {$0.contractAddress == contractAddress}) {
                    self.token = jupiterTokenInfo
                    self.tokenName = jupiterTokenInfo.ticker
                    self.tokenSymbol = jupiterTokenInfo.ticker
                    self.tokenDecimals = jupiterTokenInfo.decimals
                    self.showTokenInfo = true
                    self.isLoading = false
                } else {
                    self.error = TokenNotFoundError()
                    self.isLoading = false
                }
            } else {
                self.error = TokenNotFoundError()
                self.isLoading = false
            }
        } catch let error as NSError {
            if error.code == 429 {
                self.error = RateLimitError()
            } else {
                self.error = error
            }
            self.isLoading = false
        } catch {
            self.error = error
            self.isLoading = false
        }
    }
    
    private func validateAddress(_ address: String) {
        isValidAddress = AddressService.validateAddress(address: address, chain: chain)
    }
    
    private func saveToken() {
        guard let token = self.token else { return }
        
        Task {
            isLoading = true
            
            do {
                // Create and add the coin to the vault
                if let coin = try await CoinService.addToChain(
                    asset: token,
                    to: vault,
                    priceProviderId: token.priceProviderId
                ) {
                    // Update the selectedCoin on the main thread
                    await MainActor.run {
                        selectedCoin = coin
                        isLoading = false
                        showSheet = false
                        dismiss()
                    }
                }
            } catch {
                await MainActor.run {
                    self.error = error
                    isLoading = false
                }
            }
        }
    }
    
    private struct TokenNotFoundError: LocalizedError {
        var errorDescription: String? {
            return NSLocalizedString("Token Not Found", comment: "Token not found error")
        }
    }
    
    private struct RateLimitError: LocalizedError {
        var errorDescription: String? {
            return NSLocalizedString("Too many requests. Please close this screen and try again later.", comment: "Rate limit error")
        }
    }
}

#Preview {
    SwapCustomTokenView(
        vault: Vault.example,
        chain: .ethereum,
        showSheet: .constant(true),
        selectedCoin: .constant(Coin.example)
    )
} 
