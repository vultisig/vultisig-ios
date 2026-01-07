//
//  BottomSheetContainer.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 30/07/2025.
//

import SwiftUI

struct BottomSheetContainer<Content: BottomSheetContentView>: View {
    @Environment(\.dismiss) var dismiss
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 14) {
            header
            content
        }
        .background(content.bgColor ?? Theme.colors.bgSurface1)
        .padding(.top, 24)
        .padding(.horizontal, 16)
    }
    
    var header: some View {
        #if os(iOS)
        Capsule()
            .fill(Theme.colors.border)
            .frame(width: 64, height: 4)
            .cornerRadius(99)
        #elseif os(macOS)
        HStack {
            Spacer()
            Button {
                dismiss()
            } label: {
                Icon(named: "x", color: Theme.colors.textPrimary, size: 16)
                    .padding(8)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        #endif
    }
}
