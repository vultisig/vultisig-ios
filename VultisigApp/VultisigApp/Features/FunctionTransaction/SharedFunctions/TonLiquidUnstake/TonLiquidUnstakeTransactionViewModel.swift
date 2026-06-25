//
//  TonLiquidUnstakeTransactionViewModel.swift
//  VultisigApp
//

import Foundation
import OSLog
import BigInt

private let logger = Logger(subsystem: "com.vultisig.app", category: "ton-liquid-unstake-vm")

@MainActor
final class TonLiquidUnstakeTransactionViewModel: ObservableObject {
    /// Native TON coin — funds the burn's forward gas.
    let coin: Coin
    let vault: Vault
    /// TON-valued position shown for confirmation.
    let stakedAmount: Decimal

    /// Resolved tsTON jetton wallet (burn destination) and raw tsTON balance
    /// (burn amount, base units). Populated async in `load()`.
    @Published private(set) var jettonWalletAddress: String?
    @Published private(set) var tsTONBalanceRaw: String?
    @Published private(set) var isLoading: Bool = true

    private let service = TonService.shared

    init(coin: Coin, vault: Vault, stakedAmount: Decimal) {
        self.coin = coin
        self.vault = vault
        self.stakedAmount = stakedAmount
    }

    /// Burn carries `burnGasNano` TON for forward gas; require the liquid
    /// balance to cover that plus the network fee.
    var hasSufficientBalance: Bool {
        let fee = TonHelper.defaultFee.description.toDecimal() / pow(Decimal(10), coin.decimals)
        let gas = TonstakersConstants.burnGasNano.description.toDecimal() / pow(Decimal(10), coin.decimals)
        return coin.balanceDecimal >= gas + fee
    }

    var hasTsTONToBurn: Bool {
        guard let raw = tsTONBalanceRaw, let value = BigInt(raw) else { return false }
        return value > 0
    }

    var canContinue: Bool {
        !isLoading && hasSufficientBalance && hasTsTONToBurn && jettonWalletAddress != nil
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }

        async let wallet = service.resolveJettonWalletAddress(
            ownerAddress: coin.address,
            masterAddress: TonstakersConstants.tsTONMasterAddress
        )
        async let balance = readTsTONBalance()

        jettonWalletAddress = await wallet
        tsTONBalanceRaw = await balance

        if jettonWalletAddress == nil {
            logger.error("Failed to resolve tsTON jetton wallet for unstake")
        }
    }

    private func readTsTONBalance() async -> String {
        do {
            return try await service.getJettonBalance(coin: TokensStore.tston, address: coin.address)
        } catch {
            logger.error("Failed to read tsTON balance for unstake: \(error.localizedDescription, privacy: .private)")
            return .zero
        }
    }

    var transactionBuilder: TransactionBuilder? {
        guard
            canContinue,
            let jettonWalletAddress,
            let tsTONBalanceRaw
        else { return nil }

        let gasAmount = TonstakersConstants.burnGasNano.description.toDecimal() / pow(Decimal(10), coin.decimals)
        return TonLiquidUnstakeTransactionBuilder(
            coin: coin,
            ownerAddress: coin.address,
            jettonWalletAddress: jettonWalletAddress,
            tsTONAmountRaw: tsTONBalanceRaw,
            amount: gasAmount.formatToDecimal(digits: coin.decimals)
        )
    }
}
