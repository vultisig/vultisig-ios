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

    /// Sum of the out coins to `recipient` in exactly `asset` (the canonical
    /// spelling with the full contract, e.g. "BTC.BTC", "ETH.USDC-0XA0B8…", or a
    /// secured denom), across the swap actions whose inbound is `inboundHash`.
    /// Midgard amounts are integers scaled by `divisor` (1e8 on THORChain).
    /// Nil when the page may be truncated (`count` above what it lists), when
    /// any matching action is not a settled success, on a refund or failure,
    /// or when nothing pays the recipient in that asset.
    static func fromMidgard(
        actions: [MidgardAction],
        count: String,
        inboundHash: String,
        recipient: String,
        asset: String,
        divisor: Decimal
    ) -> Decimal? {
        guard let total = Int(count), total <= actions.count else { return nil }
        let hash = normalized(inboundHash)
        let matching = actions.filter { action in
            action.in.contains { normalized($0.txID) == hash }
        }
        guard matching.contains(where: { $0.type.lowercased() == "swap" }),
              !matching.contains(where: { ["refund", "failed"].contains($0.type.lowercased()) }),
              matching.allSatisfy({ $0.status.lowercased() == "success" }),
              !recipient.isEmpty, !asset.isEmpty, divisor > 0 else { return nil }

        let coins = matching
            .filter { $0.type.lowercased() == "swap" }
            .flatMap(\.out)
            .filter { ($0.address ?? "").caseInsensitiveCompare(recipient) == .orderedSame }
            .flatMap { $0.coins ?? [] }
        let paid = coins.filter { $0.asset.caseInsensitiveCompare(asset) == .orderedSame }
        guard !paid.isEmpty else { return nil }
        let sum = paid.reduce(Decimal(0)) { partial, coin in
            partial + (Decimal(string: coin.amount, locale: Locale(identifier: "en_US_POSIX")) ?? 0)
        }
        return sum > 0 ? sum / divisor : nil
    }

    // MARK: - EVM receipt

    struct Log: Equatable {
        let address: String
        let topics: [String]
        let data: String
    }

    /// keccak256("Transfer(address,address,uint256)")
    static let transferTopic = "0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef"

    /// The recipient's net `token` movement in the receipt, in token units:
    /// Transfers in minus Transfers out (a fee-on-transfer token that credits
    /// and then debits in one receipt is not overstated; self-transfers cancel).
    static func fromReceiptLogs(_ logs: [Log], token: String, recipient: String, decimals: Int) -> Decimal? {
        guard !token.isEmpty, let recipientWord = topicWord(recipient) else { return nil }
        let transfers = logs
            .filter { $0.address.caseInsensitiveCompare(token) == .orderedSame }
            .filter { $0.topics.count == 3 && $0.topics[0].lowercased() == transferTopic }
        let amount: (Log) -> BigInt = { BigInt($0.data.stripHexPrefix(), radix: 16) ?? 0 }
        let incoming = transfers.filter { $0.topics[2].lowercased() == recipientWord }.map(amount).reduce(BigInt(0), +)
        let outgoing = transfers.filter { $0.topics[1].lowercased() == recipientWord }.map(amount).reduce(BigInt(0), +)
        let raw = incoming - outgoing
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

/// When to read a supported route's delivered amount after completion, in
/// seconds from the first try: about two minutes in all, then give up and say
/// the route did not report it.
enum SwapDeliveredRetry {
    static let delays: [Double] = [0, 5, 15, 30, 60]
}
