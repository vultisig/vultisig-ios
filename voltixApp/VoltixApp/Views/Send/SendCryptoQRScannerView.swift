//
//  SendCryptoQRScannerView.swift
//  VoltixApp
//
//  Created by Amol Kumar on 2024-03-15.
//

import SwiftUI
import CodeScanner

struct SendCryptoQRScannerView: View {
    @ObservedObject var viewModel: SendCryptoViewModel
    
    var body: some View {
        ZStack {
            qrCodeScanner
            outline
                .allowsHitTesting(false)
        }
    }
    
    var qrCodeScanner: some View {
        CodeScannerView(codeTypes: [.qr], completion: handleScan)
    }
    
    var outline: some View {
        Image("QRScannerOutline")
            .offset(y: -50)
    }
    
    private func handleScan(result: Result<ScanResult, ScanError>) {
        viewModel.moveToNextView()
    }
}

#Preview {
    SendCryptoQRScannerView(viewModel: SendCryptoViewModel())
}
