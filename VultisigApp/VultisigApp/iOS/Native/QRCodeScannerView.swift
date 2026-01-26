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
    @Binding var isPaused: Bool
    var handleImport: (String) -> Void

    @State var isGalleryPresented = false
    @State var isFilePresented = false
    @State var showErrorPopup = false

    private var idiom: UIUserInterfaceIdiom { UIDevice.current.userInterfaceIdiom }

    var body: some View {
        ZStack {
            cameraView
                .showIf(!isPaused)
            content
            PopupCapsule(text: "noBarcodesFound".localized, showPopup: $showErrorPopup)
        }
        .frame(maxWidth: idiom == .pad ? .infinity : nil, maxHeight: idiom == .pad ? .infinity : nil)
        .ignoresSafeArea()
        .fileImporter(
            isPresented: $isFilePresented,
            allowedContentTypes: [UTType.image],
            allowsMultipleSelection: false
        ) { result in
                if let qrCode = try? Utils.handleQrCodeFromImage(result: result), let result = String(data: qrCode, encoding: .utf8) {
                    handleImport(result)
                } else {
                    showErrorPopup = true
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
                isPaused: isPaused,
                isGalleryPresented: $isGalleryPresented,
                videoCaptureDevice: AVCaptureDevice.zoomedCameraForQRCode(withMinimumCodeSize: 100)
            ) { result in
                switch result {
                case .success(let success):
                    handleImport(success.string)
                case .failure:
                    showErrorPopup = true
                }
            }

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
        PrimaryButtonView(title: "uploadQR", leadingIcon: "share")
    }

    private func getIcon(for icon: String) -> some View {
        Image(systemName: icon)
            .padding(16)
            .contentShape(Rectangle())
    }
}
#endif
