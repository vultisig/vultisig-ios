//
//  FolderDetailView.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 23/09/2025.
//

import SwiftUI
import SwiftData

struct FolderDetailView: View {
    let folder: Folder
    var onSelectVault: (Vault) -> Void
    var onEditFolder: () -> Void
    var onBack: () -> Void
    
    @Query(sort: \Vault.order, order: .forward) var vaults: [Vault]
    @EnvironmentObject var homeViewModel: HomeViewModel
    @EnvironmentObject var appViewModel: AppViewModel
    
    var filteredVaults: [Vault] {
        vaults.filter {
            folder.containedVaultNames.contains($0.name)
        }
    }
    
    var headerSubtitle: String {
        let vaultsText: String = filteredVaults.count > 1 ? "vaults".localized : "vault".localized
        var subtitle = "\(filteredVaults.count) \(vaultsText)"
        
        if filteredVaults.count > 1 {
            subtitle += " · \(homeViewModel.balanceText(for: filteredVaults))"
        }
        
        return subtitle
    }
    
    var body: some View {
        VStack(spacing: 0) {
            header
            List {
                CommonListHeaderView(title: "vaults".localized)
                vaultsList
            }
            .customSectionSpacing(0)
            .listStyle(.plain)
            .buttonStyle(.borderless)
            .scrollContentBackground(.hidden)
            .scrollIndicators(.hidden)
            .background(Theme.colors.bgPrimary)
            .padding(.top, 20)
        }
        .padding(.top, 24)
        .padding(.horizontal, 16)
    }
    
    var header: some View {
        HStack(spacing: 16) {
            ToolbarButton(
                image: "chevron-right",
                type: .outline,
                action: onBack
            )
            .rotationEffect(.radians(.pi))
            VStack(alignment: .leading, spacing: 4) {
                Text(folder.folderName)
                    .foregroundStyle(Theme.colors.textPrimary)
                    .font(Theme.fonts.title3)
                Text(headerSubtitle)
                    .foregroundStyle(Theme.colors.textTertiary)
                    .font(Theme.fonts.caption12)
            }
            Spacer()
            ToolbarButton(
                image: "pencil",
                type: .outline,
                action: onEditFolder
            )
        }
        .background(
            LinearGradient(
                stops: [
                    Gradient.Stop(color: Theme.colors.bgPrimary, location: 0.50),
                    Gradient.Stop(color: Theme.colors.bgPrimary.opacity(0.5), location: 0.85),
                    Gradient.Stop(color: Theme.colors.bgPrimary.opacity(0), location: 1.00),
                ],
                startPoint: UnitPoint(x: 0.5, y: 0),
                endPoint: UnitPoint(x: 0.5, y: 1)
            )
        )
    }
    
    @ViewBuilder
    var vaultsList: some View {
        ForEach(filteredVaults) { vault in
            VaultCellView(
                vault: vault,
                isSelected: appViewModel.selectedVault == vault,
                isEditing: .constant(false)
            ) {
                onSelectVault(vault)
            }
            .plainListItem()
            .background(Theme.colors.bgPrimary)
        }
    }
}

#Preview {
    FolderDetailView(
        folder: .example,
        onSelectVault: { _ in },
        onEditFolder: {},
        onBack: {}
    ).environmentObject(HomeViewModel())
        .environmentObject(AppViewModel())
}
