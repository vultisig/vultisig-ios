//
//  PhoneScannerView.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-08-30.
//

import SwiftUI

struct PhoneScannerView: View {
    let sendTx: SendTransaction
    @Binding var shouldJoinKeygen: Bool
    @Binding var shouldKeysignTransaction: Bool
    @Binding var shouldSendCrypto: Bool
    @Binding var selectedChain: Chain?
    
    @State var isGalleryPresented = false
    
    var body: some View {
        ZStack {
            Background()
            content
        }
        .navigationTitle(NSLocalizedString("pair", comment: ""))
    }
    
    var content: some View {
        VStack {
            Color.clear
                .frame(height: 1)
            scanner
        }
    }
    
    var scanner: some View {
        GeneralCodeScannerView(
            showSheet: .constant(true),
            shouldJoinKeygen: $shouldJoinKeygen,
            shouldKeysignTransaction: $shouldKeysignTransaction,
            shouldSendCrypto: $shouldSendCrypto,
            selectedChain: $selectedChain,
            sendTX: sendTx,
            isGalleryPresented: isGalleryPresented
        )
    }
}

#Preview {
    PhoneScannerView(
        sendTx: SendTransaction(),
        shouldJoinKeygen: .constant(false),
        shouldKeysignTransaction: .constant(false),
        shouldSendCrypto: .constant(false),
        selectedChain: .constant(nil)
    )
}
