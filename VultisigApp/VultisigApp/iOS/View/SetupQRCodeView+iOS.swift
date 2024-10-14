//
//  SetupQRCodeView+iOS.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-09-21.
//

#if os(iOS)
import SwiftUI

extension SetupQRCodeView {
    var content: some View {
        ZStack {
            Background()
            main
        }
        .navigationTitle(NSLocalizedString("setup", comment: "Setup title"))
        .toolbar {
            ToolbarItem(placement: Placement.topBarTrailing.getPlacement()) {
                NavigationHelpButton()
            }
        }
    }
    
    var main: some View {
        view
    }
    
    var pairButton: some View {
        ZStack {
            if ProcessInfo.processInfo.isiOSAppOnMac {
                pairMacButton
            } else {
                pairPhoneButton
            }
        }
    }
    
    var pairPhoneButton: some View {
        Button(action: {
            showSheet = true
        }) {
            OutlineButton(title: "pair")
        }
        .sheet(isPresented: $showSheet, content: {
            GeneralCodeScannerView(
                showSheet: $showSheet,
                shouldJoinKeygen: $shouldJoinKeygen,
                shouldKeysignTransaction: .constant(false), // CodeScanner used for keygen only
                shouldSendCrypto: .constant(false),         // -
                selectedChain: .constant(nil),              // -
                sendTX: SendTransaction()                   // -
            )
        })
        .navigationDestination(isPresented: $shouldJoinKeygen) {
            JoinKeygenView(vault: makeVault())
        }
    }
    
    var pairMacButton: some View {
        NavigationLink {
            GeneralQRImportMacView(type: .NewVault)
        } label: {
            OutlineButton(title: "pair")
        }
    }
}
#endif
