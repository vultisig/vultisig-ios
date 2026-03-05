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

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    class Coordinator: NSObject, WKNavigationDelegate {
        var spinner: UIActivityIndicatorView?

        func webView(_ webView: WKWebView, didStartProvisionalNavigation _: WKNavigation!) {
            let spinner = UIActivityIndicatorView(style: .large)
            spinner.color = .white
            spinner.translatesAutoresizingMaskIntoConstraints = false
            webView.addSubview(spinner)
            NSLayoutConstraint.activate([
                spinner.centerXAnchor.constraint(equalTo: webView.centerXAnchor),
                spinner.centerYAnchor.constraint(equalTo: webView.centerYAnchor)
            ])
            spinner.startAnimating()
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
