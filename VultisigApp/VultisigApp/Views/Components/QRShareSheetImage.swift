//
//  QRShareSheetImage.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-06-07.
//

import SwiftUI

struct QRShareSheetImage: View {
    let title: String
    let addressData: String
    
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
            Utils.getQrImage(
                data: addressData.data(using: .utf8), size: 240)
            .resizable()
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .padding(24)
            .frame(maxWidth: .infinity)
            .frame(height: geometry.size.width-(2*padding))
            .background(Color.turquoise600.opacity(0.15))
            .cornerRadius(10)
            .overlay (
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(Color.turquoise600, style: StrokeStyle(lineWidth: 2, dash: [56]))
            )
            .padding(.horizontal, padding)
        }
    }
    
    var text: some View {
        Text(title)
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
    QRShareSheetImage(title: "thor1ls0p8e4ax7nxfeh37ncs25mn67ngmtzhwzkflk", addressData: "")
}
