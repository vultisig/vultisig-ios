//
//  QRShareSheetImage.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-06-07.
//

import SwiftUI

struct QRShareSheetImage: View {
    let title: String
    let image: Image
    
    let padding: CGFloat = 30
    
#if os(iOS)
    let cornerRadius: CGFloat = 6
#elseif os(macOS)
    let cornerRadius: CGFloat = 30
#endif
    
    var body: some View {
        ZStack {
            Background()
            view
        }
#if os(iOS)
        .frame(width: 300, height: 500)
#elseif os(macOS)
        .frame(width: 900, height: 1500)
#endif
    }
    
    var view: some View {
        VStack(spacing: 32) {
            qrCode
            text
            Spacer()
            logo
        }
        .padding(.vertical, 40)
    }
    
    var qrCode: some View {
        GeometryReader { geometry in
            image
                .resizable()
#if os(iOS)
                .frame(width: 220, height: 220)
                .frame(width: 240, height: 240)
#elseif os(macOS)
                .frame(width: 700, height: 700)
                .frame(width: 800, height: 800)
#endif
                .background(Color.turquoise600.opacity(0.15))
                .cornerRadius(cornerRadius)
                .overlay (
                    RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(Color.turquoise600, style: StrokeStyle(lineWidth: 2, dash: [24]))
                )
                .padding(.horizontal, padding)
#if os(macOS)
                .offset(x: 20, y: 20)
#endif
        }
    }
    
    var text: some View {
        Text(NSLocalizedString(title, comment: ""))
#if os(iOS)
            .font(.body12Menlo)
            .frame(maxWidth: 200)
            .lineLimit(2)
#elseif os(macOS)
            .font(.title30MenloUltraLight)
            .offset(y: -200)
#endif
            .foregroundColor(.neutral0)
            .multilineTextAlignment(.center)
    }
    
    var logo: some View {
        Image("VultisigLogo")
            .resizable()
            .frame(width: 48, height: 48)
            .offset(y: -20)
#if os(macOS)
            .scaleEffect(3)
            .offset(y: -100)
#endif
    }
}

#Preview {
    QRShareSheetImage(title: "thor1ls0p8e4ax7nxfeh37ncs25mn67ngmtzhwzkflk", image: Image("VultisigLogo"))
        .frame(width: 900, height: 1500)
}
