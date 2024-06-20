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
            .navigationBarBackButtonHidden(true)
            .navigationTitle(NSLocalizedString("chooseChains", comment: "Choose Chains"))
            .onAppear {
                setData()
            }
            .onChange(of: vault) {
                setData()
            }
            .onDisappear {
                saveAssets()
            }
#if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    NavigationBackSheetButton(showSheet: $showChainSelectionSheet)
                }
            }
#endif
    }
    
    var content: some View {
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
    
    var sortedKeys: [String] {
        viewModel.groupedAssets.keys.sorted()
    }

    var view: some View {
        ScrollView {
            VStack(spacing: 24) {
                ForEach(sortedKeys, id: \.self) { key in
                    ChainSelectionCell(
                        assets: viewModel.groupedAssets[key] ?? [],
                        showAlert: $showAlert
                    )
                }
            }
            .padding(.top, 30)
        }
        .padding(.horizontal, 16)
    }
    
    private func setData() {
        viewModel.setData(for: vault)
    }
    
    private func saveAssets() {
        Task{
            await viewModel.saveAssets(for: vault)
        }
    }
}

#Preview {
    ChainSelectionView(showChainSelectionSheet: .constant(true), vault: Vault.example)
        .environmentObject(CoinSelectionViewModel())
}
