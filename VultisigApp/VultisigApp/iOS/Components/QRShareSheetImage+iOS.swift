//
//  QRShareSheetImage+iOS.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-09-25.
//

#if os(iOS)
import SwiftUI

extension QRShareSheetImage {
    var content: some View {
        ZStack {
            Background()
            view
        }
        .frame(width: 375, height: 800)
    }

    var qrCode: some View {
        image
            .resizable()
            .aspectRatio(contentMode: .fit)
            .padding(24)
            .cornerRadius(cornerRadius)
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(Theme.colors.border, lineWidth: 2)
            )
            .padding(.horizontal, padding)
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
