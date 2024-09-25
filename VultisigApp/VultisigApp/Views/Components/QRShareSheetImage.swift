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
        content
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
}

#Preview {
    QRShareSheetImage(title: "thor1ls0p8e4ax7nxfeh37ncs25mn67ngmtzhwzkflk", image: Image("VultisigLogo"))
        .frame(width: 900, height: 1500)
}
