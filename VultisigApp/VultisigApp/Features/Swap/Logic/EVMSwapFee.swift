//
//  EVMSwapFee.swift
//  VultisigApp
//
//  Single source of truth for the gas parameters an EVM aggregator/SwapKit
//  swap is SIGNED with. The signer (`OneInchSwaps`), the initiator's fee
//  display, the co-signer's fee display, and the gas-sufficiency validation
//  all consume this calculator, so the fee the user sees can never drift
//  from the fee the vault commits to.
//

import BigInt
import Foundation

enum EVMSwapFee {
    /// The gas parameters the transaction is signed with, and the resulting
    /// up-front bond (`gasPrice × gasLimit`) an EVM node requires the account
    /// to cover before admitting the transaction.
    struct Effective: Equatable {
        let gasPriceWei: BigInt
        let gasLimit: BigInt

        var feeWei: BigInt { gasPriceWei * gasLimit }
    }

    /// Reconciles an aggregator quote's gas parameters with the app's own fee
    /// oracle, exactly the way the signer builds the transaction:
    /// - a route that omits its gas (`quoteGas == 0`) falls back to the
    ///   default ETH swap gas unit, mirroring the signed fallback;
    /// - provider gas prices can be stale or too low, so the oracle
    ///   `maxFeePerGasWei` acts as a floor — transactions must not get stuck;
    /// - the oracle `gasLimit` floors the route gas so providers that
    ///   under-report can't produce insufficient-gas failures.
    static func effective(
        quoteGasPriceWei: BigInt,
        quoteGas: BigInt,
        maxFeePerGasWei: BigInt,
        gasLimit: BigInt
    ) -> Effective {
        let routeGas = quoteGas.isZero ? BigInt(EVMHelper.defaultETHSwapGasUnit) : quoteGas
        return Effective(
            gasPriceWei: max(quoteGasPriceWei, maxFeePerGasWei),
            gasLimit: max(routeGas, gasLimit)
        )
    }

    /// Parses an `EVMQuote.tx.gasPrice` decimal string the way the signer
    /// does: non-negative decimal digits, anything unparseable becomes zero
    /// (so the oracle floor takes over).
    static func quoteGasPriceWei(_ gasPrice: String) -> BigInt {
        BigUInt(gasPrice).map { BigInt($0) } ?? .zero
    }
}
