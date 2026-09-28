//
//  WalletConnectNamespaceBuilder.swift
//  VultisigApp
//

import Foundation

struct WalletConnectNamespaceRequest: Equatable {
    let namespace: String
    let chains: [String]
    let methods: [String]
    let events: [String]
}

struct WalletConnectProposal: Identifiable, Equatable {
    let id: String
    let name: String
    let url: String
    let icons: [String]
    let verificationStatus: String?
    let requiredNamespaces: [WalletConnectNamespaceRequest]
    let optionalNamespaces: [WalletConnectNamespaceRequest]
    let sessionProperties: [String: String]?

    var displayHost: String {
        guard let host = URLComponents(string: url)?.host, !host.isEmpty else {
            return url
        }
        return host
    }
}

struct WalletConnectEVMAccount: Equatable {
    let chainReference: String
    let address: String

    var caip10Account: String {
        "\(chainReference):\(address)"
    }
}

struct WalletConnectEVMNamespaceApproval: Equatable {
    let chains: [String]
    let methods: [String]
    let events: [String]
    let accounts: [String]
}

enum WalletConnectNamespaceApprovalError: LocalizedError, Equatable {
    case unsupportedRequiredNamespace(String)
    case unsupportedRequiredChain(String)
    case unsupportedRequiredMethod(String)
    case unsupportedRequiredEvent(String)
    case missingRequiredChain(String)
    case noEVMAccounts

    var errorDescription: String? {
        switch self {
        case .unsupportedRequiredNamespace(let namespace):
            return String(
                format: NSLocalizedString("walletConnectErrorUnsupportedRequiredNamespace", comment: ""),
                namespace
            )
        case .unsupportedRequiredChain(let chain):
            return String(
                format: NSLocalizedString("walletConnectErrorUnsupportedRequiredChain", comment: ""),
                chain
            )
        case .unsupportedRequiredMethod(let method):
            return String(
                format: NSLocalizedString("walletConnectErrorUnsupportedRequiredMethod", comment: ""),
                method
            )
        case .unsupportedRequiredEvent(let event):
            return String(
                format: NSLocalizedString("walletConnectErrorUnsupportedRequiredEvent", comment: ""),
                event
            )
        case .missingRequiredChain(let chain):
            return String(
                format: NSLocalizedString("walletConnectErrorMissingRequiredChain", comment: ""),
                chain
            )
        case .noEVMAccounts:
            return NSLocalizedString("walletConnectErrorNoEVMAccounts", comment: "")
        }
    }
}

protocol WalletConnectChainNamespaceAdapter {
    func buildApproval(
        requiredNamespaces: [WalletConnectNamespaceRequest],
        optionalNamespaces: [WalletConnectNamespaceRequest],
        accounts: [WalletConnectEVMAccount]
    ) throws -> WalletConnectEVMNamespaceApproval
}

struct WalletConnectEVMNamespaceAdapter: WalletConnectChainNamespaceAdapter {
    static let namespace = "eip155"
    static let supportedMethods = [
        "eth_sendTransaction",
        "personal_sign",
        "eth_signTypedData_v4"
    ]
    static let supportedEvents = [
        "accountsChanged",
        "chainChanged"
    ]

    func buildApproval(
        requiredNamespaces: [WalletConnectNamespaceRequest],
        optionalNamespaces: [WalletConnectNamespaceRequest],
        accounts: [WalletConnectEVMAccount]
    ) throws -> WalletConnectEVMNamespaceApproval {
        let requiredEVM = try validateRequiredNamespaces(requiredNamespaces)
        let optionalEVM = optionalNamespaces.compactMap(normalizedEVMRequest)
        let accountsByChain = Dictionary(grouping: accounts, by: \WalletConnectEVMAccount.chainReference)

        guard !accounts.isEmpty else {
            throw WalletConnectNamespaceApprovalError.noEVMAccounts
        }

        let availableChains = orderedUnique(accounts.map(\.chainReference))
        let requiredChains = orderedUnique(requiredEVM.flatMap { chains(for: $0, fallbackChains: availableChains) })
        for chain in requiredChains where accountsByChain[chain] == nil {
            throw WalletConnectNamespaceApprovalError.missingRequiredChain(chain)
        }

        let optionalChains = optionalEVM
            .flatMap { chains(for: $0, fallbackChains: availableChains) }
            .filter { accountsByChain[$0] != nil }
        let approvedChains = orderedUnique(requiredChains + optionalChains)
        let requestedMethods = orderedUnique((requiredEVM + optionalEVM).flatMap(\.methods))
        let requestedEvents = orderedUnique((requiredEVM + optionalEVM).flatMap(\.events))
        let approvedMethods = requestedMethods.filter(Self.supportedMethods.contains)
        let approvedEvents = requestedEvents.filter(Self.supportedEvents.contains)
        let approvedAccounts = approvedChains.flatMap { chain in
            (accountsByChain[chain] ?? []).map(\.caip10Account)
        }

        return WalletConnectEVMNamespaceApproval(
            chains: approvedChains,
            methods: approvedMethods,
            events: approvedEvents,
            accounts: approvedAccounts
        )
    }

    private func validateRequiredNamespaces(
        _ namespaces: [WalletConnectNamespaceRequest]
    ) throws -> [WalletConnectNamespaceRequest] {
        try namespaces.map { request in
            guard let normalized = normalizedEVMRequest(request) else {
                throw WalletConnectNamespaceApprovalError.unsupportedRequiredNamespace(request.namespace)
            }
            for chain in normalized.chains where !chain.hasPrefix("\(Self.namespace):") {
                throw WalletConnectNamespaceApprovalError.unsupportedRequiredChain(chain)
            }
            for method in normalized.methods where !Self.supportedMethods.contains(method) {
                throw WalletConnectNamespaceApprovalError.unsupportedRequiredMethod(method)
            }
            for event in normalized.events where !Self.supportedEvents.contains(event) {
                throw WalletConnectNamespaceApprovalError.unsupportedRequiredEvent(event)
            }
            return normalized
        }
    }

    private func normalizedEVMRequest(_ request: WalletConnectNamespaceRequest) -> WalletConnectNamespaceRequest? {
        if request.namespace == Self.namespace {
            return request
        }

        guard request.namespace.hasPrefix("\(Self.namespace):") else {
            return nil
        }

        return WalletConnectNamespaceRequest(
            namespace: Self.namespace,
            chains: request.chains.isEmpty ? [request.namespace] : request.chains,
            methods: request.methods,
            events: request.events
        )
    }

    private func chains(
        for request: WalletConnectNamespaceRequest,
        fallbackChains: [String]
    ) -> [String] {
        request.chains.isEmpty ? fallbackChains : request.chains
    }

    private func orderedUnique(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.filter { seen.insert($0).inserted }
    }
}

extension Vault {
    var walletConnectEVMAccounts: [WalletConnectEVMAccount] {
        var seen = Set<String>()
        return coins.compactMap { coin in
            guard coin.chain.chainType == .EVM,
                  let chainID = coin.chain.chainID,
                  !coin.address.isEmpty else {
                return nil
            }

            let chainReference = "eip155:\(chainID)"
            let key = "\(chainReference):\(coin.address.lowercased())"
            guard seen.insert(key).inserted else { return nil }

            return WalletConnectEVMAccount(chainReference: chainReference, address: coin.address)
        }
    }
}
