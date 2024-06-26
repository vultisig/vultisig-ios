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
            .toolbar {
#if os(iOS)
            ToolbarItem(placement: Placement.topBarLeading.getPlacement()) {
                NavigationBackSheetButton(showSheet: $showSheet)
            }
#elseif os(macOS)
            ToolbarItem(placement: Placement.topBarLeading.getPlacement()) {
                NavigationBackButton()
            }
#endif
            }
        
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
    
    var view: some View {
        ScrollView {
            VStack(spacing: 24) {
                ForEach(viewModel.groupedAssets.keys.sorted(), id: \.self) { key in
                    ChainSelectionCell(
                        assets: viewModel.groupedAssets[key] ?? [],
                        showAlert: $showAlert
                    )
                }
            }
            .padding(.vertical, 30)
#if os(iOS)
            .padding(.bottom, UIDevice.current.userInterfaceIdiom == .pad ? 50 : 0)
#elseif os(macOS)
            .padding(.horizontal, 24)
            .padding(.bottom, 30)
#endif
            .padding(.horizontal, 16)
        }
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
