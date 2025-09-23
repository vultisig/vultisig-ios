//
//  AddressCopyBannerViewModifier.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 23/09/2025.
//

import SwiftUI

private struct AddressCopyBannerViewModifier: ViewModifier {
    @Binding var group: GroupedChain?

    @State var isVisible: Bool = false
    @State var text: String = ""
    
    func body(content: Content) -> some View {
        content
            .overlay(
                NotificationBannerView(text: text, isVisible: $isVisible)
                    .showIf(isVisible)
                    .zIndex(2)
            )
            .onChange(of: group) { _, group in
                guard let group else {
                    isVisible = false
                    text = ""
                    return
                }
                ClipboardManager.copyToClipboard(group.address)
                isVisible = true
                text = String(format: "coinAddressCopied".localized, group.name)
            }
            .onChange(of: isVisible) { _, newValue in
                guard !newValue else { return }
                group = nil
            }
    }
}

extension View {
    func withAddressCopy(group: Binding<GroupedChain?>) -> some View {
        modifier(AddressCopyBannerViewModifier(group: group))
    }
}
