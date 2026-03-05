//
//  ChainDetailActionButtons+Coordinator.swift
//  VultisigApp
//

#if os(iOS) || os(macOS)
import WebKit

#if os(iOS)
private typealias PlatformSpinner = UIActivityIndicatorView
#else
private typealias PlatformSpinner = NSProgressIndicator
#endif

class WebViewCoordinator: NSObject, WKNavigationDelegate {
    private var spinner: PlatformSpinner?

    func webView(_ webView: WKWebView, didStartProvisionalNavigation _: WKNavigation!) {
        #if os(iOS)
        let spinner = UIActivityIndicatorView(style: .large)
        spinner.color = .white
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
        spinner?.removeFromSuperview()
        spinner = nil
    }

    func webView(_: WKWebView, didFail _: WKNavigation!, withError _: Error) {
        spinner?.removeFromSuperview()
        spinner = nil
    }
}
#endif
