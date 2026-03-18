//
//  BannerViewModifier.swift
//  VultisigApp
//

import SwiftUI

private struct BannerViewModifier: ViewModifier {
    @Binding var text: String?

    @State private var isVisible: Bool = false
    @State private var displayText: String = ""

    func body(content: Content) -> some View {
        content
            .overlay(
                NotificationBannerView(text: displayText, isVisible: $isVisible)
                    .padding(.bottom, isMacOS ? 24 : 0)
                    .showIf(isVisible)
                    .zIndex(2)
            )
            .onChange(of: text) { _, newValue in
                guard let newValue else { return }
                displayText = newValue
                isVisible = true
            }
            .onChange(of: isVisible) { _, newValue in
                guard !newValue else { return }
                text = nil
            }
    }
}

extension View {
    func withBanner(text: Binding<String?>) -> some View {
        modifier(BannerViewModifier(text: text))
    }
}
