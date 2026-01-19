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
                        .font(Theme.fonts.largeTitle)
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
        // Set all loading states upfront so skeletons appear and clear previous errors
        await MainActor.run {
            model.isLoading = true
            model.isLoadingBalance = true
            model.isLoadingResources = true
            model.error = nil
        }
        
        // Check if vault has TRX
        guard let trxCoin = TronViewLogic.getTrxCoin(vault: vault) else {
            await MainActor.run {
                model.missingTrx = true
                model.isLoading = false
                model.isLoadingBalance = false
                model.isLoadingResources = false
            }
            return
        }
        
        // Clear missingTrx flag when TRX is found
        await MainActor.run {
            model.missingTrx = false
        }
        
        let address = trxCoin.address
        let tronService = TronService.shared
        
        // Use structured concurrency for proper cancellation handling
        await withTaskGroup(of: Void.self) { group in
            // Task 1: Fetch account info (balance data)
            group.addTask {
                do {
                    let account = try await tronService.getAccount(address: address)
                    await MainActor.run {
                        // Calculate available balance (in TRX, not SUN)
                        let balanceSun = account.balance ?? 0
                        self.model.availableBalance = Decimal(balanceSun) / Decimal(1_000_000)
                        
                        // Parse frozen balances from frozenV2 array (Stake 2.0)
                        self.model.frozenBandwidthBalance = Decimal(account.frozenBandwidthSun) / Decimal(1_000_000)
                        self.model.frozenEnergyBalance = Decimal(account.frozenEnergySun) / Decimal(1_000_000)
                        
                        // Parse unfreezing balance
                        self.model.unfreezingBalance = Decimal(account.unfreezingTotalSun) / Decimal(1_000_000)
                        
                        // Parse pending withdrawals
                        self.model.pendingWithdrawals = (account.unfrozenV2 ?? []).compactMap { entry in
                            guard let amountSun = entry.unfreeze_amount, let expireTime = entry.unfreeze_expire_time else {
                                return nil
                            }
                            let amountTrx = Decimal(amountSun) / Decimal(1_000_000)
                            let expirationDate = Date(timeIntervalSince1970: TimeInterval(expireTime / 1000))
                            return TronPendingWithdrawal(amount: amountTrx, expirationDate: expirationDate)
                        }.sorted { $0.expirationDate < $1.expirationDate }
                        
                        self.model.isLoadingBalance = false
                    }
                } catch {
                    if !(error is CancellationError) {
                        await MainActor.run {
                            self.model.error = error
                            self.model.isLoadingBalance = false
                        }
                    }
                }
            }
            
            // Task 2: Fetch resource info (bandwidth/energy)
            group.addTask {
                do {
                    let resource = try await tronService.getAccountResource(address: address)
                    await MainActor.run {
                        self.model.availableBandwidth = resource.calculateAvailableBandwidth()
                        self.model.totalBandwidth = resource.freeNetLimit + resource.NetLimit
                        self.model.availableEnergy = resource.EnergyLimit - resource.EnergyUsed
                        self.model.totalEnergy = resource.EnergyLimit
                        self.model.isLoadingResources = false
                    }
                } catch {
                    if !(error is CancellationError) {
                        await MainActor.run {
                            self.model.error = error
                            self.model.isLoadingResources = false
                        }
                    }
                }
            }
        }
        
        // Clear global loading state after task group completes
        await MainActor.run { model.isLoading = false }
    }
}
