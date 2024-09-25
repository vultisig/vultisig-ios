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
        GeometryReader { geometry in
            image
                .resizable()
                .frame(width: 700, height: 700)
                .frame(width: 800, height: 800)
                .background(Color.turquoise600.opacity(0.15))
                .cornerRadius(cornerRadius)
                .overlay (
                    RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(Color.turquoise600, style: StrokeStyle(lineWidth: 2, dash: [24]))
                )
                .padding(.horizontal, padding)
                .offset(x: 20, y: 20)
        }
    }
    
    var text: some View {
        Text(NSLocalizedString(title, comment: ""))
            .font(.title30MenloUltraLight)
            .offset(y: -200)
            .foregroundColor(.neutral0)
            .multilineTextAlignment(.center)
    }
    
    var logo: some View {
        Image("VultisigLogo")
            .resizable()
            .frame(width: 48, height: 48)
            .offset(y: -20)
            .scaleEffect(3)
            .offset(y: -100)
    }
}
#endif
