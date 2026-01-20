//
//  PeerCell.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-04-04.
//

import SwiftUI

struct PeerCell: View {
    let id: String
    let isSelected: Bool
    
    @State var isPhone: Bool = false
    
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
            
            check
        }
        .padding(16)
        .frame(height: 70)
        .background(isSelected ? Theme.colors.bgSuccess : Theme.colors.bgSurface1)
        .cornerRadius(16)
        .overlay (
            RoundedRectangle(cornerRadius: 16)
                .stroke(isSelected ? Theme.colors.alertSuccess : Theme.colors.borderLight, lineWidth: 1)
        )
        .padding(1)
    }
    
    var deviceId: some View {
        Text(getDeviceName())
            .font(Theme.fonts.bodySMedium)
            .foregroundColor(Theme.colors.textPrimary)
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    var description: some View {
        Text(id)
            .font(Theme.fonts.caption12)
            .foregroundColor(Theme.colors.textSecondary)
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    var check: some View {
        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
            .font(Theme.fonts.title2)
            .foregroundColor(isSelected ? Theme.colors.alertSuccess : Theme.colors.borderLight)
    }
    
    private func getDeviceName() -> String {
        let idString = id.lowercased()
        let deviceName: String
        
        if idString.contains("mac") {
            deviceName = "Mac"
        } else if idString.contains("iphone") {
            deviceName = "iPhone"
        } else if idString.contains("ipad") {
            deviceName = "iPad"
        } else if idString.contains("server-") {
            deviceName = "Server"
        } else if idString.contains("extension-") {
            deviceName = "Extension"
        } else if idString.contains("windows-") {
            deviceName = "Windows"
        } else {
            // likely it will be android device , let's treat it as phone
            // android eco-system has too many types of devices, hard to know what phone or tablet it is
            deviceName = "Phone"
        }
        return deviceName
    }
}

#Preview {
    let columns = [
        GridItem(.adaptive(minimum: 200)),
        GridItem(.adaptive(minimum: 200))
    ]
    
    return ZStack {
        Background()
        LazyVGrid(columns: columns, spacing: 30) {
            PeerCell(id: "iPhone 15 Pro-5D2F5D984A37", isSelected: true)
            PeerCell(id: "iPhone 15 Pro-5D2F 5D984A37erere reretgjkhgijerh gje rhgr e jhg wd wdr", isSelected: false)
            PeerCell(id: "iPad 15 Pro-5D2F5D984A37", isSelected: false)
            PeerCell(id: "iPhone 15 Pro-5D2F 5D984A37erere reretgjkhgijerh gje rhgr e jhg wd wdr", isSelected: true)
            PeerCell(id: "Pro-5D2F 5D984A37erere reretgjkhgijerh gje rhgr e jhg wd wdr", isSelected: true)
        }
    }
    .frame(minWidth: 900, minHeight: 600)
}
