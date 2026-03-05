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

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    class Coordinator: NSObject, WKNavigationDelegate {
        var spinner: NSProgressIndicator?

        func webView(_ webView: WKWebView, didStartProvisionalNavigation _: WKNavigation!) {
            let spinner = NSProgressIndicator()
            spinner.style = .spinning
            spinner.translatesAutoresizingMaskIntoConstraints = false
            webView.addSubview(spinner)
            NSLayoutConstraint.activate([
                spinner.centerXAnchor.constraint(equalTo: webView.centerXAnchor),
                spinner.centerYAnchor.constraint(equalTo: webView.centerYAnchor)
            ])
            spinner.startAnimation(nil)
            self.spinner = spinner
        }

        func webView(_: WKWebView, didFinish _: WKNavigation!) {
            spinner?.removeFromSuperview()
            spinner = nil
        }

        func webView(_: WKWebView, didFail _: WKNavigation!, withError _: Error) {
            spinner?.removeFromSuperview()
            spinner = nil
        }
    }
}

#endif
