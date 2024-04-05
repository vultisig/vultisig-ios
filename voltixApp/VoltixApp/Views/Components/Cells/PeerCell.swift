//
//  PeerCell.swift
//  VoltixApp
//
//  Created by Amol Kumar on 2024-04-04.
//

import SwiftUI

struct PeerCell: View {
    let id: String
    let isSelected: Bool
    
    var body: some View {
        HStack(spacing: 12) {
            image
            deviceInformation
            check
        }
        .padding(18)
        .padding(.vertical, 4)
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
    }
    
    var deviceInformation: some View {
        VStack(alignment: .leading, spacing: 12) {
            deviceId
            description
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
            .multilineTextAlignment(.leading)
    }
    
    var check: some View {
        Image(systemName: "checkmark.circle.fill")
            .opacity(isSelected ? 1 : 0)
            .font(.body18MenloMedium)
            .foregroundColor(.neutral0)
            .padding(.horizontal, 2)
    }
    
    private func getDeviceName() -> String {
        let idString = id.lowercased()
        let deviceName: String
        
        if idString.contains("iphone") {
            deviceName = "iPhone"
        } else if idString.contains("ipad") {
            deviceName = "iPad"
        } else {
            deviceName = "Unknown"
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
                .frame(width: 38, height: 50)
        } else {
            return Image("macAsset")
                .resizable()
                .frame(width: 40, height: 27)
        }
    }
}

#Preview {
    ZStack {
        Background()
        VStack {
            PeerCell(id: "iPhone 15 Pro-5D2F5D984A37", isSelected: true)
            PeerCell(id: "iPhone 15 Pro-5D2F 5D984A37erere reretgjkhgijerh gje rhgr e jhg wd wdr", isSelected: false)
            PeerCell(id: "iPad 15 Pro-5D2F5D984A37", isSelected: false)
            PeerCell(id: "iPhone 15 Pro-5D2F 5D984A37erere reretgjkhgijerh gje rhgr e jhg wd wdr", isSelected: true)
        }
    }
}
