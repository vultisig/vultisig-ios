//
//  WalletConnectCoordinator.swift
//  VultisigApp
//

import CryptoSwift
import Foundation
import OSLog
#if canImport(WalletConnectSign) && canImport(Starscream)
import Starscream
import WalletConnectSign
#endif

@MainActor
protocol WalletConnectPairingClient {
    func configure(with configuration: WalletConnectConfiguration) throws
    func pair(uri: String) async throws
}

@MainActor
final class WalletConnectCoordinator: ObservableObject {
    static let shared = WalletConnectCoordinator()

    private let logger = Log.app.other
    private let pairingClient: WalletConnectPairingClient
    private var isConfigured = false
    private(set) var configurationError: WalletConnectError?
    private var pairingURIInFlight: String?

    init(pairingClient: WalletConnectPairingClient? = nil) {
        self.pairingClient = pairingClient ?? ReownWalletConnectPairingClient()
    }

    func configureFromMainBundle() {
        do {
            let configuration = try WalletConnectConfiguration.fromMainBundle()
            try pairingClient.configure(with: configuration)
            isConfigured = true
            configurationError = nil
        } catch let error as WalletConnectError {
            isConfigured = false
            configurationError = error
            logger.error("WalletConnect disabled: \(error.localizedDescription, privacy: .public)")
        } catch {
            isConfigured = false
            configurationError = .configurationFailed(error.localizedDescription)
            logger.error("WalletConnect disabled: \(error.localizedDescription, privacy: .public)")
        }
    }

    func pair(uri: String) async throws {
        guard let normalizedURI = WalletConnectURIParser.normalizedURI(from: uri) else {
            throw WalletConnectError.invalidURI
        }
        guard isConfigured else {
            throw configurationError ?? .notConfigured
        }
        guard pairingURIInFlight == nil else {
            throw WalletConnectError.pairingFailed("A WalletConnect pairing is already in progress")
        }

        pairingURIInFlight = normalizedURI
        defer { pairingURIInFlight = nil }
        try await pairingClient.pair(uri: normalizedURI)
    }
}

enum WalletConnectError: LocalizedError, Equatable {
    case missingProjectId
    case notConfigured
    case invalidURI
    case configurationFailed(String)
    case pairingFailed(String)
    case unsupportedCryptoRecovery

    var errorDescription: String? {
        switch self {
        case .missingProjectId:
            return "WalletConnect is disabled because WalletConnectProjectId is not configured."
        case .notConfigured:
            return "WalletConnect is not configured."
        case .invalidURI:
            return "Invalid WalletConnect URI."
        case .configurationFailed(let message):
            return "WalletConnect configuration failed: \(message)"
        case .pairingFailed(let message):
            return "WalletConnect pairing failed: \(message)"
        case .unsupportedCryptoRecovery:
            return "WalletConnect public-key recovery is not implemented yet."
        }
    }
}

#if canImport(WalletConnectSign) && canImport(Starscream)
@MainActor
private final class ReownWalletConnectPairingClient: WalletConnectPairingClient {
    private var configuredProjectId: String?

    func configure(with configuration: WalletConnectConfiguration) throws {
        guard configuredProjectId != configuration.projectId else { return }

        // TODO: Switch this to `WidgetSharedStorage.appGroupIdentifier` after Reown splits
        // app-group UserDefaults from Keychain access-group configuration. In Reown 1.0.7,
        // `groupIdentifier` is also used as `kSecAttrAccessGroup`, so local signing needs
        // the TeamID-prefixed keychain group rather than the App Group identifier.
        Networking.configure(
            relayHost: "relay.walletconnect.com",
            groupIdentifier: configuration.keychainAccessGroup,
            projectId: configuration.projectId,
            socketFactory: WalletConnectSocketFactory()
        )
        Pair.configure(metadata: AppMetadata(
            name: configuration.appName,
            description: configuration.appDescription,
            url: configuration.appURL.absoluteString,
            icons: [configuration.appIconURL.absoluteString],
            redirect: try AppMetadata.Redirect(native: "vultisig://", universal: nil)
        ))
        Sign.configure(crypto: WalletConnectCryptoProvider())
        configuredProjectId = configuration.projectId
    }

    func pair(uri: String) async throws {
        let walletConnectURI: WalletConnectURI
        do {
            walletConnectURI = try WalletConnectURI(uriString: uri)
        } catch {
            throw WalletConnectError.invalidURI
        }

        do {
            try await Pair.instance.pair(uri: walletConnectURI)
        } catch {
            throw WalletConnectError.pairingFailed(error.localizedDescription)
        }
    }
}

private struct WalletConnectCryptoProvider: CryptoProvider {
    func recoverPubKey(signature _: EthereumSignature, message _: Data) throws -> Data {
        // PR1 only pairs. Request verification/signing in later PRs must replace
        // this with a real recovery implementation before using methods that need it.
        throw WalletConnectError.unsupportedCryptoRecovery
    }

    func keccak256(_ data: Data) -> Data {
        Data(SHA3(variant: .keccak256).calculate(for: [UInt8](data)))
    }
}

private struct WalletConnectSocketFactory: WebSocketFactory {
    func create(with url: URL) -> WebSocketConnecting {
        WalletConnectSocket(url: url)
    }
}

// swiftlint:disable no_raw_urlrequest
private final class WalletConnectSocket: WebSocketConnecting {
    var isConnected = false
    var onConnect: (() -> Void)?
    var onDisconnect: ((Error?) -> Void)?
    var onText: ((String) -> Void)?
    var request: URLRequest

    private let socket: WebSocket

    init(url: URL) {
        self.request = URLRequest(url: url)
        self.socket = WebSocket(request: request)
        socket.callbackQueue = DispatchQueue(
            label: "com.vultisig.wallet.walletconnect.socket",
            qos: .utility,
            attributes: .concurrent
        )
        socket.onEvent = { [weak self] event in
            self?.handle(event)
        }
    }

    func connect() {
        socket.connect()
    }

    func disconnect() {
        socket.disconnect()
    }

    func write(string: String, completion: (() -> Void)?) {
        socket.write(string: string, completion: completion)
    }

    private func handle(_ event: WebSocketEvent) {
        switch event {
        case .connected:
            isConnected = true
            onConnect?()
        case .text(let text):
            onText?(text)
        case .disconnected, .cancelled, .peerClosed:
            isConnected = false
            onDisconnect?(nil)
        case .error(let error):
            isConnected = false
            onDisconnect?(error)
        case .binary, .pong, .ping, .viabilityChanged, .reconnectSuggested:
            break
        }
    }
}
// swiftlint:enable no_raw_urlrequest
#else
@MainActor
private final class ReownWalletConnectPairingClient: WalletConnectPairingClient {
    func configure(with _: WalletConnectConfiguration) throws {
        throw WalletConnectError.configurationFailed("WalletConnectSign or Starscream is not linked.")
    }

    func pair(uri _: String) async throws {
        await Task.yield()
        throw WalletConnectError.configurationFailed("WalletConnectSign or Starscream is not linked.")
    }
}
#endif
