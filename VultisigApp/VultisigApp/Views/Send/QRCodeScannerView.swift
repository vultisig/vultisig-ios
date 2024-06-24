//
//  QRCodeScannerView.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-03-15.
//

import SwiftUI
import UniformTypeIdentifiers

#if os(iOS)
import CodeScanner

struct QRCodeScannerView: View {
    @Binding var showScanner: Bool
    let handleScan: (Result<ScanResult, ScanError>) -> Void
    
    @State var isGalleryPresented = false
    @State var isFilePresented = false
    
    var body: some View {
        VStack(spacing: 0) {
            topBar
            view
        }
        .fileImporter(
            isPresented: $isFilePresented,
            allowedContentTypes: [UTType.image], // Ensure only images can be picked
            allowsMultipleSelection: false
        ) { result in
            let qrCodeFromImage = Utils.handleQrCodeFromImage(result: result)
            let (address, amount, message) = Utils.parseCryptoURI(String(data: qrCodeFromImage, encoding: .utf8) ?? .empty)
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
            codeScanner
            outline
                .allowsHitTesting(false)
        }
    }
    
    var outline: some View {
        Image("QRScannerOutline")
            .offset(y: -50)
    }
    
    var codeScanner: some View {
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
}
#endif
