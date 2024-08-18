//
//  AddressService.swift
//  VultisigApp
//
//  Created by Enrique Souza Soares on 06/08/24.
//

import Foundation
import SwiftUI
import WalletCore

public struct AddressService {

    static func resolveInput(_ input: String, chain: Chain) async throws -> String {
        if chain == .mayaChain {
            let isValid = AnyAddress.isValidBech32(string: input, coin: .thorchain, hrp: "maya")

            if isValid {
                return input
            } else {
                throw Errors.invalidAddress
            }
        }

        let isValid = chain.coinType.validate(address: input)

        if isValid {
            return input

        } else if input.isENSNameService() {
            return try await AddressService.resolveENSDomaninAddress(input: input, chain: chain)

        } else if chain == .thorChain {
            return try await ThorchainService.shared.resolveTNS(name: input, chain: chain)

        } else {
            throw Errors.invalidAddress
        }
    }

    static func validateAddress(address: String, chain: Chain) -> Bool {
        if chain == .mayaChain {
            return AnyAddress.isValidBech32(string: address, coin: .thorchain, hrp: "maya")
        }

        return chain.coinType.validate(address: address)
    }

    static func validateAddress(coin: CoinMeta, address: String) -> Bool {
        if coin.chain == .mayaChain {
            return AnyAddress.isValidBech32(string: address, coin: .thorchain, hrp: "maya")
        }

        return coin.coinType.validate(address: address)
    }

    static func validateAddress(address: String, group: GroupedChain) -> Bool {
        let firstCoinOptional = group.coins.first
        if let firstCoin = firstCoinOptional {
            if firstCoin.chain == .mayaChain {
                return AnyAddress.isValidBech32(string: address, coin: .thorchain, hrp: "maya")
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
        let namehash = ensName.namehash()
        let factory = try EvmServiceFactory.getService(forChain: chain)
        let address = try await factory.resolveENS(ensName: ensName)
        return address
    }
}
