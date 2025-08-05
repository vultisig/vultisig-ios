//
//  ThisDevicePeerCell.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2025-02-17.
//

import SwiftUI

struct ThisDevicePeerCell: View {
    let deviceName: String
    
    var body: some View {
        cell
    }
    
    var cell: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                deviceId
                description
            }
            
            Spacer()
        }
        .padding(16)
        .frame(height: 70)
        .background(Color.checkboxBlue)
        .cornerRadius(10)
        .overlay (
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.alertTurquoise.opacity(0.25), lineWidth: 1)
        )
        .padding(1)
    }
    
    var deviceId: some View {
        Text(deviceName)
            .font(Theme.fonts.bodySMedium)
            .foregroundColor(Theme.colors.textPrimary)
            .lineLimit(2)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    var description: some View {
        Text(NSLocalizedString("thisDevice", comment: ""))
            .font(Theme.fonts.caption12)
            .foregroundColor(.lightText)
            .lineLimit(2)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#Preview {
    ThisDevicePeerCell(deviceName: "iPhone")
}
