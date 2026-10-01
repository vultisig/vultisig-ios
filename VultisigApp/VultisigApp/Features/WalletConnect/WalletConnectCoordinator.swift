//
//  WalletConnectCoordinator.swift
//  VultisigApp
//

import Combine
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
    func observeSessionProposals(_ handler: @escaping @MainActor (WalletConnectProposal) -> Void)
    func approve(
        proposal: WalletConnectProposal,
        approval: WalletConnectEVMNamespaceApproval
    ) async throws -> String
    func reject(proposal: WalletConnectProposal) async throws
}

@MainActor
final class WalletConnectCoordinator: ObservableObject {
    static let shared = WalletConnectCoordinator()

    @Published private(set) var pendingProposal: WalletConnectProposal?

    private let logger = Log.app.other
    private let pairingClient: WalletConnectPairingClient
    private let bindingStore: WalletConnectSessionBindingStoring
    private var isConfigured = false
    private(set) var configurationError: WalletConnectError?
    private var pairingURIInFlight: String?

    init(
        pairingClient: WalletConnectPairingClient? = nil,
        bindingStore: WalletConnectSessionBindingStoring = WalletConnectSessionBindingStore.shared
    ) {
        self.pairingClient = pairingClient ?? ReownWalletConnectPairingClient()
        self.bindingStore = bindingStore
    }

