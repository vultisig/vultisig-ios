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
            check
            
            VStack(alignment: .leading, spacing: 2) {
                deviceId
                description
            }
            
            Spacer()
        }
        .padding(16)
        .frame(height: 50)
        .background(Color.blue600)
        .cornerRadius(10)
        .overlay (
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.alertTurquoise, lineWidth: 2)
        )
        .padding(1)
        .padding(.horizontal)
    }
    
    var deviceId: some View {
        Text(deviceName)
            .font(.body14BrockmannMedium)
            .foregroundColor(.neutral0)
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    var description: some View {
        Text(NSLocalizedString("thisDevice", comment: ""))
            .font(.body12BrockmannMedium)
            .foregroundColor(.lightText)
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    var check: some View {
        Image(systemName: "checkmark.circle.fill")
            .font(.body24MontserratMedium)
            .foregroundColor(.alertTurquoise)
    }
}

#Preview {
    ThisDevicePeerCell(deviceName: "iPhone")
}
