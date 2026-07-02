//
//  TerraClassicTax.swift
//  VultisigApp
//

import Foundation
import BigInt

/// Terra Classic (columbus-5) charges a proportional **burn tax** on every
/// `MsgSend`, paid in the send denom on top of the gas fee. The rate lives in
/// the chain's `x/tax` module (`burn_tax_rate`, currently 0.5%) and is fetched
/// live; this helper holds the conservative fallback and the pure tax math so
/// the signed fee, the validated fee, and the displayed fee stay consistent.
enum TerraClassicTax {

    /// Conservative fallback burn-tax rate used when the live `x/tax` params
    /// can't be fetched/decoded. Matches current governance (0.5%). Failing
    /// closed (taxing) rather than open (0%) avoids signing a tx the chain then
    /// rejects at broadcast.
    static let fallbackBurnTaxRate = Decimal(string: "0.005")! // swiftlint:disable:this force_unwrapping

    /// Burn tax on a send `amount` (in the denom's smallest unit) at `rate`,
    /// rounded **up** so the signed fee never undershoots the chain's check.
    static func burnTax(amount: BigInt, rate: Decimal) -> BigInt {
        guard amount > 0, rate > 0 else { return 0 }

        // amount * rate, rounded up. Work in Decimal then ceil to an integer.
        let amountDecimal = Decimal(string: amount.description) ?? 0
        var product = amountDecimal * rate
        var rounded = Decimal()
        NSDecimalRound(&rounded, &product, 0, .up)

        // `rounded` is a non-negative integer Decimal, so its stringValue is a
        // plain base-10 integer string the BigInt initializer accepts.
        return BigInt(NSDecimalNumber(decimal: rounded).stringValue) ?? 0
    }

    /// Parse a decimal-string `burn_tax_rate` from the LCD into a `Decimal`,
    /// falling back to the conservative default on any parse failure.
    static func parseRate(_ raw: String) -> Decimal {
        guard let value = Decimal(string: raw), value >= 0 else {
            return fallbackBurnTaxRate
        }
        return value
    }

    /// Whether a Terra Classic coin is a **bank denom** (e.g. USTC's `uusd`)
    /// that pays its gas + burn tax in its OWN denom, as opposed to a CW20
    /// contract token (`terra1…`) or an IBC token (`ibc/…`) that pays the fee
    /// in native LUNC (`uluna`). Mirrors the bank-denom branch selection in
    /// `TerraHelperStruct.getPreSignedInputData` so the signed fee, the
    /// validated fee, and the max-send math all agree on which tokens are taxed
    /// in their own denom. The native coin (LUNC) is intentionally excluded —
    /// it is handled by its own native-balance branch.
    static func isBankDenom(contractAddress: String, isNativeToken: Bool) -> Bool {
        guard !isNativeToken else { return false }
        let denom = contractAddress.lowercased()
        return !denom.contains("terra1")
            && !denom.hasPrefix("ibc/")
            && !denom.hasPrefix("factory/")
    }

    /// Base gas fee for an `uluna`-denominated Terra Classic send (300k gas x
    /// 28.325 uluna/gas = 8,497,500 uluna ≈ 8.5 LUNC). `28.325` is Terra Classic's
    /// `uluna` minimum gas price — the same source as the `0.75 uusd` rate below
    /// (both from the chain's gas-price config that wallets fee off). Paid by
    /// native LUNC, CW20 (`terra1…`) and IBC (`ibc/…`) tokens, whose fee the
    /// signer denominates in `uluna`.
    static let ulunaBaseGas: UInt64 = 8497500

    /// Base gas fee for a `uusd`-denominated Terra Classic send (300k gas x
    /// 0.75 uusd/gas = 225000 uusd). Paid only by the USTC bank denom, whose fee
    /// the signer denominates in `uusd`.
    static let uusdBaseGas: UInt64 = 225000

    /// Base gas number for a Terra Classic send, in the SAME denom the signer
    /// uses for the fee (see `TerraHelperStruct.getPreSignedInputData`). Bank
    /// denoms (USTC / `uusd`) get the `uusd` base; everything else — native LUNC,
    /// CW20 and IBC — gets the `uluna` base. Gating both this and the signed fee
    /// denom on `isBankDenom` keeps the gas number and the fee denom in lockstep.
    static func baseGas(contractAddress: String, isNativeToken: Bool) -> UInt64 {
        isBankDenom(contractAddress: contractAddress, isNativeToken: isNativeToken)
            ? uusdBaseGas
            : ulunaBaseGas
    }

    /// The static gas limit that `ulunaBaseGas` / `uusdBaseGas` are priced at
    /// (300k gas × the per-gas price). Mirrors `TerraHelperStruct.GasLimit`; the
    /// signer re-derives the fee amount by scaling the base from this limit to
    /// the effective (relayed) limit.
    static let staticGasLimit: UInt64 = 300_000

    /// Re-derive the Terra Classic send fee amount for a (possibly dynamic)
    /// `gasLimit`, preserving any burn tax folded into the upstream `staticFee`.
    ///
    /// The signer honors a relayed dynamic `gas_wanted` (`effectiveGasLimit`) but
    /// `staticFee` (`chainSpecific.gas`) is priced for the static 300k limit, so
    /// once the relayed limit exceeds 300k the signed fee undershoots Terra
    /// Classic's `fee >= gas_wanted × price (+ tax)` ante check (on-chain
    /// `code 13`). This scales the BASE gas portion with the gas limit at the
    /// chain's per-gas price (`ulunaBaseGas` / `uusdBaseGas` are `price × 300k`,
    /// so scaling by the limit ratio is `ceil(gasLimit × price)`), while the burn
    /// tax — a fixed proportion of the SEND amount, independent of gas — is
    /// carried over unchanged. At `gasLimit == staticGasLimit` it returns
    /// `staticFee` verbatim, so the non-simulated path is byte-identical.
    ///
    /// Pure function of `staticFee`, the relayed limit and static constants, so
    /// every co-signer derives the identical fee.
    static func scaledSendFee(
        staticFee: UInt64,
        contractAddress: String,
        isNativeToken: Bool,
        gasLimit: UInt64
    ) -> UInt64 {
        let base = baseGas(contractAddress: contractAddress, isNativeToken: isNativeToken)
        // Burn tax folded into `staticFee` upstream (0 for CW20 / IBC, which pay
        // no folded tax). Guarded against underflow.
        let tax = staticFee > base ? staticFee - base : 0
        let scaledBase = CosmosGasPricedFee.scaled(
            base: base,
            fromGasLimit: staticGasLimit,
            toGasLimit: gasLimit
        )
        return scaledBase + tax
    }
}
