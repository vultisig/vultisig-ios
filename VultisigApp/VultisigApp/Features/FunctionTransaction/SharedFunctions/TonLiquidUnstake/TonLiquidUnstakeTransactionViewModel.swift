//
//  TonLiquidUnstakeTransactionViewModel.swift
//  VultisigApp
//

import BigInt
import Foundation
import OSLog

private let logger = Logger(subsystem: "com.vultisig.app", category: "ton-liquid-unstake-vm")

@MainActor
final class TonLiquidUnstakeTransactionViewModel: ObservableObject {
    /// Native TON coin: pays the attached value and the network fee.
    let coin: Coin
    let vault: Vault

    /// tsTON amount to burn, human-decimal. Partial unstake allowed, capped at the balance.
    @Published var amount: String = ""
    @Published var amountError: String?
    @Published var percentage: Double?

    @Published private(set) var jettonWalletAddress: String?
    /// tsTON balance in base units.
    @Published private(set) var tsTONBalance: BigInt = 0
    @Published private(set) var tonPerTsTON: Decimal?
    @Published private(set) var isLoading: Bool = true

    private let service = TonService.shared
    private let tsTONDecimals = Tonstakers.tsTONDecimals

    init(coin: Coin, vault: Vault) {
        self.coin = coin
        self.vault = vault
    }

    var tsTONBalanceDecimal: Decimal {
        (Decimal(string: tsTONBalance.description) ?? 0) / pow(Decimal(10), tsTONDecimals)
    }

    /// TON attached to the burn, refunded minus what the hops spend.
    var attachedValue: Decimal {
        (Decimal(string: Tonstakers.unstakeAttachedValue.description) ?? 0) / pow(Decimal(10), coin.decimals)
    }

    private var networkFee: Decimal {
        (Decimal(string: TonHelper.defaultFee.description) ?? 0) / pow(Decimal(10), coin.decimals)
    }

    /// Native TON must cover the attached value plus the network fee.
    var hasSufficientBalance: Bool {
        coin.balanceDecimal >= attachedValue + networkFee
    }

    /// Amount to burn in base units, or `nil` when empty, non-positive or above the balance.
    var burnAmount: BigInt? {
        let value = amount.toDecimal()
        guard value > 0 else { return nil }
        let raw = amount.formatToDecimal(digits: tsTONDecimals).toBigInt(decimals: tsTONDecimals)
        guard raw > 0, raw <= tsTONBalance else { return nil }
        return raw
    }

    /// TON the pool pays out for the entered tsTON at the current rate.
    var expectedTON: Decimal? {
        guard let rate = tonPerTsTON else { return nil }
        let value = amount.toDecimal()
        return value > 0 ? value * rate : nil
    }

    var canContinue: Bool {
        !isLoading && hasSufficientBalance && jettonWalletAddress != nil && burnAmount != nil
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }

        async let wallet = resolveWallet()
        async let balance = readTsTONBalance()
        async let rate = service.getTonstakersRate()

        jettonWalletAddress = await wallet
        tsTONBalance = await balance
        tonPerTsTON = await rate
        if amount.isEmpty, tsTONBalance > 0 {
            amount = tsTONBalanceDecimal.formatToDecimal(digits: tsTONDecimals)
        }
    }

    func validate() {
        let value = amount.toDecimal()
        if amount.isEmpty || value <= 0 {
            amountError = "emptyAmountField".localized
        } else if value > tsTONBalanceDecimal {
            amountError = "insufficientBalance".localized
        } else {
            amountError = nil
        }
    }

    var transactionBuilder: TransactionBuilder? {
        validate()
        guard canContinue, let jettonWalletAddress, let burnAmount else { return nil }
        return TonLiquidUnstakeTransactionBuilder(
            coin: coin,
            jettonWalletAddress: jettonWalletAddress,
            tsTONAmount: burnAmount
        )
    }

    /// Matched on the master: the indexer can return the owner's other jetton wallets too.
    private func resolveWallet() async -> String? {
        do {
            return try await service.getJettonWalletAddress(
                ownerAddress: coin.address,
                masterAddress: Tonstakers.tsTONMasterAddress
            )
        } catch {
            logger.error("Failed to resolve tsTON jetton wallet: \(error.localizedDescription, privacy: .private)")
            return nil
        }
    }

    private func readTsTONBalance() async -> BigInt {
        do {
            let raw = try await service.getJettonBalance(coin: TokensStore.tston, address: coin.address)
            return BigInt(raw) ?? 0
        } catch {
            logger.error("Failed to read tsTON balance: \(error.localizedDescription, privacy: .private)")
            return 0
        }
    }
}
