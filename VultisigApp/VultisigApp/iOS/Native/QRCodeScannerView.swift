//
//  QRCodeScannerView.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-03-15.
//
#if os(iOS)
import SwiftUI

import CodeScanner
import AVFoundation

struct QRCodeScannerView: View {
    @Binding var showScanner: Bool
    @Binding var address: String
    let handleScan: (Result<ScanResult, ScanError>) -> Void
    
    @State var isGalleryPresented = false
    @State var isFilePresented = false
    
    var body: some View {
        VStack(spacing: 0) {
            topBar
            view
        }
        .ignoresSafeArea()
        .fileImporter(
            isPresented: $isFilePresented,
            allowedContentTypes: [UTType.image],
            allowsMultipleSelection: false
        ) { result in
            do {
                let qrCode = try Utils.handleQrCodeFromImage(result: result)
                let result = String(data: qrCode, encoding: .utf8)
                
                address = result ?? ""
                showScanner = false
            } catch {
                print(error)
            }
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
            CodeScannerView(
                codeTypes: [.qr],
                isGalleryPresented: $isGalleryPresented,
                videoCaptureDevice: AVCaptureDevice.zoomedCameraForQRCode(withMinimumCodeSize: 100),
                completion: handleScan
            )
            buttonsStack
        }
    }
    
    var buttonsStack: some View {
        VStack {
            Spacer()
            buttons
        }
    }
    
    var buttons: some View {
        HStack(spacing: 0) {
            galleryButton
                .frame(maxWidth: .infinity)

            fileButton
                .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 50)
    }
    
    var galleryButton: some View {
        Button {
            isGalleryPresented.toggle()
        } label: {
            OpenButton(buttonIcon: "photo.stack", buttonLabel: "uploadFromGallery")
        }
        .padding(.bottom, 20)
    }
    
    var fileButton: some View {
        Button {
            isFilePresented.toggle()
        } label: {
            OpenButton(buttonIcon: "folder", buttonLabel: "uploadFromFiles")
        }
        .padding(.bottom, 20)
    }
}
#endif
