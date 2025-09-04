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
    var handleImport: (String) -> Void
    var handleScan: (Result<ScanResult, ScanError>) -> Void
    
    @State var isGalleryPresented = false
    @State var isFilePresented = false
    
    private var idiom : UIUserInterfaceIdiom { UIDevice.current.userInterfaceIdiom }
    
    var body: some View {
        ZStack {
            cameraView
            content
        }
        .frame(maxWidth: idiom == .pad ? .infinity : nil, maxHeight: idiom == .pad ? .infinity : nil)
        .ignoresSafeArea()
        .fileImporter(
            isPresented: $isFilePresented,
            allowedContentTypes: [UTType.image],
            allowsMultipleSelection: false
        ) { result in
            do {
                let qrCode = try Utils.handleQrCodeFromImage(result: result)
                guard let result = String(data: qrCode, encoding: .utf8) else { return }
                handleImport(result)
            } catch {
                print(error)
            }
        }
    }
    
    var content: some View {
        VStack {
            header
            Spacer()
            menubuttons
        }
        .padding(.vertical, 8)
    }
    
    var header: some View {
        HStack {
            backButton
            Spacer()
            title
            Spacer()
            helpButton
        }
        .foregroundColor(Theme.colors.textPrimary)
        .font(Theme.fonts.bodyLMedium)
        .offset(y: 8)
    }
    
    var backButton: some View {
        Button {
            showScanner = false
        } label: {
            getIcon(for: "xmark")
        }
    }
    
    var title: some View {
        Text(NSLocalizedString("scanQRStartScreen", comment: ""))
    }
    
    var helpButton: some View {
        Link(destination: URL(string: Endpoint.supportDocumentLink)!) {
            getIcon(for: "questionmark.circle")
        }
    }
    
    var cameraView: some View {
        ZStack {
            CodeScannerView(
                codeTypes: [.qr],
                isGalleryPresented: $isGalleryPresented,
                videoCaptureDevice: AVCaptureDevice.zoomedCameraForQRCode(withMinimumCodeSize: 100),
                completion: handleScan
            )
            
            overlay
        }
    }
    
    var overlay: some View {
        Image("QRScannerOutline")
            .padding(60)
    }
    
    var menubuttons: some View {
        Menu {
            Button {
                isGalleryPresented.toggle()
            } label: {
                Label(
                    NSLocalizedString("photoLibrary", comment: ""),
                    systemImage: "photo.on.rectangle.angled"
                )
            }
            
            Button {
                isFilePresented.toggle()
            } label: {
                Label(
                    NSLocalizedString("chooseFiles", comment: ""),
                    systemImage: "folder"
                )
            }
        } label: {
            uploadButton
        }
        .buttonStyle(PrimaryButtonStyle(type: .primary, size: .medium))
        .padding(.horizontal, 16)
        .padding(.bottom, 30)
    }
    
    var uploadButton: some View {
        PrimaryButtonView(title: "uploadQR", leadingIcon: "arrow.up.document")
    }

    private func getIcon(for icon: String) -> some View {
        Image(systemName: icon)
            .padding(16)
            .contentShape(Rectangle())
    }
}
#endif
