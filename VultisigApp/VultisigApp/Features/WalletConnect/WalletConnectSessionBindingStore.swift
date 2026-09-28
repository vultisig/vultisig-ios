//
//  WalletConnectSessionBindingStore.swift
//  VultisigApp
//

import Foundation

struct WalletConnectSessionBinding: Codable, Equatable, Identifiable {
    var id: String { topic }

    let topic: String
    let vaultPubKeyECDSA: String
    let dappName: String
    let dappURL: String
    let createdAt: Date
}

protocol WalletConnectSessionBindingStoring {
    func binding(for topic: String) -> WalletConnectSessionBinding?
    func save(_ binding: WalletConnectSessionBinding)
    func allBindings() -> [WalletConnectSessionBinding]
}

final class WalletConnectSessionBindingStore: WalletConnectSessionBindingStoring {
    static let shared = WalletConnectSessionBindingStore()

    private let userDefaults: UserDefaults
    private let key: String

    init(
        userDefaults: UserDefaults = .standard,
        key: String = "walletConnect.sessionBindings.v1"
    ) {
        self.userDefaults = userDefaults
        self.key = key
    }

    func binding(for topic: String) -> WalletConnectSessionBinding? {
        allBindings().first { $0.topic == topic }
    }

    func save(_ binding: WalletConnectSessionBinding) {
        var bindings = allBindings().filter { $0.topic != binding.topic }
        bindings.append(binding)
        guard let data = try? JSONEncoder().encode(bindings) else { return }
        userDefaults.set(data, forKey: key)
    }

    func allBindings() -> [WalletConnectSessionBinding] {
        guard let data = userDefaults.data(forKey: key),
              let bindings = try? JSONDecoder().decode([WalletConnectSessionBinding].self, from: data) else {
            return []
        }
        return bindings
    }
}
