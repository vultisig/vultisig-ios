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
    func observeSessionRequests(_ handler: @escaping @MainActor (WalletConnectIncomingRequest) -> Void)
    func observeAuthenticationRequests(_ handler: @escaping @MainActor (WalletConnectAuthenticationRequest) -> Void)
    func approve(
        proposal: WalletConnectProposal,
        approval: WalletConnectEVMNamespaceApproval
    ) async throws -> String
    func reject(proposal: WalletConnectProposal) async throws
    func respond(topic: String, requestId: WalletConnectRequestID, result: String) async throws
    func rejectRequest(topic: String, requestId: WalletConnectRequestID) async throws
    func rejectAuthentication(_ request: WalletConnectAuthenticationRequest) async throws
    func disconnect(topic: String) async throws
}

@MainActor
final class WalletConnectCoordinator: ObservableObject {
    static let shared = WalletConnectCoordinator()

    @Published private(set) var pendingProposal: WalletConnectProposal?
    @Published private(set) var pendingMessageRequest: WalletConnectIncomingRequest?

    private let logger = Log.app.other
    private let pairingClient: WalletConnectPairingClient
    private let bindingStore: WalletConnectSessionBindingStoring
    private var isConfigured = false
    private(set) var configurationError: WalletConnectError?
    private var pairingURIInFlight: String?

    init(
        pairingClient: WalletConnectPairingClient? = nil,
        bindingStore: WalletConnectSessionBindingStoring = WalletConnectSessionBindingStore.shared,
        isConfigured: Bool = false
    ) {
        self.pairingClient = pairingClient ?? ReownWalletConnectPairingClient()
        self.bindingStore = bindingStore
        self.isConfigured = isConfigured
        if isConfigured {
            observePairingClientEvents()
        }
    }

