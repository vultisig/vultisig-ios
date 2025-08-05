//
//  SendCryptoTransactionDetailsRow.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 28/07/2025.
//

import SwiftUI

struct SendCryptoTransactionDetailsRow: View {
    let title: String
    let description: String
    let secondaryDescription: String?
    let bracketValue: String?
    let icon: String?
    
    init(
        title: String,
        description: String,
        secondaryDescription: String? = nil,
        bracketValue: String? = nil,
        icon: String? = nil
    ) {
        self.title = title
        self.description = description
        self.secondaryDescription = secondaryDescription
        self.bracketValue = bracketValue
        self.icon = icon
    }
    
    var body: some View {
        HStack(spacing: 2) {
            Text(NSLocalizedString(title, comment: ""))
                .foregroundColor(.extraLightGray)
                .lineLimit(1)
                .truncationMode(.tail)
            
            Spacer()
            
            if let icon {
                Image(icon)
                    .resizable()
                    .frame(width: 16, height: 16)
                    .cornerRadius(32)
            }
            
            VStack(alignment: .trailing, spacing: 2) {
                HStack(spacing: 2) {
                    Text(description)
                        .foregroundColor(.neutral0)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    
                    if let bracketValue {
                        Text("(\(bracketValue))")
                            .foregroundColor(.extraLightGray)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                
                if let secondaryDescription {
                    Text(secondaryDescription)
                        .foregroundColor(.extraLightGray)
                        .lineLimit(1)
                }
            }
        }
        .font(Theme.fonts.bodySMedium)
        .foregroundColor(.neutral0)
    }
}

#Preview {
    SendCryptoTransactionDetailsRow(title: "Test", description: "This is a test")
}
