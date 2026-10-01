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
        bindings = dedupeByDApp(
            bindingStore.allBindings().sorted { lhs, rhs in
                if lhs.createdAt == rhs.createdAt {
                    return lhs.topic < rhs.topic
                }
                return lhs.createdAt > rhs.createdAt
            }
        )
    }

    private func dedupeByDApp(_ bindings: [WalletConnectSessionBinding]) -> [WalletConnectSessionBinding] {
        var seenKeys = Set<String>()
        var uniqueBindings: [WalletConnectSessionBinding] = []
        for binding in bindings {
            let key = normalizedDAppKey(for: binding)
            guard !seenKeys.contains(key) else { continue }
            seenKeys.insert(key)
            uniqueBindings.append(binding)
        }
        return uniqueBindings
    }

    private func normalizedDAppKey(for binding: WalletConnectSessionBinding) -> String {
        if let host = URL(string: binding.dappURL)?.host?.lowercased(), !host.isEmpty {
            return host
        }
        if !binding.dappURL.isEmpty {
            return binding.dappURL.lowercased()
        }
        return binding.dappName.lowercased()
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