    func configureFromMainBundle() {
        do {
            let configuration = try WalletConnectConfiguration.fromMainBundle()
            try pairingClient.configure(with: configuration)
            observePairingClientEvents()
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

    private func observePairingClientEvents() {
        pairingClient.observeSessionProposals { [weak self] proposal in
            self?.pendingProposal = proposal
        }
        pairingClient.observeSessionRequests { [weak self] request in
            guard WalletConnectEVMNamespaceAdapter.supportedMethods.contains(request.method) else {
                Task { @MainActor in
                    await self?.rejectUnsupportedSessionRequest(request)
                }
                return
            }
            self?.pendingMessageRequest = request
        }
        pairingClient.observeAuthenticationRequests { [weak self] request in
            Task { @MainActor in
                await self?.rejectAuthenticationRequest(request)
            }
        }
    }

    private func rejectUnsupportedSessionRequest(_ request: WalletConnectIncomingRequest) async {
        do {
            try await pairingClient.rejectRequest(topic: request.topic, requestId: request.requestId)
        } catch {
            logger.error("Failed to reject WalletConnect request: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func rejectAuthenticationRequest(_ request: WalletConnectAuthenticationRequest) async {
        do {
            try await pairingClient.rejectAuthentication(request)
        } catch {
            logger.error("Failed to reject WalletConnect auth: \(error.localizedDescription, privacy: .public)")
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
            dappIconURL: proposal.icons.first,
            approvedChains: approval.chains,
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

    func approveMessageRequest(_ request: WalletConnectMessageRequest, signature: String) async throws {
        guard isConfigured else {
            throw configurationError ?? .notConfigured
        }
        let normalized = try WalletConnectEVMSignatureFormatter().normalizedSignature(signature)
        try await pairingClient.respond(topic: request.topic, requestId: request.requestId, result: normalized)
        if pendingMessageRequest?.requestId == request.requestId {
            pendingMessageRequest = nil
        }
    }

    func approveTransactionRequest(_ request: WalletConnectTransactionRequest, transactionHash: String) async throws {
        guard isConfigured else {
            throw configurationError ?? .notConfigured
        }
        guard !transactionHash.isEmpty else {
            throw WalletConnectError.responseFailed("Empty transaction hash")
        }
        try await pairingClient.respond(topic: request.topic, requestId: request.requestId, result: transactionHash)
        if pendingMessageRequest?.requestId == request.requestId {
            pendingMessageRequest = nil
        }
    }

    func rejectMessageRequest(_ request: WalletConnectIncomingRequest) async throws {
        guard isConfigured else {
            throw configurationError ?? .notConfigured
        }
        try await pairingClient.rejectRequest(topic: request.topic, requestId: request.requestId)
        if pendingMessageRequest?.requestId == request.requestId {
            pendingMessageRequest = nil
        }
    }

    func disconnectSession(topic: String) async throws {
        bindingStore.removeBinding(for: topic)
        guard isConfigured else { return }
        try await pairingClient.disconnect(topic: topic)
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
    case responseFailed(String)
    case disconnectionFailed(String)
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
        case .responseFailed(let message):
            return String(
                format: NSLocalizedString("walletConnectErrorResponseFailed", comment: ""),
                message
            )
        case .disconnectionFailed(let message):
            return String(
                format: NSLocalizedString("walletConnectErrorDisconnectionFailed", comment: ""),
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
    private var requestCancellable: AnyCancellable?
    private var authenticateCancellable: AnyCancellable?
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
                let snapshot = event.proposal.walletConnectSnapshot(verifyContext: event.context)
                self?.proposalsByID[snapshot.id] = event.proposal
                handler(snapshot)
            }
    }

    func observeSessionRequests(_ handler: @escaping @MainActor (WalletConnectIncomingRequest) -> Void) {
        requestCancellable = Sign.instance.sessionRequestPublisher
            .receive(on: DispatchQueue.main)
            .sink { event in
                let session = Sign.instance.getSessions().first { $0.topic == event.request.topic }
                handler(event.request.walletConnectIncomingRequest(
                    verifyContext: event.context,
                    session: session
                ))
            }
    }

    func observeAuthenticationRequests(_ handler: @escaping @MainActor (WalletConnectAuthenticationRequest) -> Void) {
        // One-Click Auth / session-authenticate is intentionally not mapped to
        // generic message signing. These requests have different SIWE semantics
        // and must be handled by a dedicated auth flow in a later PR.
        authenticateCancellable = Sign.instance.authenticateRequestPublisher
            .receive(on: DispatchQueue.main)
            .sink { event in
                handler(WalletConnectAuthenticationRequest(requestId: event.request.id.walletConnectRequestID))
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

    func respond(topic: String, requestId: WalletConnectRequestID, result: String) async throws {
        do {
            try await Sign.instance.respond(
                topic: topic,
                requestId: requestId.rpcID,
                response: .response(AnyCodable(result))
            )
        } catch {
            throw WalletConnectError.responseFailed(error.localizedDescription)
        }
    }

    func rejectRequest(topic: String, requestId: WalletConnectRequestID) async throws {
        do {
            try await Sign.instance.respond(
                topic: topic,
                requestId: requestId.rpcID,
                response: .error(JSONRPCError(code: 5000, message: "User rejected request"))
            )
        } catch {
            throw WalletConnectError.rejectionFailed(error.localizedDescription)
        }
    }

    func rejectAuthentication(_ request: WalletConnectAuthenticationRequest) async throws {
        do {
            try await Sign.instance.rejectSession(requestId: request.requestId.rpcID)
        } catch {
            throw WalletConnectError.rejectionFailed(error.localizedDescription)
        }
    }

    func disconnect(topic: String) async throws {
        do {
            try await Sign.instance.disconnect(topic: topic)
        } catch {
            throw WalletConnectError.disconnectionFailed(error.localizedDescription)
        }
    }
}

private extension Session.Proposal {
    func walletConnectSnapshot(verifyContext: VerifyContext?) -> WalletConnectProposal {
        WalletConnectProposal(
            id: String(describing: id),
            name: proposer.name,
            url: proposer.url,
            icons: proposer.icons,
            verifyContext: verifyContext?.walletConnectVerifyContext,
            requiredNamespaces: requiredNamespaces.walletConnectRequests,
            optionalNamespaces: optionalNamespaces?.walletConnectRequests ?? [],
            sessionProperties: sessionProperties
        )
    }
}

private extension RPCID {
    var walletConnectRequestID: WalletConnectRequestID {
        switch self {
        case .left(let string): return .string(string)
        case .right(let integer): return .integer(integer)
        }
    }
}

private extension WalletConnectRequestID {
    var rpcID: RPCID {
        switch self {
        case .string(let string): return RPCID(string)
        case .integer(let integer): return RPCID(integer)
        }
    }
}

private extension Request {
    func walletConnectIncomingRequest(
        verifyContext: VerifyContext?,
        session: Session?
    ) -> WalletConnectIncomingRequest {
        WalletConnectIncomingRequest(
            topic: topic,
            requestId: id.walletConnectRequestID,
            method: method,
            chainId: chainId.absoluteString,
            paramsJSON: params.walletConnectJSONString,
            dappName: session?.peer.name ?? "WalletConnect",
            dappURL: session?.peer.url ?? "",
            dappIcon: session?.peer.icons.first,
            verifyContext: verifyContext?.walletConnectVerifyContext
        )
    }
}

private extension VerifyContext {
    var walletConnectVerifyContext: WalletConnectVerifyContext {
        WalletConnectVerifyContext(
            origin: origin ?? "",
            validation: validation.walletConnectValidation
        )
    }
}

private extension VerifyContext.ValidationStatus {
    var walletConnectValidation: WalletConnectVerifyContext.Validation {
        switch self {
        case .valid: return .valid
        case .invalid: return .invalid
        case .scam: return .scam
        case .unknown: return .unknown
        }
    }
}

private extension AnyCodable {
    var walletConnectJSONString: String {
        guard let data = try? JSONEncoder().encode(self),
              let json = String(data: data, encoding: .utf8) else {
            return "[]"
        }
        return json
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

    func observeSessionRequests(_: @escaping @MainActor (WalletConnectIncomingRequest) -> Void) {}

    func observeAuthenticationRequests(_: @escaping @MainActor (WalletConnectAuthenticationRequest) -> Void) {}

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

    func respond(topic _: String, requestId _: WalletConnectRequestID, result _: String) async throws {
        await Task.yield()
        throw WalletConnectError.configurationFailed("WalletConnectSign or Starscream is not linked.")
    }

    func rejectRequest(topic _: String, requestId _: WalletConnectRequestID) async throws {
        await Task.yield()
        throw WalletConnectError.configurationFailed("WalletConnectSign or Starscream is not linked.")
    }

    func rejectAuthentication(_: WalletConnectAuthenticationRequest) async throws {
        await Task.yield()
        throw WalletConnectError.configurationFailed("WalletConnectSign or Starscream is not linked.")
    }

    func disconnect(topic _: String) async throws {
        await Task.yield()
        throw WalletConnectError.configurationFailed("WalletConnectSign or Starscream is not linked.")
    }
}
#endif
