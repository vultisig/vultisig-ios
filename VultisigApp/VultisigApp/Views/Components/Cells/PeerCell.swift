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
                .opacity(isSelected ? 1 : 0)
        )
        .padding(1)
        .padding(.horizontal)
    }
    
    var deviceId: some View {
        Text(getDeviceName())
            .font(.body14BrockmannMedium)
            .foregroundColor(.neutral0)
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    var description: some View {
        Text(id)
            .font(.body12BrockmannMedium)
            .foregroundColor(.lightText)
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    var check: some View {
        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
            .font(.body24MontserratMedium)
            .foregroundColor(.alertTurquoise)
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
        GridItem(.adaptive(minimum: 200)),
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
