//
//  GeneralCodeScannerView.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-05-30.
//

import SwiftUI
import SwiftData
import UniformTypeIdentifiers

#if os(iOS)
import CodeScanner
#endif

struct GeneralCodeScannerView: View {
    @Binding var showSheet: Bool
    @Binding var shouldJoinKeygen: Bool
    @Binding var shouldKeysignTransaction: Bool
    @Binding var qrCodeResult: String? // Add this binding to pass the QR code result back
    
    @State var isGalleryPresented = false
    @State var isFilePresented = false
    
    @Query var vaults: [Vault]
    
    @EnvironmentObject var deeplinkViewModel: DeeplinkViewModel
    @EnvironmentObject var viewModel: HomeViewModel
    
    var body: some View {
        ZStack(alignment: .bottom) {
            #if os(iOS)
            CodeScannerView(codeTypes: [.qr], isGalleryPresented: $isGalleryPresented, completion: handleScan)
            #endif
            HStack(spacing: 0) {
                galleryButton
                    .frame(maxWidth: .infinity)

                fileButton
                    .frame(maxWidth: .infinity)
            }
        }
        .ignoresSafeArea()
        .fileImporter(
            isPresented: $isFilePresented,
            allowedContentTypes: [UTType.image],
            allowsMultipleSelection: false
        ) { result in
            let qrCode = Utils.handleQrCodeFromImage(result: result)
            qrCodeResult = String(data: qrCode, encoding: .utf8) // Set the QR code result to the binding
            guard let url = URL(string: qrCodeResult ?? .empty) else {
                return
            }
            
            deeplinkViewModel.extractParameters(url, vaults: vaults)
            presetValuesForDeeplink(url)
            qrCodeResult = qrCodeResult // Set the QR code result to the binding
        }
    }
    
    var galleryButton: some View {
        Button {
            isGalleryPresented.toggle()
        } label: {
            OpenButton(buttonIcon: "photo.stack", buttonLabel: "uploadFromGallery")
        }
        .padding(.bottom, 50)
    }
    
    var fileButton: some View {
        Button {
            isFilePresented.toggle()
        } label: {
            OpenButton(buttonIcon: "folder", buttonLabel: "uploadFromFiles")
        }
        .padding(.bottom, 50)
    }
    
    #if os(iOS)
    private func handleScan(result: Result<ScanResult, ScanError>) {
        switch result {
        case .success(let result):
            guard let url = URL(string: result.string) else {
                return
            }
            deeplinkViewModel.extractParameters(url, vaults: vaults)
            presetValuesForDeeplink(url)
            qrCodeResult = result.string // Set the QR code result to the binding
        case .failure(_):
            return
        }
    }
    #endif
    
    private func presetValuesForDeeplink(_ url: URL) {
        shouldJoinKeygen = false
        shouldKeysignTransaction = false
        
        guard let type = deeplinkViewModel.type else {
            return
        }
        deeplinkViewModel.type = nil
        
        switch type {
        case .NewVault:
            moveToCreateVaultView()
        case .SignTransaction:
            moveToVaultsView()
        case .Unknown:
            return
        }
    }
    
    private func moveToCreateVaultView() {
        shouldJoinKeygen = true
        showSheet = false
    }
    
    private func moveToVaultsView() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            shouldKeysignTransaction = true
            showSheet = false
        }
    }
}

//#Preview {
//    GeneralCodeScannerView(
//        showSheet: .constant(true),
//        shouldJoinKeygen: .constant(true),
//        shouldKeysignTransaction: .constant(true)
//    )
//    .environmentObject(DeeplinkViewModel())
//}
