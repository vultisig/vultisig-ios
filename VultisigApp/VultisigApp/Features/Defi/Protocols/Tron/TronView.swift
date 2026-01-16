//
//  TronView.swift
//  VultisigApp
//
//  Created for TRON Freeze/Unfreeze integration
//

import SwiftUI
import BigInt

struct TronView: View {
    let vault: Vault

    @StateObject private var model = TronViewModel()

    var content: some View {
        Screen(
            title: NSLocalizedString("tronTitle", comment: "TRON Staking"),
            showNavigationBar: true,
            backgroundType: .plain
        ) {
            if model.missingTrx {
                // Show warning to add TRX
                VStack(spacing: 24) {
                    Spacer()
                    
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 60))
                        .foregroundStyle(Theme.colors.alertWarning)
                    
                    Text(NSLocalizedString("tronTrxRequired", comment: "TRX Required"))
                        .font(Theme.fonts.title2)
                        .foregroundStyle(Theme.colors.textPrimary)
                    
                    Text(NSLocalizedString("tronTrxRequiredDescription", comment: "Please add TRX to your vault to use TRON staking."))
                        .font(Theme.fonts.bodyMRegular)
                        .foregroundStyle(Theme.colors.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                    
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                // Show dashboard immediately (cards show their own loading states)
                TronDashboardView(vault: vault, model: model, onRefresh: loadData)
            }
        }
        .onAppear {
            Task { await loadData() }
        }
    }
    
    private func loadData() async {
        await MainActor.run { model.isLoading = true }
        
        // Check if vault has TRX
        guard let _ = TronViewLogic.getTrxCoin(vault: vault) else {
            await MainActor.run {
                model.missingTrx = true
                model.isLoading = false
            }
            return
        }
        
        do {
            let (available, frozenBandwidth, frozenEnergy, unfreezing, pendingWithdrawals, resource) = try await model.logic.fetchData(vault: vault)
            await MainActor.run {
                model.availableBalance = available
                model.frozenBandwidthBalance = frozenBandwidth
                model.frozenEnergyBalance = frozenEnergy
                model.unfreezingBalance = unfreezing
                model.pendingWithdrawals = pendingWithdrawals
                
                if let resource = resource {
                    model.availableBandwidth = resource.calculateAvailableBandwidth()
                    model.totalBandwidth = resource.freeNetLimit + resource.NetLimit
                    model.availableEnergy = resource.EnergyLimit - resource.EnergyUsed
                    model.totalEnergy = resource.EnergyLimit
                }
                
                model.isLoading = false
            }
        } catch {
            await MainActor.run {
                model.error = error
                model.isLoading = false
            }
        }
    }
}
