//
//  CustomTokenScreen.swift
//  VultisigApp
//
//  Created by Enrique Souza Soares on 07/06/24.
//

import Foundation
import SwiftUI
import WalletCore

struct CustomTokenScreen: View {
    let vault: Vault
    @ObservedObject var group: GroupedChain
    @Binding var isPresented: Bool
    var onClose: () -> Void
    
    @State private var contractAddress: String = ""
    @State private var tokenName: String = ""
    @State private var tokenSymbol: String = ""
    @State private var tokenDecimals: Int = 0
    @State private var showTokenInfo: Bool = false
    @State var isAddingToken: Bool = false
    @State var isLoading: Bool = false
    @State var error: Error?
    
    @State private var isValidAddress: Bool = false
    @State private var token: CoinMeta? = nil
    
    @StateObject var tokenViewModel = TokenSelectionViewModel()
    @EnvironmentObject var coinViewModel: CoinSelectionViewModel
    
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    Text("findCustomTokens".localized)
                        .foregroundStyle(Theme.colors.textPrimary)
                        .font(Theme.fonts.title2)
                        .multilineTextAlignment(.leading)
                    HStack(spacing: 12) {
                        SearchTextField(
                            value: $contractAddress,
                            showPasteButton: true
                        )
                        CircularAccessoryIconButton(icon: "search-menu") {
                            Task {
                                await fetchTokenInfo()
                            }
                        }
                    }
                    
                    if let error = error {
                        errorView(error: error)
                            .transition(.opacity)
                    }
                    
                    if showTokenInfo {
                        tokenInfoView
                        
                        PrimaryButton(title: "Add \(tokenSymbol) token") {
                            saveAssets()
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 24)
                .padding(.horizontal, 16)
            }
            .crossPlatformToolbar(showsBackButton: false) {
                CustomToolbarItem(placement: .leading) {
                    ToolbarButton(image: "x") {
                        onClose()
                    }
                }
            }
            .onSubmit {
                Task {
                    await fetchTokenInfo()
                }
            }
        }
        .onLoad {
            tokenViewModel.loadData(groupedChain: group)
        }
        .onChange(of: contractAddress) { _, newValue in
            validateAddress(newValue)
        }
        .withLoading(text: "pleaseWait".localized, isLoading: $isLoading)
        .withLoading(text: "addingToken".localized, isLoading: $isAddingToken)
    }
    
    func errorView(error: Error) -> some View {
        ActionBannerView(
            title: error.localizedDescription,
            subtitle: "customTokenErrorSubtitle".localized,
            buttonTitle: "retry".localized,
            showsActionButton: !(error is RateLimitError)
        ) {
            Task { await fetchTokenInfo() }
        }
    }
    
    var tokenInfoView: some View {
        ZStack(alignment: .top) {
            HStack(spacing: 12) {
                AsyncImageView(
                    logo: token?.logo ?? .empty,
                    size: CGSize(width: 36, height: 36),
                    ticker: token?.ticker ?? .empty,
                    tokenChainLogo: token?.chain.logo
                )
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Text(token?.ticker ?? .empty)
                            .foregroundStyle(Theme.colors.textPrimary)
                            .font(Theme.fonts.bodyMMedium)
                        
                        Text(token?.chain.name ?? .empty)
                            .foregroundStyle(Theme.colors.textSecondary)
                            .font(Theme.fonts.caption10)
                            .padding(.vertical, 8)
                            .padding(.horizontal, 12)
                            .overlay(RoundedRectangle(cornerRadius: 99).stroke(Theme.colors.borderLight))
                    }
                    
                    Text(token?.contractAddress ?? .empty)
                        .foregroundStyle(Theme.colors.textTertiary)
                        .font(Theme.fonts.caption12)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 12)
            .padding(.horizontal, 16)
            .background(RoundedRectangle(cornerRadius: 12).fill(Theme.colors.bgSurface1))
            GradientListSeparator()
        }
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
    
    private func fetchTokenInfo() async {
        guard !contractAddress.isEmpty else { return }
        
        // Validate address format before making API calls
        guard isValidAddress else {
            error = InvalidAddressError()
            return
        }
        
        isLoading = true
        showTokenInfo = false
        error = nil
        
        do {
            if ChainType.EVM == group.chain.chainType {
                
                let service = try EvmService.getService(forChain: group.chain)
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
                
            } else if ChainType.Solana == group.chain.chainType {
                
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
                
            }
            
        } catch let error as NSError {
            // Check for rate limit error
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
        isValidAddress = AddressService.validateAddress(address: address, group: group)
    }
    
    private func saveAssets() {
        if let customToken = self.token {
            isAddingToken = true
            Task {
                coinViewModel.handleSelection(isSelected: true, asset: customToken)
                await CoinService.saveAssets(for: vault, selection: coinViewModel.selection)
                
                try await Task.sleep(nanoseconds: 1_000_000_000)
                isAddingToken = false
                dismiss()
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
    
    private struct InvalidAddressError: LocalizedError {
        var errorDescription: String? {
            return NSLocalizedString("invalidAddress", comment: "Invalid address error")
        }
    }
    
}
