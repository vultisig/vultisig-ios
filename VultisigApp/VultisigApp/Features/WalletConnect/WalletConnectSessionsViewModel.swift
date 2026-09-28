//
//  WalletConnectSessionsViewModel.swift
//  VultisigApp
//

import Foundation

@MainActor
final class WalletConnectSessionsViewModel: ObservableObject {
    typealias DisconnectSession = (String) async throws -> Void

    @Published private(set) var bindings: [WalletConnectSessionBinding] = []
    @Published private(set) var removingTopic: String?
    @Published var errorMessage: String?

    private let bindingStore: WalletConnectSessionBindingStoring
    private let disconnectSession: DisconnectSession

    init(
        bindingStore: WalletConnectSessionBindingStoring = WalletConnectSessionBindingStore.shared,
        disconnectSession: @escaping DisconnectSession = { topic in
            try await WalletConnectCoordinator.shared.disconnectSession(topic: topic)
        }
    ) {
        self.bindingStore = bindingStore
        self.disconnectSession = disconnectSession
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
}
