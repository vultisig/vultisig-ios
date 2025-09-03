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
    @Binding var address: String
    let handleScan: (Result<ScanResult, ScanError>) -> Void
    
    var body: some View {
        QRCodeScannerView(showScanner: $showScanner) { address in
            self.address = address
        } handleScan: { result in
            handleScan(result)
        }
    }
}
#endif
