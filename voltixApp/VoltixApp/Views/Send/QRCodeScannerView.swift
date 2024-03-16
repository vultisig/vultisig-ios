//
//  QRCodeScannerView.swift
//  VoltixApp
//
//  Created by Amol Kumar on 2024-03-15.
//

import SwiftUI
import CodeScanner

struct QRCodeScannerView: View {
    @Binding var showScanner: Bool
    let handleScan: (Result<ScanResult, ScanError>) -> Void
    
    var body: some View {
        VStack(spacing: 0) {
            topBar
            view
        }
    }
    
    var topBar: some View {
        HStack {
            NavigationBackSheetButton(showSheet: $showScanner)
            Spacer()
            title
            Spacer()
            NavigationBackSheetButton(showSheet: $showScanner)
                .opacity(0)
                .disabled(true)
        }
        .frame(height: 60)
        .padding(.horizontal, 16)
        .background(Color.blue800)
    }
    
    var title: some View {
        Text(NSLocalizedString("scan", comment: "Scan QR Code"))
            .font(.body)
            .bold()
            .foregroundColor(.neutral0)
    }
    
    var view: some View {
        ZStack {
            CodeScannerView(codeTypes: [.qr], completion: handleScan)
            outline
        }
    }
    
    var outline: some View {
        Image("QRScannerOutline")
            .offset(y: -50)
    }
}
