//
//  ChainDetailActionButtons+macOS.swift
//  VultisigApp
//
//  Created by Johnny Luo on 9/5/2025.
//
#if os(macOS)
import SwiftUI
import WebKit

struct PlatformWebView: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> WKWebView {
        let webView = WKWebView()
        webView.setValue(false, forKey: "drawsBackground")
        webView.navigationDelegate = context.coordinator
        webView.load(URLRequest(url: url))
        return webView
    }

    // swiftlint:disable:next unused_parameter
    func updateNSView(_ nsView: WKWebView, context: Context) {}

    func makeCoordinator() -> WebViewCoordinator {
        WebViewCoordinator()
    }
}

#endif
