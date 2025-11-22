//
//  GeneralCodeScannerView.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-05-30.
//
#if os(iOS)
import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import CodeScanner
import AVFoundation

struct GeneralCodeScannerView: View {
    @Binding var showSheet: Bool
    @Binding var shouldJoinKeygen: Bool
    @Binding var shouldKeysignTransaction: Bool
    @Binding var shouldSendCrypto: Bool
    @Binding var selectedChain: Chain?
    
    let sendTX: SendTransaction
    
    @Query var vaults: [Vault]
    
    @EnvironmentObject var deeplinkViewModel: DeeplinkViewModel
    
    private var idiom : UIUserInterfaceIdiom { UIDevice.current.userInterfaceIdiom }
    
    var body: some View {
        QRCodeScannerView(
            showScanner: $showSheet
        ) { result in
            guard let url = URL(string: result) else {
                return
            }
            deeplinkViewModel.extractParameters(url, vaults: vaults, isInternal: true)
        } handleScan: { result in
            handleScan(result: result)
        }
    }
    
    private func handleScan(result: Result<ScanResult, ScanError>) {
        switch result {
        case .success(let result):
            guard let url = URL(string: result.string) else {
                return
            }
            deeplinkViewModel.extractParameters(url, vaults: vaults, isInternal: true)
        case .failure(_):
            return
        }
    }
}

#Preview {
    GeneralCodeScannerView(
        showSheet: .constant(true),
        shouldJoinKeygen: .constant(true),
        shouldKeysignTransaction: .constant(true), 
        shouldSendCrypto: .constant(true),
        selectedChain: .constant(nil), 
        sendTX: SendTransaction()
    )
}
#endif
