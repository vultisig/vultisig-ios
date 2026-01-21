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
        Screen(
            title: NSLocalizedString("circleTitle", comment: "Circle"),
            showNavigationBar: true,
            backgroundType: .plain
        ) {
            if !hasCheckedBackend {
                // Show loading while checking backend
                ProgressView()
                    .progressViewStyle(.circular)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if model.missingEth {
                // Show warning to add ETH
                VStack(spacing: 24) {
                    Spacer()

                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 60))
                        .foregroundStyle(Theme.colors.alertWarning)

                    Text(NSLocalizedString("circleEthereumRequired", comment: "Ethereum Required"))
                        .font(Theme.fonts.title2)
                        .foregroundStyle(Theme.colors.textPrimary)

                    Text(NSLocalizedString("circleEthereumRequiredDescription", comment: "Please add Ethereum..."))
                        .font(Theme.fonts.bodyMRegular)
                        .foregroundStyle(Theme.colors.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)

                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
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
