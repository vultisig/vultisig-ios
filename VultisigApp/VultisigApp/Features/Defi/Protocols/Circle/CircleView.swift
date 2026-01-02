//
//  CircleView.swift
//  VultisigApp
//
//  Created by Enrique Souza on 2025-12-11.
//

import SwiftUI
import BigInt
import WalletCore
import VultisigCommonData

struct CircleView: View {
    let vault: Vault

    @StateObject private var model = CircleViewModel()
    @State private var hasCheckedBackend = false

    var content: some View {
        ZStack {
            Theme.colors.bgPrimary.ignoresSafeArea()

            if !hasCheckedBackend {
                // Show loading while checking backend
                ProgressView()
                    .progressViewStyle(.circular)
            } else if model.missingEth {
                // Show warning to add ETH
                VStack(spacing: 24) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 60))
                        .foregroundStyle(.orange)

                    Text(NSLocalizedString("circleEthereumRequired", comment: "Ethereum Required"))
                        .font(.title2)
                        .bold()
                        .foregroundStyle(Theme.colors.textPrimary)

                    Text(NSLocalizedString("circleEthereumRequiredDescription", comment: "Please add Ethereum..."))
                        .font(.body)
                        .foregroundStyle(Theme.colors.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }
            } else {
                VStack {
                    if let address = vault.circleWalletAddress, !address.isEmpty {
                        CircleDashboardView(vault: vault, model: model)
                    } else {
                        CircleSetupView(vault: vault, model: model)
                    }
                }
            }
        }
        .onAppear {
            Task { await checkExistingWallet() }
        }
        .navigationTitle(NSLocalizedString("circleTitle", comment: "Circle"))
    }
    
    private func checkExistingWallet() async {
        await MainActor.run { model.isLoading = true }
        
        do {
            let existingAddress = try await model.logic.checkExistingWallet(vault: vault)
            await MainActor.run {
                if let existingAddress, !existingAddress.isEmpty {
                    vault.circleWalletAddress = existingAddress
                }
                model.isLoading = false
                hasCheckedBackend = true
            }
        } catch let error as CircleServiceError {
            await MainActor.run {
                if case .keysignError(let msg) = error, msg.contains("No Ethereum") || msg.contains("No ETH") {
                    model.missingEth = true
                }
                model.isLoading = false
                hasCheckedBackend = true
            }
        } catch {
            await MainActor.run {
                model.isLoading = false
                hasCheckedBackend = true
            }
        }
    }
}
