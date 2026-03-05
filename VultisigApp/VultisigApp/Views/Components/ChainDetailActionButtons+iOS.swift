//
//  ChainDetailActionButtons.swift
//  VultisigApp
//
//  Created by Johnny Luo on 9/5/2025.
//

#if os(iOS)
import SwiftUI
import WebKit

struct PlatformWebView: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> WKWebView {
        let webView = WKWebView()
        webView.isOpaque = false
        webView.backgroundColor = UIColor(Theme.colors.bgPrimary)
        webView.scrollView.backgroundColor = UIColor(Theme.colors.bgPrimary)
        webView.navigationDelegate = context.coordinator
        let request = URLRequest(url: url)
        webView.load(request)
        return webView
    }

    // swiftlint:disable:next unused_parameter
    func updateUIView(_ uiView: WKWebView, context: Context) {}

    func makeCoordinator() -> WebViewCoordinator {
        WebViewCoordinator()
    }
}
#endif
