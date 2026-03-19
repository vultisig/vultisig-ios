//
//  AddressCopyBannerViewModifier.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 23/09/2025.
//

import SwiftUI

private struct AddressCopyBannerViewModifier: ViewModifier {
    @Binding var coin: Coin?
    var onFinish: () -> Void

    @State var isVisible: Bool = false
    @State var text: String = ""

    func body(content: Content) -> some View {
        content
            .overlay(
                NotificationBannerView(text: text, isVisible: $isVisible)
                    .padding(.bottom, isMacOS ? 24 : 0)
                    .showIf(isVisible)
                    .zIndex(2)
            )
            .onChange(of: coin) { _, coin in
                guard let coin else {
                    isVisible = false
                    text = ""
                    return
                }
                ClipboardManager.copyToClipboard(coin.address)
                isVisible = true
                text = String(format: "coinAddressCopied".localized, coin.chain.name)
            }
            .onChange(of: isVisible) { _, newValue in
                guard !newValue else { return }
                coin = nil
                onFinish()
            }
    }
}

extension View {
    func withAddressCopy(coin: Binding<Coin?>, onFinish: @escaping () -> Void = {}) -> some View {
        modifier(AddressCopyBannerViewModifier(coin: coin, onFinish: onFinish))
    }
}
