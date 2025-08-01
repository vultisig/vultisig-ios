//
//  ImportFileCell.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-06-27.
//

import SwiftUI

struct ImportFileCell: View {
    @Environment(\.theme) var theme
    let name: String
    let resetData: () -> ()
    
    var body: some View {
        HStack {
            fileImage
            fileName(name)
            Spacer()
            closeButton
        }
        .padding(12)
    }
    
    var fileImage: some View {
        Image("FileIcon")
            .resizable()
            .frame(width: 24, height: 24)
    }
    
    func fileName(_ name: String) -> some View {
        Text(name)
            .font(theme.fonts.caption12)
            .foregroundColor(.neutral0)
    }
    
    var closeButton: some View {
        Button {
            resetData()
        } label: {
            Image(systemName: "xmark")
                .font(.body16MontserratMedium)
                .foregroundColor(.neutral0)
                .padding(8)
        }
        .buttonStyle(PlainButtonStyle())
        .background(Color.clear)
    }
}

#Preview {
    func reset() {
        print("RESET")
    }
    
    return ImportFileCell(name: "File", resetData: reset)
}
