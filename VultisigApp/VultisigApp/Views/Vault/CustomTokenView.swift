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
    let group: GroupedChain
    
    @State private var contractAddress: String = ""
    @State private var tokenName: String = ""
    @State private var tokenSymbol: String = ""
    @State private var tokenDecimals: Int = 0
    @State private var showTokenInfo: Bool = false
    @State private var isLoading: Bool = false
    @State private var error: Error?
    
    @State private var isValidAddress: Bool = false
    @State private var token: Coin? = nil
    
    @StateObject var tokenViewModel = TokenSelectionViewModel()
    @EnvironmentObject var coinViewModel: CoinSelectionViewModel
    
    var body: some View {
        ZStack {
            Background()
            VStack(alignment: .leading) {
                view
                    .padding(.top, 16)
                    .padding(.horizontal, 16)
                
                if let error = error {
                    errorView(error: error)
                }
                
                if isLoading {
                    Loader()
                }
                
                Spacer()
            }
        }
        .navigationBarBackButtonHidden(true)
        .navigationTitle(NSLocalizedString("findCustomTokens", comment: "Find Your Custom Token"))
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
        }
        .task {
            await tokenViewModel.loadData(chain: group.chain)
        }
    }
    
    var view: some View {
        VStack(alignment: .leading, spacing: 16) {
            
            HStack {
                AddressTextField(contractAddress: $contractAddress, validateAddress: validateAddress)
                
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
                    price
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
        AsyncImageView(logo: token?.logo ?? .empty, size: CGSize(width: 32, height: 32), ticker: token?.ticker ?? .empty, tokenChainLogo: token?.tokenChainLogo)
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
    var price: some View {
        VStack(alignment: .leading, spacing: 6) {
            
            Text(self.token?.priceRate.description.formatToFiat() ?? .empty)
                .font(.body12MontserratSemiBold)
                .foregroundColor(.neutral0)
            
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
                    self.token = Coin(
                        chain: nativeToken.chain,
                        ticker: symbol,
                        logo: .empty,
                        address: nativeToken.address,
                        priceRate: .zero,
                        decimals: decimals,
                        hexPublicKey: nativeToken.hexPublicKey,
                        priceProviderId: .empty,
                        contractAddress: contractAddress,
                        rawBalance: .zero,
                        isNativeToken: false
                    )
                    
                    if let customToken = self.token {
                        let (rawBalance, priceRate) = try await service.getBalance(coin: customToken)
                        self.token?.rawBalance = rawBalance
                        self.token?.priceRate = priceRate
                        
                        DispatchQueue.main.async {
                            self.tokenName = name
                            self.tokenSymbol = symbol
                            self.tokenDecimals = decimals
                            self.showTokenInfo = true
                            self.isLoading = false
                        }
                    }
                }
                
            } else {
                
                DispatchQueue.main.async {
                    self.error = TokenNotFoundError()
                    self.isLoading = false
                }
                
                
            }
        } catch {
            DispatchQueue.main.async {
                self.error = error
                self.isLoading = false
            }
        }
    }
    
    private func validateAddress(_ address: String) {
        let firstCoinOptional = group.coins.first
        if let firstCoin = firstCoinOptional {
            if firstCoin.chain == .mayaChain {
                isValidAddress = AnyAddress.isValidBech32(string: address, coin: .thorchain, hrp: "maya")
                return
            }
            isValidAddress = firstCoin.coinType.validate(address: address)
        }
    }
    
    private func saveAssets() {
        if let customToken = self.token {
            isLoading = true
            Task {
                coinViewModel.handleSelection(isSelected: true, asset: customToken)
                await coinViewModel.saveAssets(for: vault)
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                    isLoading = false
                    chainDetailView.sheetType = nil
                }
            }
        }
    }
    
    private struct TokenNotFoundError: LocalizedError {
        var errorDescription: String? {
            return NSLocalizedString("Token Not Found", comment: "Token not found error")
        }
    }
}

