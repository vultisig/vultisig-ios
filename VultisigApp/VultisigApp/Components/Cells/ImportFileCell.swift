//
//  ImportFileCell.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-06-27.
//

import SwiftUI

struct ImportFileCell: View {

    let name: String
    let resetData: () -> Void

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
        Image(.file)
            .resizable()
            .frame(width: 24, height: 24)
    }

    func fileName(_ name: String) -> some View {
        Text(name)
            .font(Theme.fonts.caption12)
            .foregroundStyle(Theme.colors.textPrimary)
    }

    var closeButton: some View {
        Button {
            resetData()
        } label: {
            Image(systemName: "xmark")
                .font(Theme.fonts.bodyMMedium)
                .foregroundStyle(Theme.colors.textPrimary)
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
