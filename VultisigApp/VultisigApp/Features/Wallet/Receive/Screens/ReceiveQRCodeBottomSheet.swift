//
//  ReceiveQRCodeBottomSheet.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 22/09/2025.
//

import SwiftUI

struct ReceiveQRCodeBottomSheet: View {
    let coin: Coin
    let isNativeCoin: Bool
    var onCopy: (Coin) -> Void
    
    @State var qrCodeImage: Image?
    @Environment(\.displayScale) var displayScale
    @Environment(\.dismiss) var dismiss
    @StateObject var shareSheetViewModel = ShareSheetViewModel()
    
    var coinLogo: String {
        isNativeCoin ? coin.chain.logo : coin.logo
    }
    
    var coinName: String {
        isNativeCoin ? coin.chain.name : coin.ticker
    }
    
    var body: some View {
        VStack(spacing: 24) {
            topSection
            Text(coin.address)
                .font(Theme.fonts.footnote)
                .foregroundStyle(Theme.colors.textPrimary)
                .frame(maxWidth: 216)
                .multilineTextAlignment(.center)
            bottomSection
        }
        .padding(.top, 40)
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity) // Use maxWidth instead of GeometryReader
        .frame(height: 465)
        .background(
            // Capture width using overlay instead of GeometryReader
            GeometryReader { proxy in
                ModalBackgroundView(width: proxy.size.width)
            }
        )
        .presentationDetents([.height(465)])
        .presentationBackground(Theme.colors.bgSecondary)
        .presentationDragIndicator(.visible)
        .onLoad {
            let qrCodeImage = QRCodeGenerator().generateImage(
                qrStringData: coin.address,
                size: CGSize(width: 200, height: 200),
                logoImage: PlatformImage(named: coinLogo),
                scale: displayScale
            )
            
            guard let qrCodeImage else {
                return
            }
            
            self.qrCodeImage = qrCodeImage
            shareSheetViewModel.render(
                qrCodeImage: qrCodeImage,
                qrCodeData: nil,
                displayScale: displayScale,
                type: .Address,
                addressData: coin.address
            )
        }
        .crossPlatformToolbar(ignoresTopEdge: true, showsBackButton: true)
    }

    var topSection: some View {
        VStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 24)
                .fill(Theme.colors.bgSecondary)
                .overlay(
                    qrCodeImage?
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .padding(8)
                )
            
            Text("\("receive".localized) \(coinName)")
                .font(Theme.fonts.bodyMMedium)
                .foregroundStyle(Theme.colors.textPrimary)
        }
        .padding(.horizontal, 8)
        .padding(.top, 8)
        .padding(.bottom, 16)
        .frame(width: 216, height: 247)
        .background(Image("qr-code-container").resizable())
    }
    
    var bottomSection: some View {
        HStack(spacing: 8) {
            if let image = shareSheetViewModel.renderedImage {
                CrossPlatformShareButton(image: image, caption: shareSheetViewModel.qrCodeData ?? .empty) { onShare in
                    PrimaryButton(title: "share".localized, type: .secondary, action: onShare)
                }
            }
            PrimaryButton(title: "copyAddress".localized) {
                    onCopy(coin)
            }
        }
    }
}

#Preview {
    @Previewable @State var show = true
    return VStack {
        Button("Show QR Code") {
            show = true
        }
    }
    .overlay(show ? ReceiveQRCodeBottomSheet(coin: .example, isNativeCoin: false, onCopy: { _ in }) : nil)
    
}
