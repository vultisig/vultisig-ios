//
//  LocalNetworkAuthorization.swift
//  VultisigApp
//

#if os(iOS)
import Foundation
import Network
import OSLog

/// Probes the app's iOS **Local Network** authorization.
///
/// iOS exposes no API to read Local Network permission directly, so the
/// established technique (credited to Apple DTS) is to advertise a throwaway
/// Bonjour service while simultaneously browsing the local network:
///
/// - Advertising the service succeeds only when access is **granted**
///   (`netServiceDidPublish`) → `.authorized`.
/// - Browsing enters its `.waiting` state (or fails) when the system has
///   **denied** access → `.denied`.
///
/// Starting the probe also triggers the system permission prompt the first time
/// it runs. A short timeout backstops the rare case where neither signal
/// arrives; it resolves `.denied` so the caller surfaces a recoverable,
/// retryable error instead of hanging on "Discovering".
///
/// > Caveat: on the very first run, while the system prompt is still on screen,
/// > neither signal has fired yet. If the user takes longer than `timeout` to
/// > respond, the probe reports `.denied`; the caller's Retry re-runs it and
/// > then observes the real decision. The common real-world case this fixes —
/// > access previously denied / toggled off — resolves in well under a second.
enum LocalNetworkAuthorization {
    enum Status: Equatable {
        case authorized
        case denied
    }

    /// Runs the probe once. Safe to call repeatedly (e.g. from a Retry button).
    /// - Parameter timeout: how long to wait before treating an inconclusive
    ///   probe as `.denied` (kept short so the UX never stalls).
    static func status(timeout: TimeInterval = 3) async -> Status {
        await Prober().status(timeout: timeout)
    }
}

/// Coordinates the advertiser + browser + timeout, funnelling the first decisive
/// signal into a single-shot continuation. All state is confined to the main run
/// loop: `NetService` publishing is run-loop driven and its delegate callbacks
/// need a live run loop, and the browser/timeout are scheduled there too so no
/// locking is required.
private final class Prober: NSObject, NetServiceDelegate, @unchecked Sendable {
    private let logger = Logger(subsystem: "com.vultisig.app", category: "local-network-authorization")
    /// The probe type MUST be one of the app's declared `NSBonjourServices`
    /// entries. iOS refuses to publish or browse an undeclared type even when
    /// Local Network access is *granted* — `NetService` fails with
    /// `NSNetServicesMissingRequiredConfigurationError` (-72008) and
    /// `NWBrowser`/DNSServiceBrowse returns `NoAuth` (-65555) — which the probe
    /// would misread as `.denied`. `_lnp._tcp` is declared in Info.plist and is
    /// otherwise unused, so it's a dedicated, authorized throwaway type that
    /// doesn't collide with the app's real `_http._tcp.` discovery.
    private let serviceType = "_lnp._tcp"

    private var browser: NWBrowser?
    private var service: NetService?
    private var continuation: CheckedContinuation<LocalNetworkAuthorization.Status, Never>?
    private var didFinish = false

    func status(timeout: TimeInterval) async -> LocalNetworkAuthorization.Status {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { [self] in
                self.continuation = continuation
                start(timeout: timeout)
            }
        }
    }

    private func start(timeout: TimeInterval) {
        let parameters = NWParameters()
        parameters.includePeerToPeer = true

        let browser = NWBrowser(for: .bonjour(type: serviceType, domain: nil), using: parameters)
        browser.stateUpdateHandler = { [weak self] state in
            self?.handleBrowser(state)
        }
        self.browser = browser
        browser.start(queue: .main)

        // NWBrowser wants the bare service type (`_lnp._tcp`); NetService wants
        // the trailing-dot form (`_lnp._tcp.`), which also matches the Info.plist
        // NSBonjourServices entry. Advertising with the wrong form can make the
        // browser never see the service → false timeout/deny.
        let service = NetService(domain: "local.", type: serviceType + ".", name: "VultisigLocalNetwork", port: 1100)
        service.delegate = self
        self.service = service
        service.publish()

        DispatchQueue.main.asyncAfter(deadline: .now() + timeout) { [weak self] in
            guard let self, !self.didFinish else { return }
            self.logger.info("Local Network probe timed out; treating as denied")
            self.finish(.denied)
        }
    }

    private func handleBrowser(_ state: NWBrowser.State) {
        switch state {
        case let .waiting(error):
            logger.error("Local Network denied (browser waiting): \(String(describing: error))")
            finish(.denied)
        case let .failed(error):
            logger.error("Local Network browser failed: \(String(describing: error))")
            finish(.denied)
        default:
            break
        }
    }

    // MARK: - NetServiceDelegate

    func netServiceDidPublish(_: NetService) {
        logger.info("Local Network authorized (service published)")
        finish(.authorized)
    }

    func netService(_: NetService, didNotPublish errorDict: [String: NSNumber]) {
        logger.error("Local Network service failed to publish: \(errorDict)")
        finish(.denied)
    }

    private func finish(_ status: LocalNetworkAuthorization.Status) {
        guard !didFinish else { return }
        didFinish = true
        browser?.cancel()
        service?.stop()
        browser = nil
        service = nil
        continuation?.resume(returning: status)
        continuation = nil
    }
}
#endif
