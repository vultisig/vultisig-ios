//
//  QRShareSheetImage+macOS.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-09-25.
//

#if os(macOS)
import SwiftUI

extension QRShareSheetImage {
    var content: some View {
        ZStack {
            Background()
            view
        }
        .frame(width: 900, height: 1500)
    }

    var qrCode: some View {
        image
            .resizable()
            .frame(width: 700, height: 700)
            .frame(width: 800, height: 800)
            .background(Theme.colors.bgButtonPrimary.opacity(0.15))
            .cornerRadius(cornerRadius)
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                .strokeBorder(Theme.colors.bgButtonPrimary, style: StrokeStyle(lineWidth: 2, dash: [24]))
            )
            .padding(.horizontal, padding)
            .offset(x: 20, y: 20)
            .padding(.bottom, 50)
    }

    var logo: some View {
        VStack(spacing: 16) {
            Image("VultisigLogo")
                .resizable()
                .frame(width: 110, height: 110)

            Text("vultisig.com")
        }
        .offset(y: -20)
    }
}
#endif