    func configureFromMainBundle() {
        do {
            let configuration = try WalletConnectConfiguration.fromMainBundle()
            try pairingClient.configure(with: configuration)
            pairingClient.observeSessionProposals { [weak self] proposal in
                self?.pendingProposal = proposal
            }
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

    func approvePendingProposal(with vault: Vault) async throws {
        guard let proposal = pendingProposal else {
            throw WalletConnectError.noPendingProposal
        }
        guard isConfigured else {
            throw configurationError ?? .notConfigured
        }

        let approval = try WalletConnectEVMNamespaceAdapter().buildApproval(
            requiredNamespaces: proposal.requiredNamespaces,
            optionalNamespaces: proposal.optionalNamespaces,
            accounts: vault.walletConnectEVMAccounts
        )
        let topic = try await pairingClient.approve(proposal: proposal, approval: approval)
        bindingStore.save(WalletConnectSessionBinding(
            topic: topic,
            vaultPubKeyECDSA: vault.pubKeyECDSA,
            dappName: proposal.name,
            dappURL: proposal.url,
            createdAt: Date()
        ))
        pendingProposal = nil
    }

    func rejectPendingProposal() async throws {
        guard let proposal = pendingProposal else {
            throw WalletConnectError.noPendingProposal
        }
        guard isConfigured else {
            throw configurationError ?? .notConfigured
        }

        try await pairingClient.reject(proposal: proposal)
        pendingProposal = nil
    }
}

enum WalletConnectError: LocalizedError, Equatable {
    case missingProjectId
    case notConfigured
    case invalidURI
    case noPendingProposal
    case configurationFailed(String)
    case pairingFailed(String)
    case approvalFailed(String)
    case rejectionFailed(String)
    case unsupportedCryptoRecovery

    var errorDescription: String? {
        switch self {
        case .missingProjectId:
            return NSLocalizedString("walletConnectErrorMissingProjectId", comment: "")
        case .notConfigured:
            return NSLocalizedString("walletConnectErrorNotConfigured", comment: "")
        case .invalidURI:
            return NSLocalizedString("walletConnectErrorInvalidURI", comment: "")
        case .noPendingProposal:
            return NSLocalizedString("walletConnectErrorNoPendingProposal", comment: "")
        case .configurationFailed(let message):
            return String(
                format: NSLocalizedString("walletConnectErrorConfigurationFailed", comment: ""),
                message
            )
        case .pairingFailed(let message):
            return String(
                format: NSLocalizedString("walletConnectErrorPairingFailed", comment: ""),
                message
            )
        case .approvalFailed(let message):
            return String(
                format: NSLocalizedString("walletConnectErrorApprovalFailed", comment: ""),
                message
            )
        case .rejectionFailed(let message):
            return String(
                format: NSLocalizedString("walletConnectErrorRejectionFailed", comment: ""),
                message
            )
        case .unsupportedCryptoRecovery:
            return NSLocalizedString("walletConnectErrorUnsupportedCryptoRecovery", comment: "")
        }
    }
}

#if canImport(WalletConnectSign) && canImport(Starscream)
@MainActor
private final class ReownWalletConnectPairingClient: WalletConnectPairingClient {
    private var configuredProjectId: String?
    private var proposalCancellable: AnyCancellable?
    private var proposalsByID: [String: Session.Proposal] = [:]

    func configure(with configuration: WalletConnectConfiguration) throws {
        guard configuredProjectId != configuration.projectId else { return }

        Networking.configure(
            relayHost: "relay.walletconnect.com",
            groupIdentifier: WidgetSharedStorage.appGroupIdentifier,
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

    func observeSessionProposals(_ handler: @escaping @MainActor (WalletConnectProposal) -> Void) {
        proposalCancellable = Sign.instance.sessionProposalPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] event in
                let snapshot = event.proposal.walletConnectSnapshot
                self?.proposalsByID[snapshot.id] = event.proposal
                handler(snapshot)
            }
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

    func approve(
        proposal: WalletConnectProposal,
        approval: WalletConnectEVMNamespaceApproval
    ) async throws -> String {
        guard let rawProposal = proposalsByID[proposal.id] else {
            throw WalletConnectError.noPendingProposal
        }

        do {
            let namespaces = try AutoNamespaces.build(
                sessionProposal: rawProposal,
                chains: approval.chains.compactMap { Blockchain($0) },
                methods: approval.methods,
                events: approval.events,
                accounts: approval.accounts.compactMap { Account($0) }
            )
            let session = try await Sign.instance.approve(
                proposalId: rawProposal.id,
                namespaces: namespaces,
                sessionProperties: proposal.sessionProperties
            )
            proposalsByID[proposal.id] = nil
            return session.topic
        } catch {
            throw WalletConnectError.approvalFailed(error.localizedDescription)
        }
    }

    func reject(proposal: WalletConnectProposal) async throws {
        guard let rawProposal = proposalsByID[proposal.id] else {
            throw WalletConnectError.noPendingProposal
        }

        do {
            try await Sign.instance.rejectSession(proposalId: rawProposal.id, reason: .userRejected)
            proposalsByID[proposal.id] = nil
        } catch {
            throw WalletConnectError.rejectionFailed(error.localizedDescription)
        }
    }
}

private extension Session.Proposal {
    var walletConnectSnapshot: WalletConnectProposal {
        WalletConnectProposal(
            id: String(describing: id),
            name: proposer.name,
            url: proposer.url,
            icons: proposer.icons,
            verificationStatus: nil,
            requiredNamespaces: requiredNamespaces.walletConnectRequests,
            optionalNamespaces: optionalNamespaces?.walletConnectRequests ?? [],
            sessionProperties: sessionProperties
        )
    }
}

private extension Dictionary where Key == String, Value == ProposalNamespace {
    var walletConnectRequests: [WalletConnectNamespaceRequest] {
        map { key, value in
            WalletConnectNamespaceRequest(
                namespace: key,
                chains: value.chains?.map(\.absoluteString) ?? [],
                methods: Array(value.methods).sorted(),
                events: Array(value.events).sorted()
            )
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

    private var socket: WebSocket?

    init(url: URL) {
        self.request = URLRequest(url: url)
    }

    func connect() {
        let socket = makeSocket()
        self.socket = socket
        socket.connect()
    }

    func disconnect() {
        socket?.disconnect()
    }

    func write(string: String, completion: (() -> Void)?) {
        socket?.write(string: string, completion: completion)
    }

    private func makeSocket() -> WebSocket {
        let socket = WebSocket(request: request)
        socket.callbackQueue = DispatchQueue(
            label: "com.vultisig.wallet.walletconnect.socket",
            qos: .utility,
            attributes: .concurrent
        )
        socket.onEvent = { [weak self] event in
            self?.handle(event)
        }
        return socket
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

    func observeSessionProposals(_: @escaping @MainActor (WalletConnectProposal) -> Void) {}

    func pair(uri _: String) async throws {
        await Task.yield()
        throw WalletConnectError.configurationFailed("WalletConnectSign or Starscream is not linked.")
    }

    func approve(
        proposal _: WalletConnectProposal,
        approval _: WalletConnectEVMNamespaceApproval
    ) async throws -> String {
        await Task.yield()
        throw WalletConnectError.configurationFailed("WalletConnectSign or Starscream is not linked.")
    }

    func reject(proposal _: WalletConnectProposal) async throws {
        await Task.yield()
        throw WalletConnectError.configurationFailed("WalletConnectSign or Starscream is not linked.")
    }
}
#endif
