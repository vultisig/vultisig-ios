//
//  AddressService.swift
//  VultisigApp
//
//  Created by Enrique Souza Soares on 06/08/24.
//

import Foundation
import SwiftUI
import WalletCore

struct AddressService {

    /// Detects which chain an address belongs to by validating against all WalletCore CoinTypes
    /// Returns the detected chain if found and it exists in the vault, or nil otherwise
    static func detectChain(from address: String, vault: Vault, currentChain: Chain) -> Chain? {
        // First check if address is valid for current chain
        if validateAddress(address: address, chain: currentChain) {
            return nil // Already on correct chain
        }

        // Special handling for MayaChain
        if AnyAddress.isValidBech32(string: address, coin: .thorchain, hrp: "maya") {
            return vault.coins.contains(where: { $0.chain == .mayaChain && $0.isNativeToken }) ? .mayaChain : nil
        }

        // Special handling for ThorChain Stagenet
        if AnyAddress.isValidBech32(string: address, coin: .thorchain, hrp: "cthor") {
            return vault.coins.contains(where: { $0.chain == .thorChainStagenet && $0.isNativeToken }) ? .thorChainStagenet : nil
        }

        // Special handling for ThorChain Stagenet-2
        if AnyAddress.isValidBech32(string: address, coin: .thorchain, hrp: "sthor") {
            return vault.coins.contains(where: { $0.chain == .thorChainStagenet2 && $0.isNativeToken }) ? .thorChainStagenet2 : nil
        }

        // Check if it's an EVM address - don't auto-switch for safety
        if isEVMAddress(address) {
            // Don't auto-switch between EVM chains for safety
            return nil
        }

        // Iterate through all WalletCore CoinTypes to find matching address
        for coinType in CoinType.allCases {
            if coinType.validate(address: address) {
                // Map CoinType to Vultisig Chain
                if let chain = Chain.allCases.first(where: { $0.coinType == coinType }) {
                    // Only return if chain exists in vault with native token
                    return vault.coins.contains(where: { $0.chain == chain && $0.isNativeToken }) ? chain : nil
                }
            }
        }

        return nil
    }

    /// Checks if an address is an EVM address (0x followed by 40 hex characters)
    private static func isEVMAddress(_ address: String) -> Bool {
        let pattern = "^0x[a-fA-F0-9]{40}$"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return false }
        let range = NSRange(address.startIndex..., in: address)
        return regex.firstMatch(in: address, range: range) != nil
    }

    static func resolveInput(_ input: String, chain: Chain) async throws -> String {
        if chain == .mayaChain {
            let isValid = AnyAddress.isValidBech32(string: input, coin: .thorchain, hrp: "maya")

            if isValid {
                return input
            } else {
                throw Errors.invalidAddress
            }
        }

        if chain == .thorChainStagenet {
            let isValid = AnyAddress.isValidBech32(string: input, coin: .thorchain, hrp: "cthor")

            if isValid {
                return input
            } else {
                // Try TNS resolution for stagenet
                let service = ThorchainServiceFactory.getService(for: .thorChainStagenet)
                return try await service.resolveTNS(name: input, chain: chain)
            }
        }

        if chain == .thorChainStagenet2 {
            let isValid = AnyAddress.isValidBech32(string: input, coin: .thorchain, hrp: "sthor")

            if isValid {
                return input
            } else {
                let service = ThorchainServiceFactory.getService(for: .thorChainStagenet2)
                return try await service.resolveTNS(name: input, chain: chain)
            }
        }

        let isValid = chain.coinType.validate(address: input)

        if isValid {
            return input

        } else if input.isENSNameService() {
            return try await AddressService.resolveENSDomaninAddress(input: input, chain: chain)

        } else if chain == .thorChain {
            let service = ThorchainServiceFactory.getService(for: .thorChain)
            return try await service.resolveTNS(name: input, chain: chain)

        } else {
            throw Errors.invalidAddress
        }
    }

    static func validateAddress(address: String, chain: Chain) -> Bool {
        if chain == .mayaChain {
            return AnyAddress.isValidBech32(string: address, coin: .thorchain, hrp: "maya")
        }

        if chain == .thorChainStagenet {
            return AnyAddress.isValidBech32(string: address, coin: .thorchain, hrp: "cthor")
        }

        if chain == .thorChainStagenet2 {
            return AnyAddress.isValidBech32(string: address, coin: .thorchain, hrp: "sthor")
        }

        return chain.coinType.validate(address: address)
    }

    static func validateAddress(address: String, group: GroupedChain) -> Bool {
        let firstCoinOptional = group.coins.first
        if let firstCoin = firstCoinOptional {
            if firstCoin.chain == .mayaChain {
                return AnyAddress.isValidBech32(string: address, coin: .thorchain, hrp: "maya")
            }
            if firstCoin.chain == .thorChainStagenet {
                return AnyAddress.isValidBech32(string: address, coin: .thorchain, hrp: "cthor")
            }
            if firstCoin.chain == .thorChainStagenet2 {
                return AnyAddress.isValidBech32(string: address, coin: .thorchain, hrp: "sthor")
            }
            return firstCoin.coinType.validate(address: address)
        }

        return false
    }
}

private extension AddressService {

    enum Errors: Error {
        case invalidAddress
    }

    static func resolveENSDomaninAddress(input: String, chain: Chain) async throws -> String {
        let ensName = input
        let factory = try EvmService.getService(forChain: chain)
        let address = try await factory.resolveENS(ensName: ensName)
        return address
    }
}
