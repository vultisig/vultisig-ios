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
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: Placement.topBarLeading.getPlacement()) {
                Button(action: {
                    showSheet = false
                }) {
                    Image(systemName: "chevron.backward")
                        .font(.body18Menlo)
                        .foregroundColor(Color.neutral0)
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
                    saveToken()
                }) {
                    FilledButton(title: "Add \(tokenSymbol) token")
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
                .font(.body16Menlo)
                .foregroundColor(.neutral0)
                .padding(.horizontal, 16)
            
            if !(error is RateLimitError) {
                Button {
                    Task { await fetchTokenInfo() }
                } label: {
                    FilledButton(title: "Retry")
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
        if let customToken = self.token {
            isLoading = true
            Task {
                do {
                    if let newCoin = try await CoinService.addToChain(asset: customToken, to: vault, priceProviderId: customToken.priceProviderId) {
                        selectedCoin = newCoin
                        showSheet = false
                    }
                } catch {
                    self.error = error
                }
                isLoading = false
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