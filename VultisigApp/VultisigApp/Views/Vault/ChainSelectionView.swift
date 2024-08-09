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
        ZStack {
            ZStack {
                Background()
                main
            }
        }
#if os(iOS)
        .navigationBarBackButtonHidden(true)
        .navigationTitle(NSLocalizedString("chooseChains", comment: "Choose Chains"))
        .toolbar {
            ToolbarItem(placement: Placement.topBarLeading.getPlacement()) {
                NavigationBackSheetButton(showSheet: $showChainSelectionSheet)
            }
        }
#endif
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
    
    var main: some View {
        VStack {
#if os(macOS)
            headerMac
#endif
            content
        }
    }
    
    var headerMac: some View {
        GeneralMacHeader(title: "chooseChains")
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
            await CoinService.saveAssets(for: vault, selection: viewModel.selection)
        }
    }
}

#Preview {
    ChainSelectionView(showChainSelectionSheet: .constant(true), vault: Vault.example)
        .environmentObject(CoinSelectionViewModel())
}
