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
        .frame(width: 300, height: 500)
    }
    
    var qrCode: some View {
        GeometryReader { geometry in
            image
                .resizable()
                .frame(width: 220, height: 220)
                .frame(width: 240, height: 240)
                .background(Color.turquoise600.opacity(0.15))
                .cornerRadius(cornerRadius)
                .overlay (
                    RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(Color.turquoise600, style: StrokeStyle(lineWidth: 2, dash: [24]))
                )
                .padding(.horizontal, padding)
        }
    }
    
    var text: some View {
        Text(NSLocalizedString(title, comment: ""))
            .font(.body12Menlo)
            .frame(maxWidth: 200)
            .lineLimit(2)
            .foregroundColor(.neutral0)
            .multilineTextAlignment(.center)
    }
    
    var logo: some View {
        Image("VultisigLogo")
            .resizable()
            .frame(width: 48, height: 48)
            .offset(y: -20)
    }
}
#endif
