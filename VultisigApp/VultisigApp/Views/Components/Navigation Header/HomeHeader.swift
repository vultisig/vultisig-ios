//
//  HomeHeader.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-08-09.
//

import SwiftUI

struct HomeHeader: View {
    @Binding var showFolderDetails: Bool
    @Binding var showVaultsList: Bool
    @Binding var isEditingVaults: Bool
    @Binding var isEditingFolders: Bool
    @Binding var selectedFolder: Folder
    
    @EnvironmentObject var viewModel: HomeViewModel
    @EnvironmentObject var vaultDetailViewModel: VaultDetailViewModel
    
    var body: some View {
        HStack(spacing: 22) {
            leadingButton
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
    
    var leadingButton: some View {
        ZStack {
            if showFolderDetails && showVaultsList {
                backButtonForFolder
            } else {
                menuButton
            }
        }
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
            selectedFolder: selectedFolder,
            isEditingVaults: $isEditingVaults,
            isEditingFolders: $isEditingFolders,
            showFolderDetails: $showFolderDetails
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
            Text(NSLocalizedString(showFolderDetails ? selectedFolder.folderName : "vaults", comment: "Vaults"))
            Text(viewModel.selectedVault?.name ?? NSLocalizedString("vault", comment: "Home view title"))
        }
        .offset(y: showVaultsList ? 9 : -10)
        .frame(height: 20)
        .clipped()
        .bold()
        .foregroundColor(.neutral0)
        .font(.title2)
    }
    
    var backButtonForFolder: some View {
        Button {
            showFolderDetails = false
        } label: {
            NavigationBackButton()
        }
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
        showFolderDetails: .constant(false),
        showVaultsList: .constant(false),
        isEditingVaults: .constant(false), 
        isEditingFolders: .constant(false),
        selectedFolder: .constant(.example)
    )
    .environmentObject(HomeViewModel())
    .environmentObject(VaultDetailViewModel())
}
