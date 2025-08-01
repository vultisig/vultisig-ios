//
//  SecurityScannerHeaderView.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 29/07/2025.
//

import SwiftUI

struct SecurityScannerHeaderView: View {
    let state: SecurityScannerState
    
    var body: some View {
        HStack(spacing: 4) {
            Group {
                switch state {
                case .scanning:
                    scanningView
                case .scanned(let securityScannerResult):
                    scannedView(provider: securityScannerResult.provider)
                case .notScanned(let provider):
                    notScannedView(provider: provider)
                case .idle:
                    EmptyView()
                }
            }
        }
        .font(.body14BrockmannMedium)
        .foregroundStyle(Color.lightText)
        .frame(height: 20)
        .transition(.opacity)
        .animation(.easeOut, value: state)
    }
    
    @ViewBuilder
    var scanningView: some View {
        InlineLoader()
        Text("securityScannerTransactionScanning".localized)
    }
    
    @ViewBuilder
    func scannedView(provider: String) -> some View {
        Image(systemName: "checkmark")
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(height: 8)
            .foregroundStyle(Color.alertTurquoise)
            .font(.system(size: 10, weight: .bold))
        Text("securityScannerTransactionScannedBy".localized)
        providerImage(provider)
    }
    
    @ViewBuilder
    func notScannedView(provider: String) -> some View {
        Image(systemName: "exclamationmark.triangle")
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: 16)
        Text("securityScannerTransactionNotScanned".localized)
        providerImage(provider)
    }
    
    func providerImage(_ provider: String) -> some View {
        Image(provider)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .tint(.lightText)
            .frame(height: 10)
    }
}
