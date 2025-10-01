//
//  ReceiveQRCodeBottomSheet.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 22/09/2025.
//

import SwiftUI

struct ReceiveQRCodeBottomSheet: View {
    let coin: Coin
    @Binding var isPresented: Bool
    
    @State var qrCodeImage: Image?
    @State var addressToCopy: Coin?
    @Environment(\.displayScale) var displayScale
    @Environment(\.dismiss) var dismiss
    @StateObject var shareSheetViewModel = ShareSheetViewModel()
    
    var body: some View {
        GeometryReader { proxy in
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
            .background(ModalBackgroundView(width: proxy.size.width))
            .withAddressCopy(coin: $addressToCopy)
            .presentationDetents([.height(465)])
            .presentationBackground(Theme.colors.bgSecondary)
            .presentationDragIndicator(.visible)
        }
        .frame(height: 465)
        .onLoad {
            let qrCodeImage = QRCodeGenerator().generateImage(
                qrStringData: coin.address,
                size: CGSize(width: 200, height: 200),
                logoImage: PlatformImage(named: coin.logo),
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
                addressData: coin.logo
            )
        }
        .crossPlatformToolbar {
            #if os(macOS)
            CustomToolbarItem(placement: .leading) {
                ToolbarButton(image: "x") {
                    dismiss()
                }
            }
            #endif
        }
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
            
            Text("\("receive".localized) \(coin.chain.name)")
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
                CrossPlatformShareButton(image: image, caption: shareSheetViewModel.qrCodeData ?? .empty) {
                    PrimaryButtonView(title: "share".localized)
                }
                .buttonStyle(PrimaryButtonStyle(type: .secondary))
            }
            PrimaryButton(title: "copyAddress".localized) {
                addressToCopy = coin
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
    .overlay(show ? ReceiveQRCodeBottomSheet(coin: .example, isPresented: $show) : nil)
    
}
