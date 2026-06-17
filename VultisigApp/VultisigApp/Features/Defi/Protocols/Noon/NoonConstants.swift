//
//  NoonConstants.swift
//  VultisigApp
//

import Foundation
import SwiftUI
import BigInt

/// Single source of truth for the Noon "sUSN Delta-Neutral" USDC yield vault.
///
/// Two addresses must never be confused:
/// - `vaultAddress` is the ERC-7540 vault and the `naccUSDC` share token; it is
///   the target for every on-chain transaction (deposit / requestRedeem /
///   withdraw) and the `approve` spender.
/// - `loanAddress` is the off-chain Accountable "loan" id, used only as the API
///   key for APY and TVL. It is NEVER a transaction target.
enum NoonConstants {
    /// ERC-7540 vault + `naccUSDC` share-token contract. Target of all user txs.
    static let vaultAddress = "0xA73424f1Ac94b3ef0D0c9af4F2967c87D4AF25D9"

    /// Accountable loan id — off-chain APY/TVL key only. Not a tx target.
    static let loanAddress = "0xc3Edd8B28C41749Eed38c2A33a78e3E046DFB876"

    /// Underlying asset (USDC, mainnet).
    static let usdcMainnet = "0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48"

    static let chain: Chain = .ethereum

    static let assetDecimals = 6
    static let shareDecimals = 6

    /// Product minimums in base units (6 dp), sourced from the loan terms
    /// (`on_chain_loan.loan.loan.minDeposit` / `.minRedeem`) with these as a
    /// hardcoded fallback because the loan terms can update. These mirror the
    /// SDK's hardcoded floors and are the authoritative deposit / redeem minimum.
    /// They are NOT the vault's on-chain `MIN_AMOUNT_WEI` (a 0.01 USDC dust floor).
    static let minDepositAssets = BigIntFallback.minDeposit
    static let minRedeemShares = BigIntFallback.minRedeem

    /// The fallback minimums as a single value, for the loan-API min source.
    static var fallbackMinimums: NoonMinimums {
        NoonMinimums(
            minDeposit: BigInt(minDepositAssets) ?? .zero,
            minRedeem: BigInt(minRedeemShares) ?? .zero
        )
    }

    enum BigIntFallback {
        // 100 USDC
        static let minDeposit = "100000000"
        // 95 naccUSDC
        static let minRedeem = "95000000"
    }

    /// Weekly redemption window: closes Wednesday 23:00 UTC, settles ~7 days later.
    enum RedemptionWindow {
        /// 1 = Sunday … 4 = Wednesday (Foundation `Calendar` weekday numbering).
        static let closesWeekday = 4
        static let closesHourUtc = 23
        static let settlementDays = 7
    }

    struct Design {
        static let horizontalPadding: CGFloat = 20
        static let cardPadding: CGFloat = 16
        static let verticalSpacing: CGFloat = 16
        static let cornerRadius: CGFloat = 16

        #if os(macOS)
        static let mainViewTopPadding: CGFloat = 60
        #else
        static let mainViewTopPadding: CGFloat = 16
        #endif

        static let mainViewBottomPadding: CGFloat = 32
    }
}
