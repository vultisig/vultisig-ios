//
//  FunctionCallVerifyView.swift
//  VultisigApp
//
//  Created by Enrique Souza Soares on 14/05/24.
//

import Foundation
import SwiftUI

struct FunctionCallVerifyScreen: View {
    @Binding var keysignPayload: KeysignPayload?
    @ObservedObject var depositViewModel: FunctionCallViewModel
    @ObservedObject var depositVerifyViewModel: FunctionCallVerifyViewModel
    @ObservedObject var tx: SendTransaction
    let vault: Vault

    @EnvironmentObject var settingsViewModel: SettingsViewModel

    @State var fastPasswordPresented = false
    @State var isForReferral = false

    var body: some View {
        ZStack {
            Background()
            content
        }
        .gesture(DragGesture())
        .alert(isPresented: $depositVerifyViewModel.showAlert) {
            alert
        }
        .onDisappear {
            depositVerifyViewModel.isLoading = false
        }
        .onLoad {
            depositVerifyViewModel.onLoad()
            Task {
                await depositVerifyViewModel.scan(transaction: tx, vault: vault)
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

    var content: some View {
        VStack(spacing: 0) {
            if isForReferral {
                ReferralSendOverviewView(
                    sendTx: tx,
                    functionCallViewModel: depositViewModel,
                    functionCallVerifyViewModel: depositVerifyViewModel
                )
            } else {
                summary
            }

            Spacer()
            pairedSignButton
                .padding(.bottom, 40)
                .padding(.horizontal, 16)
        }
        .blur(radius: depositVerifyViewModel.isLoading ? 1 : 0)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    var alert: Alert {
        Alert(
            title: Text(NSLocalizedString("error", comment: "")),
            message: Text(NSLocalizedString(depositVerifyViewModel.errorMessage, comment: "")),
            dismissButton: .default(Text(NSLocalizedString("ok", comment: "")))
        )
    }

    var summary: some View {
        SendCryptoVerifySummaryView(
            input: SendCryptoVerifySummary(
                fromName: vault.name,
                fromAddress: tx.fromAddress,
                toAddress: tx.toAddress,
                network: tx.coin.chain.name,
                networkImage: tx.coin.chain.logo,
                memo: "",
                memoFunctionDictionary: depositViewModel.memoDictionary(for: tx.memoFunctionDictionary),
                feeCrypto: tx.gasInReadable,
                feeFiat: depositViewModel.feesInReadable(tx: tx, vault: vault),
                coinImage: tx.coin.logo,
                amount: getAmount(),
                coinTicker: tx.coin.ticker
            ),
            securityScannerState: $depositVerifyViewModel.securityScannerState
        )
        .padding(.horizontal, 16)
    }

    var pairedSignButton: some View {
        VStack {
            if tx.isFastVault {
                Text(NSLocalizedString("holdForPairedSign", comment: ""))
                    .foregroundColor(Theme.colors.textExtraLight)
                    .font(Theme.fonts.bodySMedium)

                LongPressPrimaryButton(
                    title: NSLocalizedString("signTransaction", comment: "")) {
                        fastPasswordPresented = true
                    } longPressAction: {
                        onSignPress()
                    }
                    .crossPlatformSheet(isPresented: $fastPasswordPresented) {
                        FastVaultEnterPasswordView(
                            password: $tx.fastVaultPassword,
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
        if let pool = tx.memoFunctionDictionary.get("pool"), !pool.isEmpty {
            // For LP operations, show context about which pool
            let cleanPoolName = ThorchainService.cleanPoolName(pool)
            if tx.coin.chain == .thorChain {
                // Adding RUNE to a specific pool
                return tx.amountDecimal.formatForDisplay() + " " + tx.coin.ticker + " → " + cleanPoolName + " LP"
            } else {
                // Adding L1 asset to its pool
                return tx.amountDecimal.formatForDisplay() + " " + tx.coin.ticker + " → " + cleanPoolName + " LP"
            }
        }

        // Default display for non-LP operations
        return tx.amountDecimal.formatForDisplay() + " " + tx.coin.ticker
    }

    private func onSignPress() {
        let canSign = depositVerifyViewModel.validateSecurityScanner()
        if canSign {
            signAndMoveToNextView()
        }
    }

    func signAndMoveToNextView() {
        Task {

            keysignPayload = await depositVerifyViewModel.createKeysignPayload(tx: tx, vault: vault)

            if keysignPayload != nil {
                depositViewModel.moveToNextView()
            }
        }
    }
}

#Preview {
    FunctionCallVerifyScreen(
        keysignPayload: .constant(nil),
        depositViewModel: FunctionCallViewModel(),
        depositVerifyViewModel: FunctionCallVerifyViewModel(),
        tx: SendTransaction(),
        vault: Vault.example
    )
    .environmentObject(SettingsViewModel())
}
