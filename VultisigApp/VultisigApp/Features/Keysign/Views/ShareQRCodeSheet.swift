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
    @Binding var isPresented: Bool

    @State private var bannerText: String?
    @State private var dismissTask: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 0) {
            Text("shareQRCode".localized)
                .font(Theme.fonts.title3)
                .foregroundStyle(Theme.colors.textPrimary)
            Spacer()
            buttons
            Spacer()
        }
        .padding(.top, 22)
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity)
        .withBanner(text: $bannerText)
        .presentationDetents([.height(150)])
        .presentationBackground { Theme.colors.bgPrimary.padding(.bottom, -1000) }
        .background(Theme.colors.bgPrimary)
        .presentationDragIndicator(.visible)
        .applySheetSize(460, 150)
        .onDisappear { dismissTask?.cancel() }
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

        // Cancelled on disappear so a pending close can't dismiss a reopened sheet.
        dismissTask?.cancel()
        dismissTask = Task {
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled else { return }
            isPresented = false
        }
    }
}

#Preview {
    let viewModel = ShareSheetViewModel()
    return Color.clear
        .crossPlatformSheet(isPresented: .constant(true)) {
            ShareQRCodeSheet(shareSheetViewModel: viewModel, isPresented: .constant(true))
        }
}
