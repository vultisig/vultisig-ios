//
//  WebViewCoordinator.swift
//  VultisigApp
//

import WebKit

#if os(iOS)
private typealias PlatformSpinner = UIActivityIndicatorView
#else
private typealias PlatformSpinner = NSProgressIndicator
#endif

class WebViewCoordinator: NSObject, WKNavigationDelegate {
    private var spinner: PlatformSpinner?

    private func removeSpinner() {
        #if os(macOS)
        spinner?.stopAnimation(nil)
        #endif
        spinner?.removeFromSuperview()
        spinner = nil
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation _: WKNavigation!) {
        removeSpinner()
        #if os(iOS)
        let spinner = UIActivityIndicatorView(style: .large)
        spinner.color = UIColor(Theme.colors.textPrimary)
        spinner.startAnimating()
        #else
        let spinner = NSProgressIndicator()
        spinner.style = .spinning
        spinner.startAnimation(nil)
        #endif
        spinner.translatesAutoresizingMaskIntoConstraints = false
        webView.addSubview(spinner)
        NSLayoutConstraint.activate([
            spinner.centerXAnchor.constraint(equalTo: webView.centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: webView.centerYAnchor)
        ])
        self.spinner = spinner
    }

    func webView(_: WKWebView, didFinish _: WKNavigation!) {
        removeSpinner()
    }

    func webView(_: WKWebView, didFail _: WKNavigation!, withError _: Error) {
        removeSpinner()
    }

    func webView(_: WKWebView, didFailProvisionalNavigation _: WKNavigation!, withError _: Error) {
        removeSpinner()
    }
}
