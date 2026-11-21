//
//  Tonstakers.swift
//  VultisigApp
//

import BigInt
import Foundation

/// Tonstakers liquid staking (tonapi implementation `liquidTF`), matching Android's `Tonstakers`
/// and verified against `ton-blockchain/liquid-staking-contract` and `tonstakers-sdk`.
///
/// Two contract facts the flows depend on:
/// - The pool takes `depositFee` (1 TON) off every deposit before staking, so the transfer must
///   carry the stake plus that fee.
/// - The pool reads two flag bits from the burn's `custom_payload`. Without that cell the read
///   underflows, the pool re-mints the tsTON, and the unstake silently does nothing but burn gas.
enum Tonstakers {
    /// Pool contract, bounceable user-friendly form so deposits bounce back if rejected.
    static let poolAddress = "EQCkWxfyhAkim3g2DjKQQg8T5P4g-Q1-K_jErGcDJZ4i-vqR"
    /// tsTON jetton master; equals `TokensStore.tston.contractAddress`.
    static let tsTONMasterAddress = "EQC98_qAmNEptUtPc7W6xdHh_ZHrBUFpw5Ft_IzNU20QAJav"
    static let tsTONDecimals = 9

    static let opPoolDeposit: UInt64 = 0x47d54391
    static let opJettonBurn: UInt64 = 0x595f07bc

    /// `DEPOSIT_FEE` in `pool.func`. Unspent part returns as excesses.
    static let depositFee = BigInt(1_000_000_000)
    /// `UNSTAKE_FEE_RES` in `tonstakers-sdk`: clears the pool's 0.5 TON withdrawal fee after the
    /// jetton-wallet and minter hops. Unspent part is refunded.
    static let unstakeAttachedValue = BigInt(1_050_000_000)
    /// Pool `min_stake` default, before `depositFee`.
    static let minStake = BigInt(1_000_000_000)

    private static let poolAddressRaw = tonFriendlyToRaw(poolAddress)

    /// Value a deposit must carry for the pool to stake `stakeAmount`.
    static func depositValue(stakeAmount: BigInt) -> BigInt {
        stakeAmount + depositFee
    }

    /// Smallest value a deposit may carry: pool minimum (default `minStake`) plus `depositFee`.
    static func minimumDepositValue(minStake poolMinStake: BigInt? = nil) -> BigInt {
        let base = poolMinStake.flatMap { $0 > 0 ? $0 : nil } ?? minStake
        return depositValue(stakeAmount: base)
    }

    /// `pool::deposit` with `query_id = 0`, base64 BOC for the transfer's custom payload.
    static func depositBody() throws -> String {
        let cell = try TonCellBuilder()
            .storeUInt(opPoolDeposit, bits: 32)
            .storeUInt(0, bits: 64)
            .build()
        return TonBocSerializer.toBase64(cell)
    }

    /// TEP-74 burn of `amount` tsTON base units, sent to the user's own tsTON jetton wallet.
    /// Both withdrawal flags clear by default: immediate payout when the pool has liquidity,
    /// round-end payout otherwise (the SDK default). `nil` when `responseAddress` is not TON.
    static func burnBody(
        amount: BigInt,
        responseAddress: String,
        waitTillRoundEnd: Bool = false,
        fillOrKill: Bool = false
    ) throws -> String? {
        guard let response = tonFriendlyToRaw(responseAddress) else { return nil }
        let flags = try TonCellBuilder().storeBit(waitTillRoundEnd).storeBit(fillOrKill).build()
        let body = try TonCellBuilder()
            .storeUInt(opJettonBurn, bits: 32)
            .storeUInt(0, bits: 64)
            .storeCoins(amount)
            .storeAddress(raw: response)
            .storeMaybeRef(flags)
            .build()
        return TonBocSerializer.toBase64(body)
    }

    /// Whether `address` is the Tonstakers pool, in any spelling.
    static func isPool(_ address: String?) -> Bool {
        guard let address, let raw = tonFriendlyToRaw(address) else { return false }
        return raw == poolAddressRaw
    }
}
