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
        content
            .onAppear {
                setData()
            }
    }
    
    var cell: some View {
        VStack(spacing: 12) {
            image
            deviceId
            description
        }
        .padding(16)
        .frame(
            width: 150,
            height: 200
        )
        .background(Color.blue600)
        .cornerRadius(10)
        .overlay (
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.neutral0, lineWidth: 2)
                .opacity(isSelected ? 1 : 0)
        )
        .padding(1)
    }
    
    var image: some View {
        getDeviceImage()
            .frame(width: 50)
            .frame(maxHeight: .infinity)
    }
    
    var deviceId: some View {
        Text(getDeviceName())
            .font(.body18MenloMedium)
            .foregroundColor(.neutral0)
    }
    
    var description: some View {
        Text(id)
            .font(.body12Menlo)
            .foregroundColor(.neutral0)
            .frame(height: 30)
    }
    
    var check: some View {
        Image(systemName: "checkmark.circle.fill")
            .opacity(isSelected ? 1 : 0)
            .font(.body18MenloMedium)
            .foregroundColor(.neutral0)
            .padding(.horizontal, 2)
            .offset(x: -10, y: 10)
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
        } else {
            // likely it will be android device , let's treat it as phone
            // android eco-system has too many types of devices, hard to know what phone or tablet it is
            deviceName = "Phone"
        }
        return deviceName
    }
    
    private func getDeviceImage() -> some View {
        let idString = id.lowercased()
        
        if idString.contains("iphone") {
            return Image("iPhoneAsset")
                .resizable()
                .frame(width: 30, height: 50)
        } else if idString.contains("ipad") {
            return Image("iPadAsset")
                .resizable()
                .frame(width: 60, height: 80)
        } else if idString.contains("mac") {
            return Image("macAsset")
                .resizable()
                .frame(width: 100, height: 67)
        } else {
            // this could be android device, just show as phone
            return Image("iPhoneAsset")
                .resizable()
                .frame(width: 30, height: 50)
        }
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
