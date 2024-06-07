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
    
    var body: some View {
        ZStack {
            Background()
            view
        }
        .frame(width: 300, height: 500)
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
                .frame(width: 220, height: 220)
                .frame(width: 240, height: 240)
                .background(Color.turquoise600.opacity(0.15))
                .cornerRadius(6)
                .overlay (
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(Color.turquoise600, style: StrokeStyle(lineWidth: 2, dash: [24]))
                )
                .padding(.horizontal, padding)
        }
    }
    
    var text: some View {
        Text(NSLocalizedString(title, comment: ""))
            .font(.body12Menlo)
            .foregroundColor(.neutral0)
            .multilineTextAlignment(.center)
            .frame(maxWidth: 200)
            .lineLimit(2)
    }
    
    var logo: some View {
        Image("VultisigLogo")
            .resizable()
            .frame(width: 48, height: 48)
            .offset(y: -20)
    }
}

#Preview {
    QRShareSheetImage(title: "thor1ls0p8e4ax7nxfeh37ncs25mn67ngmtzhwzkflk", image: Image("VultisigLogo"))
}
