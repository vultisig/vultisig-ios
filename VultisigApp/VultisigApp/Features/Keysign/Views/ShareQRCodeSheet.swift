//
//  ShareQRCodeSheet.swift
//  VultisigApp
//

import SwiftUI
import VultisigUIResources

/// In-app replacement for the system share sheet on a secure keysign pairing
/// screen. Both actions read state already produced by `ShareSheetViewModel`
/// — the join URL and the branded QR image are never re-derived here, so
/// "Copy Link" can never diverge from what the QR encodes.
struct ShareQRCodeSheet: View {
    @ObservedObject var shareSheetViewModel: ShareSheetViewModel

    @State private var bannerText: String?

    var body: some View {
        VStack(spacing: 32) {
            Text("shareQRCode".localized)
                .font(Theme.fonts.title3)
                .foregroundStyle(Theme.colors.textPrimary)

            qrPreview

            buttons
        }
        .padding(.horizontal, 24)
        .padding(.top, 28)
        .padding(.bottom, 24)
        .frame(maxWidth: .infinity)
        .background(Theme.colors.bgSurface1)
        .withBanner(text: $bannerText)
        .presentationDetents([.height(420)])
        .presentationDragIndicator(.visible)
        .applySheetSize(420, 460)
    }

    private var qrPreview: some View {
        Theme.radius.xl.shape
            .fill(Theme.colors.bgSurface1)
            .overlay(
                shareSheetViewModel.qrCodeImage?
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .padding(12)
            )
            .frame(width: 200, height: 200)
            .background(VultisigImage("qr-code-container").resizable())
    }

    private var buttons: some View {
        HStack(spacing: 12) {
            PrimaryButton(title: "copyLink".localized, type: .secondary) {
                copyLink()
            }

            if let renderedImage = shareSheetViewModel.renderedImage {
                CrossPlatformShareButton(
                    image: renderedImage,
                    caption: shareSheetViewModel.qrCodeData ?? .empty
                ) { onShare in
                    PrimaryButton(title: "shareQRImage".localized, action: onShare)
                }
            }
        }
    }

    private func copyLink() {
        guard let qrCodeData = shareSheetViewModel.qrCodeData else { return }
        ClipboardManager.copyToClipboard(qrCodeData)
        bannerText = "linkCopied".localized
    }
}

#Preview {
    let viewModel = ShareSheetViewModel()
    return Color.clear
        .crossPlatformSheet(isPresented: .constant(true)) {
            ShareQRCodeSheet(shareSheetViewModel: viewModel)
        }
}
