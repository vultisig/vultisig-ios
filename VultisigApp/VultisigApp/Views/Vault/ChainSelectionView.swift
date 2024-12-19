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
    @State var isSearching: Bool = false

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

    var searchBar: some View {
        HStack(spacing: 0) {
            searchField

            if isSearching {
                Button("Cancel") {
                    viewModel.searchText = ""
                    isSearching = false
                }
                .foregroundColor(.blue)
                .font(.body12Menlo)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 44)
        .padding(.horizontal, 12)
        .listRowInsets(EdgeInsets())
        .listRowSeparator(.hidden)
        .onChange(of: viewModel.searchText) { oldValue, newValue in
            isSearching = !newValue.isEmpty
        }
        .background(Color.blue600)
        .cornerRadius(12)
    }

    var searchField: some View {
        TextField(NSLocalizedString("Search", comment: "Search"), text: $viewModel.searchText)
            .font(.body16Menlo)
            .foregroundColor(.neutral0)
            .disableAutocorrection(true)
            .padding(.horizontal, 8)
            .borderlessTextFieldStyle()
            .textInputAutocapitalization(.never)
            .keyboardType(.default)
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
