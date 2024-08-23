//
//  HomeHeader.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-08-09.
//

import SwiftUI

struct HomeHeader: View {
    @Binding var showVaultsList: Bool
    @Binding var isEditingVaults: Bool
    
    @EnvironmentObject var viewModel: HomeViewModel
    @EnvironmentObject var vaultDetailViewModel: VaultDetailViewModel
    
    var body: some View {
        HStack(spacing: 22) {
            menuButton
            menuButton.opacity(0)
            Spacer()
            navigationTitle
            Spacer()
            editButton
            refreshButton
        }
        .padding(.vertical, 16)
        .padding(.horizontal, 40)
    }
    
    var menuButton: some View {
        NavigationLink {
            SettingsView()
        } label: {
            NavigationMenuButton()
        }
    }
    
    var editButton: some View {
        NavigationHomeEditButton(
            vault: viewModel.selectedVault,
            showVaultsList: showVaultsList,
            isEditingVaults: $isEditingVaults
        )
    }
    
    var refreshButton: some View {
        ZStack {
            if let vault = viewModel.selectedVault {
                NavigationRefreshButton {
                    vaultDetailViewModel.updateBalance(vault: vault)
                }
            }
        }
    }
    
    var navigationTitle: some View {
        ZStack {
            HStack {
                title
                
                if viewModel.selectedVault != nil {
                    Image(systemName: "chevron.up")
                        .font(.body8Menlo)
                        .bold()
                        .foregroundColor(.neutral0)
                        .rotationEffect(.degrees(showVaultsList ? 0 : 180))
                }
            }
        }
        .onTapGesture {
            switchView()
        }
    }
    
    var title: some View {
        VStack(spacing: 0) {
            Text(NSLocalizedString("vaults", comment: "Vaults"))
            Text(viewModel.selectedVault?.name ?? NSLocalizedString("vault", comment: "Home view title"))
        }
        .offset(y: showVaultsList ? 9 : -10)
        .frame(height: 20)
        .clipped()
        .bold()
        .foregroundColor(.neutral0)
        .font(.title2)
    }
    
    private func switchView() {
        guard viewModel.selectedVault != nil else {
            return
        }
        
        withAnimation(.easeInOut) {
            showVaultsList.toggle()
        }
    }
}

#Preview {
    HomeHeader(
        showVaultsList: .constant(false),
        isEditingVaults: .constant(false)
    )
    .environmentObject(HomeViewModel())
    .environmentObject(VaultDetailViewModel())
}
