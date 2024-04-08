//
//  FeeService.swift
//  VoltixApp
//
//  Created by Artur Guseinov on 08.04.2024.
//

import Foundation
import BigInt

final class FeeService {

    enum Fee {
        case utxo(BigInt)
        case evm(gasPrice:String, priorityFee:Int64, nonce:Int64)
        case thorchain(String)
        case gaia(String)
        case solana(String)
    }

    static let shared = FeeService()

    private let utxo = BlockchairService.shared
    private let sol = SolanaService.shared

    func fetchFee(for coin: Coin) async throws -> Fee {
        switch coin.chain {
        case .bitcoin, .bitcoinCash, .litecoin, .dogecoin:
            let sats = try await utxo.fetchSatsPrice(coin: coin)
            return .utxo(sats)

        case .thorChain:
            return .thorchain("0.02")
        case .solana:
            let (_, feeInLamports) = try await sol.fetchRecentBlockhash()
            return .solana(feeInLamports)

        case .ethereum, .avalanche, .bscChain:
            let service = try EvmServiceFactory.getService(forChain: coin)
            let (gasPrice, priorityFee, nonce) = try await service.getGasInfo(fromAddress: coin.address)
            return .evm(gasPrice: gasPrice, priorityFee: priorityFee, nonce: nonce)

        case .gaiaChain:
            return .gaia("0.0075")
        }
    }
}
