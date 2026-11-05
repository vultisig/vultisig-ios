//
//  BottomSheetContainer.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 30/07/2025.
//

import SwiftUI

struct BottomSheetContainer<Content: BottomSheetContentView>: View {
    @Binding var isPresented: Bool
    let content: Content

    init(isPresented: Binding<Bool>, @ViewBuilder content: () -> Content) {
        self._isPresented = isPresented
        self.content = content()
    }

    private static var systemGrabberTopInset: CGFloat { 26 }

    var body: some View {
        VStack(spacing: 14) {
            #if os(iOS)
            if !content.usesSystemGrabber {
                header
            }
            #else
            header
            #endif
            content
        }
        .background(content.bgColor ?? Theme.colors.bgSurface1)
        .padding(.top, content.usesSystemGrabber ? Self.systemGrabberTopInset : 24)
        .padding(.horizontal, 16)
    }

    var header: some View {
        #if os(iOS)
        Capsule()
            .fill(Theme.colors.border)
            .frame(width: 64, height: 4)
            .cornerRadius(Theme.radius.pill)
        #elseif os(macOS)
        HStack {
            Spacer()
            Button {
                isPresented = false
            } label: {
                Icon(.xmark, color: Theme.colors.textPrimary, size: 16)
                    .padding(8)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        #endif
    }
}
