//
//  ReceiveQRCodeBottomSheet.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 22/09/2025.
//

import SwiftUI

struct ReceiveQRCodeBottomSheet: View {
    let groupedChain: GroupedChain
    @Binding var isPresented: Bool
    
    @State var qrCodeImage: Image?
    @State var addressToCopy: GroupedChain?
    @Environment(\.displayScale) var displayScale
    @Environment(\.dismiss) var dismiss
    @StateObject var shareSheetViewModel = ShareSheetViewModel()
    
    var body: some View {
        GeometryReader { proxy in
            VStack(spacing: 24) {
                topSection
                Text(groupedChain.address)
                    .font(Theme.fonts.footnote)
                    .foregroundStyle(Theme.colors.textPrimary)
                    .frame(maxWidth: 216)
                    .multilineTextAlignment(.center)
                bottomSection
            }
            .padding(.top, 40)
            .padding(.horizontal, 16)
            .background(backgroundView(width: proxy.size.width))
            .overlay(macOSOverlay)
            .withAddressCopy(group: $addressToCopy)
            .presentationDetents([.height(465)])
            .presentationBackground(Theme.colors.bgSecondary)
            .presentationDragIndicator(.visible)
        }
        .frame(height: 465)
        .onLoad {
            let qrCodeImage = QRCodeGenerator().generateImage(
                qrStringData: groupedChain.address,
                size: CGSize(width: 200, height: 200),
                logoImage: PlatformImage(named: groupedChain.logo),
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
                addressData: groupedChain.address
            )
        }
    }
    
    @ViewBuilder
    func backgroundView(width: CGFloat) -> some View {
        let cornerRadius: CGFloat = 34
        ZStack(alignment: .bottom) {
            magicPattern
                .frame(maxWidth: width)
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            LinearGradient(
                stops: [
                    Gradient.Stop(color: Theme.colors.bgSecondary, location: 0.50),
                    Gradient.Stop(color: Theme.colors.bgSecondary.opacity(0.5), location: 0.85),
                    Gradient.Stop(color: Theme.colors.bgSecondary.opacity(0), location: 1.00),
                ],
                startPoint: UnitPoint(x: 0.5, y: 1),
                endPoint: UnitPoint(x: 0.5, y: 0)
            )
            .frame(height: 230)
        }
    }
    
    var magicPattern: some View {
        Image("magic-pattern")
            .resizable()
            .scaledToFill()
            .opacity(0.2)
            .frame(maxHeight: .infinity)
            .clipped()
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
            
            Text("\("receive".localized) \(groupedChain.name)")
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
                addressToCopy = groupedChain
            }
        }
    }
    
    @ViewBuilder
    var macOSOverlay: some View {
        #if os(macOS)
        VStack(alignment: .trailing) {
            CircularIconButton(icon: "x") {
                dismiss()
            }
            .padding(16)
            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        #else
        EmptyView()
        #endif
    }
}

#Preview {
    @Previewable @State var show = true
    return VStack {
        Button("Show QR Code") {
            show = true
        }
    }
    .overlay(show ? ReceiveQRCodeBottomSheet(groupedChain: .example, isPresented: $show) : nil)
    
}
