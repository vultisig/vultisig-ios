//
//  CreateVaultView+iOS.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-09-06.
//

#if os(iOS)
import SwiftUI

extension CreateVaultView {
    var main: some View {
        view
            .onChange(of: shouldJoinKeygen) { _, shouldNavigate in
                guard shouldNavigate else { return }
                router.navigate(to: OnboardingRoute.joinKeygen(
                    vault: createVault(),
                    selectedVault: selectedVault
                ))
                shouldJoinKeygen = false
            }
            .crossPlatformSheet(isPresented: $showSheet) {
                GeneralCodeScannerView(
                    showSheet: $showSheet,
                    shouldJoinKeygen: $shouldJoinKeygen,
                    shouldKeysignTransaction: .constant(false), // CodeScanner used for keygen only
                    shouldSendCrypto: .constant(false),         // -
                    selectedChain: .constant(nil),              // -
                    sendTX: SendTransaction()                   // -
                )
            }
    }
    
    var scanButton: some View {
        ZStack {
            if ProcessInfo.processInfo.isiOSAppOnMac {
                scanMacButton
            } else {
                scanPhoneButton
            }
        }
    }
    
    var scanPhoneButton: some View {
        PrimaryButton(title: "scanQRStartScreen", leadingIcon: "qr-code", type: .secondary) {
            showSheet = true
        }
    }
    
    var scanMacButton: some View {
        PrimaryButton(title: "scanQRStartScreen", leadingIcon: "qr-code", type: .secondary) {
            navigateToGeneralQRImport = true
        }
    }
}
#endif
