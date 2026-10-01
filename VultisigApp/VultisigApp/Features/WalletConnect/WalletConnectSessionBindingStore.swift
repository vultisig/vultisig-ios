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
    let dappIconURL: String?
    let approvedChains: [String]
    let createdAt: Date

    init(
        topic: String,
        vaultPubKeyECDSA: String,
        dappName: String,
        dappURL: String,
        dappIconURL: String? = nil,
        approvedChains: [String] = [],
        createdAt: Date
    ) {
        self.topic = topic
        self.vaultPubKeyECDSA = vaultPubKeyECDSA
        self.dappName = dappName
        self.dappURL = dappURL
        self.dappIconURL = dappIconURL
        self.approvedChains = approvedChains
        self.createdAt = createdAt
    }

    enum CodingKeys: String, CodingKey {
        case topic
        case vaultPubKeyECDSA
        case dappName
        case dappURL
        case dappIconURL
        case approvedChains
        case createdAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        topic = try container.decode(String.self, forKey: .topic)
        vaultPubKeyECDSA = try container.decode(String.self, forKey: .vaultPubKeyECDSA)
        dappName = try container.decode(String.self, forKey: .dappName)
        dappURL = try container.decode(String.self, forKey: .dappURL)
        dappIconURL = try container.decodeIfPresent(String.self, forKey: .dappIconURL)
        approvedChains = try container.decodeIfPresent([String].self, forKey: .approvedChains) ?? []
        createdAt = try container.decode(Date.self, forKey: .createdAt)
    }
}

extension Notification.Name {
    static let walletConnectSessionBindingsDidChange = Notification.Name("walletConnectSessionBindingsDidChange")
}

protocol WalletConnectSessionBindingStoring {
    func binding(for topic: String) -> WalletConnectSessionBinding?
    func save(_ binding: WalletConnectSessionBinding)
    func removeBinding(for topic: String)
    func allBindings() -> [WalletConnectSessionBinding]
}

final class WalletConnectSessionBindingStore: WalletConnectSessionBindingStoring {
    static let shared = WalletConnectSessionBindingStore()

    private let userDefaults: UserDefaults
    private let key: String

    static func activeDAppCount(bindingStore: WalletConnectSessionBindingStoring = WalletConnectSessionBindingStore()) -> Int {
        Set(bindingStore.allBindings().map(normalizedDAppKey(for:))).count
    }

    private static func normalizedDAppKey(for binding: WalletConnectSessionBinding) -> String {
        if let host = URL(string: binding.dappURL)?.host?.lowercased(), !host.isEmpty {
            return host
        }
        if !binding.dappURL.isEmpty {
            return binding.dappURL.lowercased()
        }
        return binding.dappName.lowercased()
    }

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
        let bindings = allBindings().filter { $0.topic != binding.topic } + [binding]
        save(bindings)
    }

    func removeBinding(for topic: String) {
        save(allBindings().filter { $0.topic != topic })
    }

    func allBindings() -> [WalletConnectSessionBinding] {
        guard let data = userDefaults.data(forKey: key),
              let bindings = try? JSONDecoder().decode([WalletConnectSessionBinding].self, from: data) else {
            return []
        }
        return bindings
    }

    private func save(_ bindings: [WalletConnectSessionBinding]) {
        guard let data = try? JSONEncoder().encode(bindings) else { return }
        userDefaults.set(data, forKey: key)
        NotificationCenter.default.post(name: .walletConnectSessionBindingsDidChange, object: self)
    }
}
