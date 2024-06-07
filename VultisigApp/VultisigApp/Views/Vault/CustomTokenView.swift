//
//  CustomTokenView.swift
//  VultisigApp
//
//  Created by Enrique Souza Soares on 07/06/24.
//

import Foundation
import SwiftUI

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
    
    var body: some View {
        ZStack {
            Background()
            VStack {
                view
                
                if let error = error {
                    errorView(error: error)
                }
                
                if isLoading {
                    Loader()
                }
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
    }
    
    var view: some View {
        VStack(spacing: 16) {
            AddressTextField(contractAddress: $contractAddress, validateAddress: validateAddress)
                .padding(.horizontal)
            
            Button(action: {
                Task {
                    await fetchTokenInfo()
                }
            }) {
                FilledButton(title: "Fetch Token Info")
            }
            .padding(.horizontal)
            
            if showTokenInfo {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Name: \(tokenName)")
                    Text("Symbol: \(tokenSymbol)")
                    Text("Decimals: \(tokenDecimals)")
                }
                .padding(.horizontal)
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
    
    private func fetchTokenInfo() async {
        guard !contractAddress.isEmpty else { return }
        isLoading = true
        showTokenInfo = false
        error = nil
        
        do {
            let service = try EvmServiceFactory.getService(forChain: group.chain)
            let (name, symbol, decimals) = try await service.getTokenInfo(contractAddress: contractAddress)
            
            print("Token name \(name), Token symbol \(symbol), Token decimals \(decimals)")
            
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
        // Implement address validation logic here
        print("Validating address: \(address)")
        // Add your validation logic here, e.g., checking if the address is a valid Ethereum address
    }
}
