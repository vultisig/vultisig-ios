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
        webView.load(URLRequest(url: url))
        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}
}

#endif
