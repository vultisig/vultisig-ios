//
//  ChainSelectionView.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-03-11.
//

import SwiftUI

struct ChainSelectionView: View {
    @Binding var showChainSelectionSheet: Bool
    let vault: Vault
    
    @State var showAlert = false
    @EnvironmentObject var viewModel: CoinSelectionViewModel
    
    var body: some View {
        content
            .onAppear {
                setData()
            }
            .onChange(of: vault) {
                setData()
            }
            .onDisappear {
                saveAssets()
            }
    }
    
    var views: some View {
        ZStack {
            Background()
            view
        }
        .alert(isPresented: $showAlert) {
            alert
        }
    }
    
    var alert: Alert {
        Alert(
            title: Text(NSLocalizedString("cannotDisableChain", comment: "")),
            message: Text(NSLocalizedString("needToRemoveTokens", comment: "")),
            dismissButton: .default(Text(NSLocalizedString("ok", comment: "")))
        )
    }
    
    private func setData() {
        viewModel.setData(for: vault)
    }
    
    private func saveAssets() {
        Task{
            await CoinService.saveAssets(for: vault, selection: viewModel.selection)
        }
    }
}

#Preview {
    ChainSelectionView(showChainSelectionSheet: .constant(true), vault: Vault.example)
        .environmentObject(CoinSelectionViewModel())
}
