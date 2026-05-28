//
//  FunctionCallVerifyView.swift
//  VultisigApp
//
//  Created by Enrique Souza Soares on 14/05/24.
//

import Foundation
import SwiftUI

struct FunctionCallVerifyScreen: View {
    @Environment(\.router) var router
    @StateObject var depositViewModel = FunctionCallViewModel()
    @StateObject var depositVerifyViewModel = FunctionCallVerifyViewModel()
    let transaction: SendTransaction
    let vault: Vault

    @State var fastPasswordPresented = false
    @State var fastVaultPassword: String = ""
    @State var isForReferral = false
    @State private var error: HelperError?

    var body: some View {
        Screen {
            VStack(spacing: 0) {
                if isForReferral {
                    ReferralSendOverviewView(transaction: transaction)
                } else if transaction.cosmosStakingPayload != nil {
                    stakingSummary
                } else {
                    summary
                }

                Spacer()
                pairedSignButton
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .blur(radius: depositVerifyViewModel.isLoading ? 1 : 0)
        }
        .screenTitle("verify".localized)
        .onDisappear {
            depositVerifyViewModel.isLoading = false
            // Clear password if navigating back (not forward to keysign)
            if vault.isFastVault {
                fastVaultPassword = .empty
            }
        }
        .alert(item: $error) { error in
            Alert(
                title: Text(NSLocalizedString("error", comment: "")),
                message: Text(NSLocalizedString(error.localizedDescription, comment: "")),
                dismissButton: .default(Text(NSLocalizedString("ok", comment: "")))
            )
        }
        .onLoad {
            depositVerifyViewModel.onLoad()
            Task {
                await depositVerifyViewModel.scan(transaction: transaction)
            }
        }
        .bottomSheet(isPresented: $depositVerifyViewModel.showSecurityScannerSheet) {
            SecurityScannerBottomSheet(securityScannerModel: depositVerifyViewModel.securityScannerState.result) {
                depositVerifyViewModel.showSecurityScannerSheet = false
                signAndMoveToNextView()
            } onDismissRequest: {
                depositVerifyViewModel.showSecurityScannerSheet = false
            }
        }
    }

    var stakingSummary: some View {
        CosmosStakingVerifySummaryView(
            transaction: transaction,
            vault: vault,
            feeCrypto: transaction.gasInReadable,
            feeFiat: depositViewModel.feesInReadable(tx: transaction, vault: vault),
            securityScannerState: $depositVerifyViewModel.securityScannerState
        )
    }

    var summary: some View {
        SendCryptoVerifySummaryView(
            input: SendCryptoVerifySummary(
                fromName: vault.name,
                fromAddress: transaction.fromAddress,
                toAddress: transaction.toAddress,
                network: transaction.coin.chain.name,
                networkImage: transaction.coin.chain.logo,
                memo: "",
                memoFunctionDictionary: depositViewModel.memoDictionary(for: transaction.memoFunctionDictionary),
                feeCrypto: transaction.gasInReadable,
                feeFiat: depositViewModel.feesInReadable(tx: transaction, vault: vault),
                coinImage: transaction.coin.logo,
                amount: getAmount(),
                coinTicker: transaction.coin.ticker
            ),
            securityScannerState: $depositVerifyViewModel.securityScannerState
        )
    }

    var pairedSignButton: some View {
        VStack {
            if vault.isFastVault {
                Text(NSLocalizedString("holdForPairedSign", comment: ""))
                    .foregroundColor(Theme.colors.textTertiary)
                    .font(Theme.fonts.bodySMedium)

                LongPressPrimaryButton(
                    title: NSLocalizedString("signTransaction", comment: "")) {
                        fastPasswordPresented = true
                    } longPressAction: {
                        // Clear password for paired sign (long press)
                        fastVaultPassword = .empty
                        onSignPress()
                    }
                    .crossPlatformSheet(isPresented: $fastPasswordPresented) {
                        FastVaultEnterPasswordView(
                            password: $fastVaultPassword,
                            vault: vault,
                            onSubmit: { onSignPress() }
                        )
                    }
            } else {
                PrimaryButton(title: NSLocalizedString("signTransaction", comment: "")) {
                    onSignPress()
                }
            }
        }
    }

    private func getAmount() -> String {
        // Check if this is a THORChain LP operation
        if let pool = transaction.memoFunctionDictionary["pool"], !pool.isEmpty {
            // For LP operations, show context about which pool
            let cleanPoolName = ThorchainService.cleanPoolName(pool)
            // Adding source asset to its pool (THORChain RUNE or any L1 asset).
            return transaction.amountDecimal.formatForDisplay() + " " + transaction.coin.ticker + " → " + cleanPoolName + " LP"
        }

        // Default display for non-LP operations
        return transaction.amountDecimal.formatForDisplay()
    }

    private func onSignPress() {
        let canSign = depositVerifyViewModel.validateSecurityScanner()
        if canSign {
            signAndMoveToNextView()
        }
    }

    func signAndMoveToNextView() {
        Task {
            do {
                let result = try await depositVerifyViewModel.createKeysignPayload(tx: transaction)
                await MainActor.run {
                    router.navigate(to: FunctionCallRoute.pair(
                        vault: vault,
                        tx: transaction,
                        keysignPayload: result,
                        fastVaultPassword: fastVaultPassword.nilIfEmpty
                    ))
                }
            } catch {
                await MainActor.run {
                    self.error = error as? HelperError
                }
            }
        }
    }
}

#Preview {
    FunctionCallVerifyScreen(
        transaction: .empty(coin: .example, vault: .example),
        vault: Vault.example
    )
}
