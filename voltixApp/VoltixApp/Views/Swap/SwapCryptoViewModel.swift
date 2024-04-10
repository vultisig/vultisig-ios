//
//  SwapCryptoViewModel.swift
//  VoltixApp
//
//  Created by Artur Guseinov on 02.04.2024.
//

import SwiftUI
import BigInt
import WalletCore

@MainActor
class SwapCryptoViewModel: ObservableObject, TransferViewModel {

    private let titles = ["send", "verify", "pair", "keysign", "done"]

    @Published var coins: [Coin] = []
    @Published var currentIndex = 1
    @Published var currentTitle = "send"
    @Published var hash: String?

    func load(tx: SwapTransaction, fromCoin: Coin, coins: [Coin]) {
        self.coins = coins.filter { $0.chain.isSwapSupported }
        tx.fromCoin = fromCoin
        tx.toCoin = coins.first!
    }

    // MARK: Progress

    var progress: Double {
        return Double(currentIndex) / Double(titles.count)
    }

    func validateForm(tx: SwapTransaction) -> Bool {
        return tx.fromCoin != tx.toCoin
            && tx.fromCoin != .example
            && tx.toCoin != .example
            && !tx.fromAmount.isEmpty
            && !tx.toAmount.isEmpty
            && tx.quote != nil
    }

    func setHash(_ hash: String) {
        self.hash = hash
    }

    func moveToNextView() {
        currentIndex += 1
        currentTitle = titles[currentIndex-1]
    }

    func buildKeysignPayload(tx: SwapTransaction) -> KeysignPayload {
        let swapPayload = THORChainSwapPayload(
            fromAddress: tx.fromCoin.address,
            fromAsset: swapAsset(for: tx.fromCoin),
            toAsset: swapAsset(for: tx.toCoin),
            toAddress: tx.toCoin.address,
            vaultAddress: tx.quote!.inboundAddress,
            routerAddress: nil,
            fromAmount: tx.fromAmount,
            toAmountLimit: .zero
        )
        return KeysignPayloadFactory().buildSwap(coin: tx.fromCoin, swapPayload: swapPayload)
    }
}

private extension SwapCryptoViewModel {

    func swapAsset(for coin: Coin) -> THORChainSwapAsset {
        return THORChainSwapAsset.with {
            switch coin.chain {
            case .thorChain:
                $0.chain = .thor
            case .ethereum:
                $0.chain = .eth
            case .avalanche:
                $0.chain = .avax
            case .bscChain:
                $0.chain = .bsc
            case .bitcoin:
                $0.chain = .btc
            case .bitcoinCash:
                $0.chain = .bch
            case .litecoin:
                $0.chain = .ltc
            case .dogecoin:
                $0.chain = .doge
            case .gaiaChain:
                $0.chain = .atom
            case .solana: break
            }
            $0.symbol = coin.ticker
            if !coin.isNativeToken {
                $0.tokenID = coin.contractAddress
            }
        }
    }
}
