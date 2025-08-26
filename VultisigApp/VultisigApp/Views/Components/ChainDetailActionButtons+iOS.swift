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
        let request = URLRequest(url: url)
        webView.load(request)
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}
}
#endif
