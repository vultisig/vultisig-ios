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
                Theme.colors.bgPrimary
                    .ignoresSafeArea()

                cameraView
                    .showIf(!isPaused)

                viewportOverlay

                if showTooltip {
                    tooltipDismissLayer
                }

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
            VStack(spacing: 0) {
                header
                HelpTooltip(isPresented: $showTooltip, maxWidth: nil) {
                    tooltipContent
                }
                .padding(.top, 8)
                Spacer()
                uploadButton
                    .padding(.bottom, 30)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
        }

        var header: some View {
            HStack {
                backButton
                Spacer()
                Text("scanQRStartScreen".localized)
                    .font(Theme.fonts.bodyLMedium)
                    .foregroundStyle(Theme.colors.textPrimary)
                Spacer()
                HelpButton(isPresented: $showTooltip)
            }
        }

        var backButton: some View {
            Button {
                showScanner = false
            } label: {
                Image(systemName: "chevron.backward")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Theme.colors.textPrimary)
                    .frame(width: 44, height: 44)
                    .background(glassCircleBackground)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
        }

        private var tooltipDismissLayer: some View {
            Color.clear
                .contentShape(Rectangle())
                .ignoresSafeArea()
                .onTapGesture {
                    withAnimation(.interpolatingSpring) {
                        showTooltip = false
                    }
                }
        }

        private var glassCircleBackground: some View {
            Circle()
                .fill(Color.white.opacity(0.05))
                .overlay(
                    Circle()
                        .stroke(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.3),
                                    Color.white.opacity(0.05),
                                    Color.clear,
                                    Color.white.opacity(0.2)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                )
                .glassy(shape: Circle())
        }

        private var tooltipContent: some View {
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
        }

        private let tooltipBullets = [
            "scanQRCodeTooltipBullet1",
            "scanQRCodeTooltipBullet2",
            "scanQRCodeTooltipBullet3"
        ]

        var cameraView: some View {
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
        }

        var viewportOverlay: some View {
            GeometryReader { proxy in
                let rect = viewportRect(in: proxy)
                ZStack {
                    Path { path in
                        path.addRect(proxy.frame(in: .local))
                        path.addRoundedRect(in: rect, cornerSize: CGSize(width: 24, height: 24))
                    }
                    .fill(Theme.colors.bgPrimary.opacity(0.55), style: FillStyle(eoFill: true))

                    RoundedRectangle(cornerRadius: 24)
                        .stroke(Theme.colors.primaryAccent4, lineWidth: 1)
                        .frame(width: rect.width, height: rect.height)
                        .position(x: rect.midX, y: rect.midY)
                        .shadow(color: .black.opacity(0.25), radius: 2, x: 0, y: 4)
                }
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)
        }

        private func viewportRect(in proxy: GeometryProxy) -> CGRect {
            let horizontalInset: CGFloat = 24
            let topOffset = proxy.safeAreaInsets.top + 72
            let bottomOffset: CGFloat = 120
            let width = proxy.size.width - horizontalInset * 2
            let availableHeight = proxy.size.height - topOffset - bottomOffset
            return CGRect(
                x: horizontalInset,
                y: topOffset,
                width: width,
                height: max(availableHeight, 0)
            )
        }

        var uploadButton: some View {
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
                Text("uploadQRCode".localized)
            }
            .buttonStyle(PrimaryButtonStyle(type: .primary, size: .small))
        }
    }
#endif
