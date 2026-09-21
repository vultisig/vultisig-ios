//
//  SwapTryAgain.swift
//  VultisigApp
//
//  "Try again" on a failed market swap reopens the swap form with the same
//  from/to pair selected, and nothing else: the amount, route and review are
//  entered afresh, and nothing from the failed swap's quote or keysign payload
//  is reused. Named apart from `SwapRetrySignal`, which re-broadcasts the
//  same signed swap.
//

import Foundation

/// The pair a failed swap is tried again on, as the vault's own coin ids.
struct SwapTryAgainPair: Hashable {
    let fromCoinID: String
    let toCoinID: String

    func route(vaultPubKeyECDSA: String) -> SwapRoute {
        .root(fromCoinID: fromCoinID, toCoinID: toCoinID, vaultPubKeyECDSA: vaultPubKeyECDSA)
    }
}

/// One side of a swap, as a history row or a signed swap names it.
struct SwapTryAgainCoin: Equatable {
    /// `nil` only for the destination of a row recorded before it was stored.
    let chainRawValue: String?
    let ticker: String
    /// Empty for a native coin, and on a row recorded before it was stored.
    let contractAddress: String
    /// Where the swap paid out; consulted only when `chainRawValue` is `nil`.
    let address: String?

    init(chainRawValue: String?, ticker: String, contractAddress: String, address: String?) {
        self.chainRawValue = chainRawValue
        self.ticker = ticker
        self.contractAddress = contractAddress
        self.address = address
    }

    init(coin: Coin) {
        self.init(
            chainRawValue: coin.chain.rawValue,
            ticker: coin.ticker,
            contractAddress: coin.contractAddress,
            address: coin.address
        )
    }
}

enum SwapTryAgain {

    // MARK: - When it is offered

    /// Only a terminal failure — a refunded SwapKit swap already arrives as
    /// `.failed`. A swap still in flight may yet land, and trying it again
    /// would sell the same funds twice; a timeout says nothing about the swap.
    private static func isOffered(for status: TransactionStatus) -> Bool {
        if case .failed = status { return true }
        return false
    }

    /// A failed or refunded market swap. Limit orders are their own row type.
    static func isOffered(for row: TransactionHistoryData) -> Bool {
        row.type == .swap && row.status == .error
    }

    // MARK: - Which pair

    /// Resolves a history row against the vault's current coins.
    static func pair(for row: TransactionHistoryData, in coins: [Coin]) -> SwapTryAgainPair? {
        guard row.type == .swap, let toTicker = row.toCoinTicker else { return nil }
        return pair(
            from: SwapTryAgainCoin(
                chainRawValue: row.chainRawValue,
                ticker: row.coinTicker,
                contractAddress: row.fromContractAddress ?? "",
                address: nil
            ),
            to: SwapTryAgainCoin(
                chainRawValue: row.toChainRawValue,
                ticker: toTicker,
                contractAddress: row.toContractAddress ?? "",
                address: row.toAddress
            ),
            isLimitOrder: false,
            in: coins
        )
    }

    /// What a done screen offers: the pair a just-signed swap can be tried
    /// again on, once `status` says it failed.
    static func pair(
        status: TransactionStatus,
        fromCoin: Coin,
        toCoin: Coin,
        isLimitOrder: Bool,
        in coins: [Coin]
    ) -> SwapTryAgainPair? {
        guard isOffered(for: status) else { return nil }
        return pair(fromCoin: fromCoin, toCoin: toCoin, isLimitOrder: isLimitOrder, in: coins)
    }

    /// Resolves a just-signed swap — the initiator's transaction or the
    /// co-signer's payload — against the signing vault's current coins.
    static func pair(fromCoin: Coin, toCoin: Coin, isLimitOrder: Bool, in coins: [Coin]) -> SwapTryAgainPair? {
        pair(
            from: SwapTryAgainCoin(coin: fromCoin),
            to: SwapTryAgainCoin(coin: toCoin),
            isLimitOrder: isLimitOrder,
            in: coins
        )
    }

    /// `nil` for a limit order, or when either side is missing from the vault
    /// or matches more than one coin — picking one would be guessing which
    /// asset to sell.
    static func pair(
        from: SwapTryAgainCoin,
        to: SwapTryAgainCoin,
        isLimitOrder: Bool,
        in coins: [Coin]
    ) -> SwapTryAgainPair? {
        guard !isLimitOrder,
              let fromCoin = uniqueMatch(for: from, in: coins),
              let toCoin = uniqueMatch(for: to, in: coins) else {
            return nil
        }
        return SwapTryAgainPair(fromCoinID: fromCoin.id, toCoinID: toCoin.id)
    }

    private static func uniqueMatch(for side: SwapTryAgainCoin, in coins: [Coin]) -> Coin? {
        let candidates = coins.filter { matches($0, side) }
        return candidates.count == 1 ? candidates.first : nil
    }

    private static func matches(_ coin: Coin, _ side: SwapTryAgainCoin) -> Bool {
        guard coin.ticker == side.ticker else { return false }
        guard let chainRawValue = side.chainRawValue else {
            // A legacy destination names no chain, so the payout address
            // stands in for it and uniqueness decides.
            guard let address = side.address, !address.isEmpty else { return false }
            return coin.address == address
        }
        guard coin.chain.rawValue == chainRawValue else { return false }
        // Native coins, and legacy rows, carry no contract: chain and ticker
        // alone, with uniqueness deciding.
        guard !side.contractAddress.isEmpty else { return true }
        // An EVM contract may be held checksummed and re-added lowercased;
        // elsewhere case is part of the address.
        if coin.chainType == .EVM {
            return coin.contractAddress.lowercased() == side.contractAddress.lowercased()
        }
        return coin.contractAddress == side.contractAddress
    }
}
