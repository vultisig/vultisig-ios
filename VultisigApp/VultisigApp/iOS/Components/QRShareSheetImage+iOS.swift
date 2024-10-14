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
            .frame(width: 250, height: 250)
            .frame(width: 300, height: 300)
            .background(Color.turquoise600.opacity(0.15))
            .cornerRadius(cornerRadius)
            .overlay (
                RoundedRectangle(cornerRadius: cornerRadius)
                .strokeBorder(Color.turquoise600, style: StrokeStyle(lineWidth: 2, dash: [24]))
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
