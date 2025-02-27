//
//  LocalModeDisclaimer.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2025-02-27.
//

import SwiftUI

struct LocalModeDisclaimer: View {
    var body: some View {
        HStack(spacing: 12) {
            infoIcon
            text
        }
        .foregroundColor(.neutral0)
        .padding(12)
        .background(Color.blue600)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.persianBlue200, lineWidth: 1)
        )
        .padding(.horizontal, 8)
        .padding(.vertical, 12)
    }
    
    var infoIcon: some View {
        Image(systemName: "icloud.slash")
            .resizable()
            .frame(width: 16, height: 16)
            .foregroundColor(.persianBlue200)
    }
    
    var text: some View {
        Text(NSLocalizedString("youAreInLocalMode", comment: ""))
            .font(.body14BrockmannMedium)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#Preview {
    LocalModeDisclaimer()
}
