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
    @Binding var showTokenSelectionSheet: Bool
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
                NavigationBackSheetButton(showSheet: $showTokenSelectionSheet)
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
                VStack(alignment: .leading, spacing: 8) {
                    getAddressCell(for: "Contract Address", with: contractAddress)
                    Separator()
                    getDetailsCell(for: "Name", with: tokenName)
                    Separator()
                    getDetailsCell(for: "Symbol", with: tokenSymbol)
                    Separator()
                    getDetailsCell(for: "Decimals", with: tokenDecimals.description)
                    Separator()
                    getDetailsCell(for: "Logo", with: token?.logo ?? "default")
                    Separator()
                    getDetailsCell(for: "Price Rate", with: "\(token?.priceRate ?? 0)")
                    Separator()
                    getAddressCell(for: "Hex Public Key", with: token?.hexPublicKey ?? "")
                    Separator()
                    getDetailsCell(for: "Price Provider ID", with: token?.priceProviderId ?? "")
                    Separator()
                    getDetailsCell(for: "Raw Balance", with: token?.rawBalance ?? "")
                    Separator()
                    getDetailsCell(for: "Is Native Token", with: "\(token?.isNativeToken ?? false)")
                }
                .padding(16)
                .background(Color.blue600)
                .cornerRadius(10)
                
                Button(action: {
                    Task {
                        
                    }
                }) {
                    FilledButton(title: "Add \(tokenSymbol) token")
                }
            }
            
        }
    }
    
    private func getAddressCell(for title: String, with address: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(NSLocalizedString(title, comment: ""))
                .font(.body20MontserratSemiBold)
                .foregroundColor(.neutral0)
            
            Text(address)
                .font(.body12Menlo)
                .foregroundColor(.turquoise600)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    private func getDetailsCell(for title: String, with value: String) -> some View {
        HStack {
            Text(
                NSLocalizedString(title, comment: "")
            )
            Spacer()
            Text(value)
        }
        .font(.body16MenloBold)
        .foregroundColor(.neutral100)
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
    
    private func fetchTokenInfo() async {
        guard !contractAddress.isEmpty else { return }
        isLoading = true
        showTokenInfo = false
        error = nil
        
        do {
            let service = try EvmServiceFactory.getService(forChain: group.chain)
            let (name, symbol, decimals) = try await service.getTokenInfo(contractAddress: contractAddress)
            let nativeTokenOptional = group.coins.first(where: {$0.isNativeToken})
            if let nativeToken = nativeTokenOptional {
                self.token = Coin(
                    chain: nativeToken.chain,
                    ticker: tokenSymbol,
                    logo: "default",
                    address: nativeToken.address,
                    priceRate: 0,
                    decimals: tokenDecimals,
                    hexPublicKey: nativeToken.hexPublicKey,
                    priceProviderId: "",
                    contractAddress: contractAddress,
                    rawBalance: "",
                    isNativeToken: false
                )
                
                if let customToken = self.token {
                    let (rawBalance, priceRate) = try await service.getBalance(coin: customToken)
                    self.token?.rawBalance = rawBalance
                    self.token?.priceRate = priceRate
                    coinViewModel.handleSelection(isSelected: true, asset: customToken)
                }
            }
            
            DispatchQueue.main.async {
                self.tokenName = name
                self.tokenSymbol = symbol
                self.tokenDecimals = decimals
                self.showTokenInfo = true
                self.isLoading = false
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
        isLoading = true
        Task {
            await coinViewModel.saveAssets(for: vault)
        }
        isLoading = false
    }
}
