//
//  QRCodeScannerView.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-03-15.
//
#if os(iOS)
    import AVFoundation
    import CodeScanner
    import SwiftUI

    struct QRCodeScannerView: View {
        @Binding var showScanner: Bool
        @Binding var isPaused: Bool
        var handleImport: (String) -> Void

        @State private var isGalleryPresented = false
        @State private var isFilePresented = false
        @State private var showErrorPopup = false
        @State private var showTooltip = false

        private var idiom: UIUserInterfaceIdiom {
            UIDevice.current.userInterfaceIdiom
        }

        var body: some View {
            ZStack {
                LinearGradient(
                    colors: [Theme.colors.bgPrimary, Theme.colors.bgSurface2],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
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
                if showTooltip {
                    tooltip
                }
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
            .foregroundStyle(Theme.colors.textPrimary)
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
            Button {
                withAnimation(.interpolatingSpring) {
                    showTooltip.toggle()
                }
            } label: {
                getIcon(for: "info.circle")
            }
        }

        var tooltip: some View {
            VStack(alignment: .leading, spacing: 6) {
                Text("scanQRCodeTooltipTitle".localized)
                    .font(Theme.fonts.bodySMedium)
                VStack(alignment: .leading, spacing: 4) {
                    Text("scanQRCodeTooltipSubtitle".localized)
                        .font(Theme.fonts.footnote)
                    ForEach(tooltipBullets, id: \.self) { bullet in
                        HStack(alignment: .top, spacing: 6) {
                            Text("•").font(Theme.fonts.footnote)
                            Text(bullet.localized)
                                .font(Theme.fonts.footnote)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
            .foregroundStyle(Theme.colors.textDark)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.leading, 16)
            .padding(.trailing, 16)
            .padding(.top, 24)
            .padding(.bottom, 12)
            .background(Theme.colors.textPrimary)
            .clipShape(TooltipShape(arrowXFraction: 0.9))
            .padding(.horizontal, 16)
            .onTapGesture {
                withAnimation(.interpolatingSpring) {
                    showTooltip = false
                }
            }
        }

        private let tooltipBullets = [
            "scanQRCodeTooltipBullet1",
            "scanQRCodeTooltipBullet2",
            "scanQRCodeTooltipBullet3"
        ]

        var cameraView: some View {
            ZStack {
                CodeScannerView(
                    codeTypes: [.qr],
                    isPaused: isPaused,
                    isGalleryPresented: $isGalleryPresented,
                    videoCaptureDevice: AVCaptureDevice.zoomedCameraForQRCode(withMinimumCodeSize: 100)
                ) { result in
                    switch result {
                    case let .success(success):
                        handleImport(success.string)
                    case .failure:
                        showErrorPopup = true
                    }
                }

                overlay
            }
        }

        var overlay: some View {
            GeometryReader { proxy in
                let scanW = proxy.size.width - 48
                let scanH = scanW * 1.5
                let scanRect = CGRect(
                    x: 24,
                    y: (proxy.size.height - scanH) / 2,
                    width: scanW,
                    height: scanH
                )
                ZStack {
                    Path { path in
                        path.addRect(proxy.frame(in: .local))
                        path.addRoundedRect(in: scanRect, cornerSize: CGSize(width: 20, height: 20))
                    }
                    .fill(.black.opacity(0.55), style: FillStyle(eoFill: true))

                    RoundedRectangle(cornerRadius: 20)
                        .stroke(LinearGradient.qrBorderGradient, lineWidth: 3)
                        .frame(width: scanW, height: scanH)
                        .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
                }
            }
            .ignoresSafeArea()
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
            PrimaryButtonView(title: "uploadQRCode", leadingIcon: "share")
        }

        private func getIcon(for icon: String) -> some View {
            Image(systemName: icon)
                .padding(16)
                .contentShape(Rectangle())
        }
    }
#endif
