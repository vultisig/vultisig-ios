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

    @State private var localError: Error?
    @State private var isPaused: Bool = false

    private var idiom: UIUserInterfaceIdiom { UIDevice.current.userInterfaceIdiom }

    var body: some View {
        QRCodeScannerView(
            showScanner: $showSheet,
            isPaused: $isPaused
        ) { result in
            handle(urlString: result)
        }
        .withError(error: $localError, errorType: .warning) {
            localError = nil
        }
        .onChange(of: localError != nil) { _, newValue in
            isPaused = newValue
        }
    }

    private func handle(urlString: String) {
        guard let url = URL(string: urlString) else {
            return
        }
        do {
            let validDeeplink = try deeplinkViewModel.extractParameters(url, vaults: vaults, isInternal: true)
            if validDeeplink {
                showSheet = false
            }
        } catch let scanError {
            localError = scanError
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
