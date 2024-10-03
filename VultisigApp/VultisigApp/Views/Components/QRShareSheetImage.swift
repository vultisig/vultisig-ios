//
//  QRShareSheetImage.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-06-07.
//

import SwiftUI

enum QRShareSheetType: String {
    case Keygen = "JoinKeygen"
    case Send = "JoinSend"
    case Swap = "JoinSwap"
    case Address = ""
}

struct QRShareSheetImage: View {
    let image: Image
    let type: QRShareSheetType
    let addressData: String
    
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
            titleContent
            description
            Spacer()
            logo
        }
        .padding(.vertical, 48)
        .font(.body16MenloBold)
        .foregroundColor(.neutral0)
        .multilineTextAlignment(.center)
    }
    
    var description: some View {
        ZStack {
            switch type {
            case .Keygen:
                keygenDescription
            case .Send:
                keygenDescription
            case .Swap:
                keygenDescription
            case .Address:
                keygenDescription
            }
        }
    }
    
    var keygenDescription: some View {
        Text(NSLocalizedString("previewKeygenDescription", comment: ""))
    }
}

#Preview {
    QRShareSheetImage(
        image: Image("VultisigLogo"),
        type: .Keygen,
        addressData: "123456789123456789"
    )
    .ignoresSafeArea()
}
