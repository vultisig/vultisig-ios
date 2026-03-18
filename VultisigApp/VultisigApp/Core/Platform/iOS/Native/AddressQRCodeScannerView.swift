//
//  AddressQRCodeScannerView.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 03/09/2025.
//
#if os(iOS)
import SwiftUI

import CodeScanner
import AVFoundation

struct AddressQRCodeScannerView: View {
    @Binding var showScanner: Bool
    let onAddress: (String) -> Void

    var body: some View {
        QRCodeScannerView(
            showScanner: $showScanner,
            isPaused: .constant(false)
        ) { address in
            onAddress(address)
        }
    }
}
#endif
