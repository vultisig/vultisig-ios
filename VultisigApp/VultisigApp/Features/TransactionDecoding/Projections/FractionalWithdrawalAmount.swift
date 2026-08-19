//
//  FractionalWithdrawalAmount.swift
//  VultisigApp
//
//  Resolves a signed withdrawal fraction against the signer's own public staked
//  position. Failed reads leave the verb-only presentation unchanged.
//

import Foundation

enum FractionalWithdrawalAmount {

    /// Resolves a fractional unstake from a base-unit position reader.
    static func resolve(
        for decoded: DecodedTransaction,
        coin: Coin,
        readStakedRaw: (String) async -> Decimal
    ) async -> HeroCoinAmount? {
        // Absolute amounts already exist in signed content.
        guard case .fraction(let basisPoints, _) = decoded.amount,
              basisPoints > 0, basisPoints <= 10_000 else { return nil }

        let rawStaked = await readStakedRaw(coin.address)
        let divisor = Decimal(sign: .plus, exponent: coin.decimals, significand: 1)
        let staked = rawStaked / divisor
        guard staked > 0 else { return nil }

        // Match builder arithmetic: position × BPS, truncated to asset precision.
        let amount = (staked * Decimal(basisPoints)) / Decimal(10_000)
        guard amount > 0 else { return nil }

        return HeroCoinAmount(amount: amount, coin: coin)
    }
}
