//
//  WalletConnectSessionsViewModel.swift
//  VultisigApp
//

import Foundation

@MainActor
final class WalletConnectSessionsViewModel: ObservableObject {
    typealias DisconnectSession = (String) async throws -> Void
    typealias PairURI = (String) async throws -> Void

    @Published private(set) var bindings: [WalletConnectSessionBinding] = []
    @Published private(set) var removingTopic: String?
    @Published private(set) var isPairingDebugURI = false
    @Published var errorMessage: String?

    private let bindingStore: WalletConnectSessionBindingStoring
    private let disconnectSession: DisconnectSession
    private let pairURI: PairURI

    init(
        bindingStore: WalletConnectSessionBindingStoring = WalletConnectSessionBindingStore.shared,
        disconnectSession: @escaping DisconnectSession = { topic in
            try await WalletConnectCoordinator.shared.disconnectSession(topic: topic)
        },
        pairURI: @escaping PairURI = { uri in
            try await WalletConnectCoordinator.shared.pair(uri: uri)
        }
    ) {
        self.bindingStore = bindingStore
        self.disconnectSession = disconnectSession
        self.pairURI = pairURI
        load()
    }

    func load() {
        bindings = bindingStore.allBindings().sorted { lhs, rhs in
            if lhs.createdAt == rhs.createdAt {
                return lhs.topic < rhs.topic
            }
            return lhs.createdAt > rhs.createdAt
        }
    }

    func remove(_ binding: WalletConnectSessionBinding) async {
        removingTopic = binding.topic
        defer { removingTopic = nil }

        do {
            try await disconnectSession(binding.topic)
            load()
        } catch {
            bindingStore.removeBinding(for: binding.topic)
            load()
            errorMessage = error.localizedDescription
        }
    }

#if DEBUG
    func pairDebugURI(_ uri: String) async {
        let trimmedURI = uri.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedURI.isEmpty else { return }

        isPairingDebugURI = true
        defer { isPairingDebugURI = false }

        do {
            try await pairURI(trimmedURI)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
#endif
}
