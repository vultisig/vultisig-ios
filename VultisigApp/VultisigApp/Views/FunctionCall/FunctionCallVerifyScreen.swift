//
//  FunctionCallVerifyView.swift
//  VultisigApp
//
//  Created by Enrique Souza Soares on 14/05/24.
//

import Foundation
import SwiftUI

struct FunctionCallVerifyScreen: View {
//    @Binding var keysignPayload: KeysignPayload?
    @StateObject var depositViewModel = FunctionCallViewModel()
    @StateObject var depositVerifyViewModel = FunctionCallVerifyViewModel()
    @ObservedObject var tx: SendTransaction
    let vault: Vault
    
    @EnvironmentObject var settingsViewModel: SettingsViewModel
    
    @State var fastPasswordPresented = false
    @State var isForReferral = false
    @State private var keysignPayload: VerifyKeysignPayload?
    @State private var error: HelperError?
    
    var body: some View {
        Screen(title: "verify".localized) {
            VStack(spacing: 0) {
                if isForReferral {
                    ReferralSendOverviewView(sendTx: tx)
                } else {
                    summary
                }
                
                Spacer()
                pairedSignButton
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .blur(radius: depositVerifyViewModel.isLoading ? 1 : 0)
        }
        .onDisappear {
            depositVerifyViewModel.isLoading = false
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
        .navigationDestination(item: $keysignPayload) { payload in
            FunctionCallRouteBuilder().buildPairScreen(
                vault: vault,
                tx: tx,
                keysignPayload: payload.payload,
                fastVaultPassword: tx.fastVaultPassword.nilIfEmpty
            )
        }
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
            do {
                let result = try await depositVerifyViewModel.createKeysignPayload(
                    tx: tx,
                    vault: vault
                )
                await MainActor.run {
                    self.keysignPayload = .init(payload: result)
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
        depositViewModel: FunctionCallViewModel(),
        depositVerifyViewModel: FunctionCallVerifyViewModel(),
        tx: SendTransaction(),
        vault: Vault.example
    )
    .environmentObject(SettingsViewModel())
}
