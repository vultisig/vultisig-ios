//
//  CreateVaultView+macOS.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-09-06.
//

#if os(macOS)
import SwiftUI

extension CreateVaultView {
    var main: some View {
        VStack {
            headerMac
            view
        }
    }
    
    var scanButton: some View {
        PrimaryNavigationButton(title: "scanQRStartScreen", type: .secondary) {
            MacScannerView(type: .NewVault, sendTx: SendTransaction(), selectedVault: selectedVault)
        }
    }
}
#endif
