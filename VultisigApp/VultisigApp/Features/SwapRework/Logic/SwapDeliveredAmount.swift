//
//  SwapDeliveredAmount.swift
//  VultisigApp
//
//  What actually reached the vault, read from the chain once a swap is done,
//  so the success screen can put it next to the quote. Only sources that state
//  it are used:
//
//  - THORChain / Maya: the Midgard action's `out` coins paid to the vault's
//    destination address in the destination asset.
//  - Same-chain EVM aggregators (1inch, KyberSwap, LI.FI) into an ERC-20: the
//    token's `Transfer` logs to the vault in the swap receipt.
//
//  Anything else (native EVM output, which moves as an internal call with no
//  log; SwapKit; cross-chain aggregator legs; Solana) returns nil, and the
//  screen shows "Received" without a delivered row or a difference.
//

import BigInt
import Foundation

enum SwapDeliveredAmount {

    // MARK: - Midgard

    /// Sum of the out coins to `recipient` in `assetPrefix` (e.g. "BTC.BTC",
    /// "ETH.USDC"), across the actions whose inbound is `inboundHash`. Midgard
    /// amounts are integers scaled by `divisor` (1e8 on THORChain). Nil when no
    /// swap action pays the recipient, or when a refund is among the actions.
    static func fromMidgard(
        actions: [MidgardAction],
        inboundHash: String,
        recipient: String,
        assetPrefix: String?,
        divisor: Decimal
    ) -> Decimal? {
        let hash = normalized(inboundHash)
        let matching = actions.filter { action in
            action.in.contains { normalized($0.txID) == hash }
        }
        guard matching.contains(where: { $0.type.lowercased() == "swap" }),
              !matching.contains(where: { ["refund", "failed"].contains($0.type.lowercased()) }),
              divisor > 0 else { return nil }

        let coins = matching
            .filter { $0.type.lowercased() == "swap" }
            .flatMap(\.out)
            .filter { ($0.address ?? "").caseInsensitiveCompare(recipient) == .orderedSame }
            .flatMap { $0.coins ?? [] }
        let paid: [MidgardCoin]
        if let assetPrefix {
            paid = coins.filter { matches(asset: $0.asset, prefix: assetPrefix) }
        } else {
            // No asset spelling for this chain: trust the address only when
            // everything paid to it is a single asset.
            paid = Set(coins.map { $0.asset.uppercased() }).count == 1 ? coins : []
        }
        guard !paid.isEmpty else { return nil }
        let total = paid.reduce(Decimal(0)) { sum, coin in
            sum + (Decimal(string: coin.amount, locale: Locale(identifier: "en_US_POSIX")) ?? 0)
        }
        return total > 0 ? total / divisor : nil
    }

    /// "ETH.USDC-0XA0B8..." matches "ETH.USDC"; "ETH.USDT-..." does not.
    static func matches(asset: String, prefix: String) -> Bool {
        let asset = asset.uppercased()
        let prefix = prefix.uppercased()
        return asset == prefix || asset.hasPrefix(prefix + "-")
    }

    // MARK: - EVM receipt

    struct Log: Equatable {
        let address: String
        let topics: [String]
        let data: String
    }

    /// keccak256("Transfer(address,address,uint256)")
    static let transferTopic = "0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef"

    /// Sum of `token` Transfer logs whose `to` is `recipient`, in token units.
    static func fromReceiptLogs(_ logs: [Log], token: String, recipient: String, decimals: Int) -> Decimal? {
        guard !token.isEmpty, let recipientWord = topicWord(recipient) else { return nil }
        let raw = logs
            .filter { $0.address.caseInsensitiveCompare(token) == .orderedSame }
            .filter { $0.topics.count == 3 && $0.topics[0].lowercased() == transferTopic }
            .filter { $0.topics[2].lowercased() == recipientWord }
            .compactMap { BigInt($0.data.stripHexPrefix(), radix: 16) }
            .reduce(BigInt(0), +)
        guard raw > 0 else { return nil }
        return (Decimal(string: raw.description) ?? 0) / pow(10, max(decimals, 0))
    }

    static func logs(fromReceipt receipt: [String: Any]) -> [Log] {
        (receipt["logs"] as? [[String: Any]] ?? []).compactMap { entry in
            guard let address = entry["address"] as? String,
                  let topics = entry["topics"] as? [String],
                  let data = entry["data"] as? String else { return nil }
            return Log(address: address, topics: topics, data: data)
        }
    }

    /// An address left-padded to a 32-byte topic word, lowercased.
    static func topicWord(_ address: String) -> String? {
        let hex = address.stripHexPrefix().lowercased()
        guard hex.count == 40 else { return nil }
        return "0x" + String(repeating: "0", count: 24) + hex
    }

    private static func normalized(_ hash: String) -> String {
        hash.stripHexPrefix().uppercased()
    }
}
