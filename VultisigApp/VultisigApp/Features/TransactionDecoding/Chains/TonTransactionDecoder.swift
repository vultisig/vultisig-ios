//
//  TonTransactionDecoder.swift
//  VultisigApp
//
//  Decodes exact TON nominator-pool comments from signed transaction content.
//

import BigInt
import Foundation
import WalletCore

struct TonTransactionDecoder: TransactionContentDecoder {

    /// Chain-scoped so bare pool comments cannot collide with other grammars.
    let handles: Set<Chain>? = [.ton]

    /// Earlier approve or swap routes make the comment inert.
    private static let precedence: MemoPrecedence = .memoIsInertWhenRoutedEarlier

    func decode(_ tx: SignedTransactionContent) -> DecodedTransaction? {
        // TonConnect BOCs and earlier routes make the outer memo a sidecar.
        guard let content = tx.corroborated else { return nil }

        // Pool protocol tokens are exact and must not be trimmed.
        guard let comment = content.memo(Self.precedence), !comment.isEmpty else { return nil }

        if TonStakingComment.depositComments.contains(comment) {
            // Deposit amount is the TON moved into the pool.
            return DecodedTransaction(
                operation: .stake,
                amount: Self.deposited(content.amount),
                counterparty: .pool(content.toAddress),
                evidence: .memo
            )
        }

        if TonStakingComment.withdrawComments.contains(comment) {
            // The transfer carries only a request fee; settlement returns later.
            return DecodedTransaction(
                operation: .unstake,
                amount: .unstated,
                counterparty: .pool(content.toAddress),
                evidence: .memo
            )
        }

        return nil
    }
    /// Positive committed deposits move chain-native TON.
    private static func deposited(_ signed: SignedAmount) -> DecodedAmount {
        switch signed {
        case .committed(let raw) where raw > 0:
            return .units(raw, of: .chainNative)
        case .committed, .computedAtSigning:
            return .unstated
        }
    }

}

/// Reads the whole position named by a signed TON pool withdrawal request.
struct TonStakedPositionReader: PositionReading {
    var readPools: (String) async throws -> [TonAccountStakingInfo] = {
        try await TonService.shared.getNominatorPools(address: $0)
    }

    func handles(_ decoded: DecodedTransaction, coin: Coin) -> Bool {
        guard coin.chain == .ton, decoded.operation == .unstake,
              case .pool = decoded.counterparty else { return false }
        return true
    }

    func amount(for decoded: DecodedTransaction, coin: Coin) async -> HeroCoinAmount? {
        guard case .pool(let signedPool) = decoded.counterparty,
              let pools = try? await readPools(coin.address),
              let position = pools.first(where: { Self.sameAddress($0.pool, signedPool) }) else {
            return nil
        }

        let raw = BigInt(position.amount) + BigInt(position.pendingDeposit)
        guard raw > 0 else { return nil }
        let amount = coin.decimal(for: raw)
        return HeroCoinAmount(amount: amount, coin: coin)
    }

    private static func sameAddress(_ lhs: String, _ rhs: String) -> Bool {
        let normalize: (String) -> String = {
            TONAddressConverter.toUserFriendly(
                address: $0,
                bounceable: true,
                testnet: false
            ) ?? $0
        }
        return normalize(lhs) == normalize(rhs)
    }
}
