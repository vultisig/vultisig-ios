//
//  SwapCryptoViewModel.swift
//  VultisigApp
//
//  Created by Artur Guseinov on 02.04.2024.
//

import SwiftUI
import BigInt
import WalletCore
import Mediator

@MainActor
class SwapCryptoViewModel: ObservableObject, TransferViewModel {
    private let titles = ["swap", "swapOverview", "pair", "keysign", "done"]

    private var updateQuoteTask: Task<Void, Never>?
    private var updateFeesTask: Task<Void, Never>?

    // Logic delegation
    private let logic = SwapCryptoLogic()

    var keysignPayload: KeysignPayload?

    @Published var currentIndex = 1
    @Published var currentTitle = "swap"
    @Published var hash: String?
    @Published var approveHash: String?

    @Published var error: Error?
    @Published var isLoading = false
    @Published var isLoadingQuotes = false
    @Published var isLoadingFees = false
    @Published var isLoadingTransaction = false
    @Published var dataLoaded = false
    @Published var timer: Int = 59

    @Published var fromChain: Chain? = nil
    @Published var toChain: Chain? = nil
    @Published var showFromChainSelector = false
    @Published var showToChainSelector = false
    @Published var showFromCoinSelector = false
    @Published var showToCoinSelector = false
    @Published var showAllPercentageButtons = true

    var progress: Double {
        return Double(currentIndex) / Double(titles.count)
    }

    func load(initialFromCoin: Coin?, initialToCoin: Coin?, vault: Vault, tx: SwapTransaction) {
        guard !dataLoaded else { return }
        logic.load(initialFromCoin: initialFromCoin, initialToCoin: initialToCoin, vault: vault, tx: tx)
        dataLoaded = true
    }

    func loadFastVault(tx: SwapTransaction, vault: Vault) async {
        tx.isFastVault = await logic.loadFastVault(tx: tx, vault: vault)
    }

    func updateCoinLists(tx: SwapTransaction) {
        logic.updateCoinLists(tx: tx)
    }

    func progressLink(tx: SwapTransaction, hash: String) -> String? {
        return logic.progressLink(tx: tx, hash: hash)
    }

    func fromFiatAmount(tx: SwapTransaction) -> String {
        return logic.fromFiatAmount(tx: tx)
    }

    func toFiatAmount(tx: SwapTransaction) -> String {
        return logic.toFiatAmount(tx: tx)
    }

    func showGas(tx: SwapTransaction) -> Bool {
        return logic.showGas(tx: tx)
    }

    func showFees(tx: SwapTransaction) -> Bool {
        return logic.showFees(tx: tx)
    }

    func showTotalFees(tx: SwapTransaction) -> Bool {
        return logic.showTotalFees(tx: tx)
    }

    func showDuration(tx: SwapTransaction) -> Bool {
        return logic.showDuration(tx: tx)
    }

    func showAllowance(tx: SwapTransaction) -> Bool {
        return logic.showAllowance(tx: tx)
    }

    func showToAmount(tx: SwapTransaction) -> Bool {
        return logic.showToAmount(tx: tx)
    }

    func swapFeeString(tx: SwapTransaction) -> String {
        return logic.swapFeeString(tx: tx)
    }

    func swapGasString(tx: SwapTransaction) -> String {
        return logic.swapGasString(tx: tx)
    }

    func approveFeeString(tx: SwapTransaction) -> String {
        return logic.approveFeeString(tx: tx)
    }

    func totalFeeString(tx: SwapTransaction) -> String {
        return logic.totalFeeString(tx: tx)
    }

    func isSufficientBalance(tx: SwapTransaction) -> Bool {
        return logic.isSufficientBalance(tx: tx)
    }

    func durationString(tx: SwapTransaction) -> String {
        return logic.durationString(tx: tx)
    }

    func validateForm(tx: SwapTransaction) -> Bool {
        return logic.validateForm(tx: tx, isLoading: isLoading)
    }

    func moveToNextView() {
        currentIndex += 1
        currentTitle = titles[currentIndex-1]
    }

    func buildSwapKeysignPayload(tx: SwapTransaction, vault: Vault) async -> Bool {
        isLoadingTransaction = true
        defer { isLoadingTransaction = false }

        do {
            keysignPayload = try await logic.buildSwapKeysignPayload(tx: tx, vault: vault)
            return true
        } catch {
            self.error = error
            return false
        }
    }

    func stopMediator() {
        Mediator.shared.stop()
    }

    func switchCoins(tx: SwapTransaction, vault: Vault, referredCode: String) {
        let fromCoin = tx.fromCoin
        let toCoin = tx.toCoin
        tx.fromCoin = toCoin
        tx.toCoin = fromCoin
        fetchQuotes(tx: tx, vault: vault, referredCode: referredCode)
    }

    func updateFromAmount(tx: SwapTransaction, vault: Vault, referredCode: String) {
        fetchQuotes(tx: tx, vault: vault, referredCode: referredCode)
    }

    func updateFromCoin(coin: Coin, tx: SwapTransaction, vault: Vault, referredCode: String) {
        tx.fromCoin = coin
        fromChain = coin.chain
        fetchQuotes(tx: tx, vault: vault, referredCode: referredCode)
        updateBalance(for: coin)
    }

    func updateToCoin(coin: Coin, tx: SwapTransaction, vault: Vault, referredCode: String) {
        tx.toCoin = coin
        toChain = coin.chain
        fetchQuotes(tx: tx, vault: vault, referredCode: referredCode)
        updateBalance(for: coin)
    }

    func updateBalance(for coin: Coin) {
        Task {
            await BalanceService.shared.updateBalance(for: coin)
        }
    }

    func handleBackTap() {
        currentIndex-=1
        currentTitle = titles[currentIndex-1]
    }

    func updateTimer(tx: SwapTransaction, vault: Vault, referredCode: String) {
        timer -= 1

        if timer < 1 {
            restartTimer(tx: tx, vault: vault, referredCode: referredCode)
        }
    }

    func restartTimer(tx: SwapTransaction, vault: Vault, referredCode: String) {
        refreshData(tx: tx, vault: vault, referredCode: referredCode)
        timer = 59
    }

    func refreshData(tx: SwapTransaction, vault: Vault, referredCode: String) {
        fetchQuotes(tx: tx, vault: vault, referredCode: referredCode)
    }

    func fetchFees(tx: SwapTransaction, vault: Vault) {
        updateFeesTask?.cancel()
        updateFeesTask = Task {[weak self] in
            try? await Task.sleep(nanoseconds: 300_000_000) // 0.3 seconds delay
            guard !Task.isCancelled else { return }

            self?.isLoadingFees = true
            defer { self?.isLoadingFees = false }

            await self?.updateFees(tx: tx, vault: vault)
        }
    }

    func fetchQuotes(tx: SwapTransaction, vault: Vault, referredCode: String) {
        // this method is called when the user changes the amount, from/to coins, or chains
        // it will update the quotes after a short delay to avoid excessive requests
        updateQuoteTask?.cancel()
        updateQuoteTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 300_000_000) // 0.3 seconds delay
            guard !Task.isCancelled else { return }

            self?.isLoadingQuotes = true
            self?.isLoadingFees = true
            defer {
                self?.isLoadingQuotes = false
                self?.isLoadingFees = false
            }

            await self?.updateQuotes(tx: tx, vault: vault, referredCode: referredCode)
            await self?.updateFees(tx: tx, vault: vault)
        }
    }

    func pickerFromCoins(tx: SwapTransaction) -> [Coin] {
        return logic.pickerFromCoins(tx: tx, fromChain: fromChain)
    }

    func pickerToCoins(tx: SwapTransaction) -> [Coin] {
        return logic.pickerToCoins(tx: tx, toChain: toChain)
    }

    // Helper to get fee coin needed for view display
    func feeCoin(tx: SwapTransaction) -> Coin {
        return logic.feeCoin(tx: tx)
    }
}

private extension SwapCryptoViewModel {

    func updateQuotes(tx: SwapTransaction, vault: Vault, referredCode: String) async {
        // Loading state managed by caller

        tx.quote = nil

        error = nil

        guard !tx.fromAmount.isEmpty else { return }

        do {
            let quote = try await logic.fetchQuote(tx: tx, vault: vault, referredCode: referredCode)
            tx.quote = quote

            if !logic.isSufficientBalance(tx: tx) {
                throw SwapCryptoLogic.Errors.insufficientFunds
            }
        } catch {
            if let error = error as? URLError, error.code == .cancelled {
                print("request cancelled")
            } else {
                self.error = error
            }
        }
    }

    func updateFees(tx: SwapTransaction, vault: Vault) async {
        // Loading state managed by caller

        tx.gas = .zero
        tx.thorchainFee = .zero

        // Skip fee calculation if no amount is entered
        guard !tx.fromAmount.isEmpty, !tx.fromAmountDecimal.isZero else {
            return
        }

        do {
            let chainSpecific = try await logic.fetchChainSpecific(tx: tx)
            tx.gas = chainSpecific.gas
            tx.thorchainFee = try await logic.thorchainFee(for: chainSpecific, tx: tx, vault: vault)

        } catch {
            print("Update fees error: \(error.localizedDescription)")

            // Handle UTXO-specific errors for better user experience
            switch error {
            case KeysignPayloadFactory.Errors.notEnoughUTXOError,
                 KeysignPayloadFactory.Errors.utxoTooSmallError,
                 KeysignPayloadFactory.Errors.utxoSelectionFailedError:
                // These are UTXO-specific errors that should be shown directly
                self.error = error
            default:
                self.error = SwapCryptoLogic.Errors.insufficientFunds
            }
        }
    }
}

// MARK: - Asset Selection

extension SwapCryptoViewModel {
    func handleFromChainUpdate(tx: SwapTransaction, vault: Vault) {
        guard
            let fromChain,
            fromChain != tx.fromCoin.chain,
            let coin = logic.getDefaultCoin(for: fromChain, vault: vault)
        else { return }
        tx.fromCoin = coin
    }

    func handleToChainUpdate(tx: SwapTransaction, vault: Vault) {
        guard
            let toChain,
            toChain != tx.toCoin.chain,
            let coin = logic.getDefaultCoin(for: toChain, vault: vault) else { return }
        tx.toCoin = coin
    }
}

// MARK: - Logic

struct SwapCryptoLogic {

    private let swapService = SwapService.shared
    private let blockchainService = BlockChainService.shared
    private let fastVaultService = FastVaultService.shared

    // MARK: - Errors
    enum Errors: String, Error, LocalizedError {
        case unexpectedError
        case insufficientFunds
        case swapAmountTooSmall
        case inboundAddress

        var errorTitle: String {
            switch self {
            case .unexpectedError:
                return "swapErrorUnexpectedTitle".localized
            case .insufficientFunds:
                return "swapErrorInsufficientFundsTitle".localized
            case .swapAmountTooSmall:
                return "swapErrorAmountTooSmallTitle".localized
            case .inboundAddress:
                return "swapErrorInboundAddressTitle".localized
            }
        }

        var errorDescription: String? {
            switch self {
            case .unexpectedError:
                return "swapErrorUnexpectedDescription".localized
            case .insufficientFunds:
                return "swapErrorInsufficientFundsDescription".localized
            case .swapAmountTooSmall:
                return "swapErrorAmountTooSmallDescription".localized
            case .inboundAddress:
                return "swapErrorInboundAddressDescription".localized
            }
        }
    }

    // MARK: - Loaders

    func load(initialFromCoin: Coin?, initialToCoin: Coin?, vault: Vault, tx: SwapTransaction) {
        let allCoins = vault.coins
        guard !allCoins.isEmpty else { return }

        let (fromCoins, fromCoin) = SwapCoinsResolver.resolveFromCoins(allCoins: allCoins)
        let resolvedFromCoin = initialFromCoin ?? fromCoin

        let (toCoins, toCoin) = SwapCoinsResolver.resolveToCoins(
            fromCoin: resolvedFromCoin,
            allCoins: allCoins,
            selectedToCoin: initialToCoin ?? .example
        )

        tx.load(fromCoin: resolvedFromCoin, toCoin: toCoin, fromCoins: fromCoins, toCoins: toCoins)
    }

    func loadFastVault(tx: SwapTransaction, vault: Vault) async -> Bool {
        let isExist = await fastVaultService.exist(pubKeyECDSA: vault.pubKeyECDSA)
        let isLocalBackup = vault.localPartyID.lowercased().contains("server-")
        return isExist && !isLocalBackup
    }

    func updateCoinLists(tx: SwapTransaction) {
        let (toCoins, toCoin) = SwapCoinsResolver.resolveToCoins(
            fromCoin: tx.fromCoin,
            allCoins: tx.fromCoins,
            selectedToCoin: tx.toCoin
        )
        tx.toCoin = toCoin
        tx.toCoins = toCoins
    }

    // MARK: - Formatters & Presentation

    func progressLink(tx: SwapTransaction, hash: String) -> String? {
        switch tx.quote {
        case .thorchain:
            return Endpoint.getSwapProgressURL(txid: hash)
        case .thorchainStagenet:
            return Endpoint.getStagenetSwapProgressURL(txid: hash)
        case .mayachain:
            return Endpoint.getMayaSwapTracker(txid: hash)
        case .lifi:
            return Endpoint.getLifiSwapTracker(txid: hash)
        case .oneinch, .kyberswap, .none:
            return Endpoint.getExplorerURL(chain: tx.fromCoin.chain, txid: hash)
        }
    }

    func fromFiatAmount(tx: SwapTransaction) -> String {
        let fiatDecimal = tx.fromCoin.fiat(decimal: tx.fromAmountDecimal)
        return fiatDecimal.formatForDisplay()
    }

    func toFiatAmount(tx: SwapTransaction) -> String {
        let fiatDecimal = tx.toCoin.fiat(decimal: tx.toAmountDecimal)
        return fiatDecimal.formatForDisplay()
    }

    func showGas(tx: SwapTransaction) -> Bool {
        return !tx.gas.isZero
    }

    func showFees(tx: SwapTransaction) -> Bool {
        let fee = swapFeeString(tx: tx)
        return !fee.isEmpty && !fee.isZero
    }

    func showTotalFees(tx: SwapTransaction) -> Bool {
        let fee = totalFeeString(tx: tx)
        return !fee.isEmpty && !fee.isZero
    }

    func showDuration(tx: SwapTransaction) -> Bool {
        return showFees(tx: tx)
    }

    func showAllowance(tx: SwapTransaction) -> Bool {
        return tx.isApproveRequired
    }

    func showToAmount(tx: SwapTransaction) -> Bool {
        return tx.toAmountDecimal != 0
    }

    func swapFeeString(tx: SwapTransaction) -> String {
        guard let inboundFeeDecimal = tx.inboundFeeDecimal, !inboundFeeDecimal.isZero else { return .empty }

        let inboundFee = tx.toCoin.raw(for: inboundFeeDecimal)
        let fee = tx.toCoin.fiat(value: inboundFee)
        return fee.formatToFiat(includeCurrencySymbol: true)
    }

    func swapGasString(tx: SwapTransaction) -> String {
        let coin = feeCoin(tx: tx)
        let decimals = coin.decimals

        // Use tx.fee for swap quotes (which includes corrected gas price calculations)
        // Fall back to tx.gas for other transaction types
        let gasValue = tx.quote != nil ? tx.fee : tx.gas

        if coin.chain.chainType == .EVM {
            guard let weiPerGWeiDecimal = Decimal(string: EVMHelper.weiPerGWei.description) else {
                return .empty
            }
            return "\((Decimal(gasValue) / weiPerGWeiDecimal).formatToDecimal(digits: 0).description) \(coin.chain.feeUnit)"
        } else {
            return "\((Decimal(gasValue) / pow(10, decimals)).formatToDecimal(digits: decimals).description) \(coin.ticker)"
        }
    }

    func approveFeeString(tx: SwapTransaction) -> String {
        let fromCoin = feeCoin(tx: tx)
        let fee = fromCoin.fiat(gas: tx.fee)
        return fee.formatToFiat(includeCurrencySymbol: true)
    }

    func totalFeeString(tx: SwapTransaction) -> String {
        guard let inboundFeeDecimal = tx.inboundFeeDecimal else { return .empty }

        let fromCoin = feeCoin(tx: tx)
        let inboundFee = tx.toCoin.raw(for: inboundFeeDecimal)
        let providerFee = tx.toCoin.fiat(value: inboundFee)
        let networkFee = fromCoin.fiat(gas: tx.fee)
        let totalFee = providerFee + networkFee
        return totalFee.formatToFiat(includeCurrencySymbol: true)
    }

    func durationString(tx: SwapTransaction) -> String {
        guard let duration = tx.quote?.totalSwapSeconds else { return "Instant" }
        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .full
        formatter.includesApproximationPhrase = false
        formatter.includesTimeRemainingPhrase = false
        formatter.allowedUnits = [.day, .hour, .minute, .second]
        formatter.maximumUnitCount = 1
        let fromDate = Date(timeIntervalSince1970: 0)
        let toDate = Date(timeIntervalSince1970: TimeInterval(duration))
        return formatter.string(from: fromDate, to: toDate) ?? .empty
    }

    // MARK: - Helper Logic

    func feeCoin(tx: SwapTransaction) -> Coin {
        // Fees are always paid in native token
        guard !tx.fromCoin.isNativeToken else { return tx.fromCoin }
        return tx.fromCoins.first(where: { $0.chain == tx.fromCoin.chain && $0.isNativeToken }) ?? tx.fromCoin
    }

    func getDefaultCoin(for chain: Chain, vault: Vault) -> Coin? {
        let firstVaultCoin = vault.coins
            .filter { $0.chain == chain && $0.isNativeToken}
            .first

        if let firstVaultCoin {
            return firstVaultCoin
        } else {
            let coinMeta = TokensStore.TokenSelectionAssets
                .filter { $0.chain == chain }
                .sorted { $0.isNativeToken && !$1.isNativeToken }
                .first
            let pubKey = vault.chainPublicKeys.first { $0.chain == chain }?.publicKeyHex
            let isDerived = pubKey != nil
            guard let coinMeta, let coin = try? CoinFactory.create(asset: coinMeta,
                                                                   publicKeyECDSA: pubKey ?? vault.pubKeyECDSA,
                                                                   publicKeyEdDSA: pubKey ?? vault.pubKeyEdDSA,
                                                                   hexChainCode: vault.hexChainCode,
                                                                   isDerived: isDerived) else {
                return nil
            }
            return coin
        }
    }

    func pickerFromCoins(tx: SwapTransaction, fromChain: Chain?) -> [Coin] {
        return tx.fromCoins.filter({ coin in
            coin.chain == fromChain
        }).sorted(by: {
            Int($0.chain == tx.fromCoin.chain) > Int($1.chain == tx.fromCoin.chain)
        })
    }

    func pickerToCoins(tx: SwapTransaction, toChain: Chain?) -> [Coin] {
        return tx.toCoins.filter({ coin in
            coin.chain == toChain
        }).sorted(by: {
            Int($0.chain == tx.toCoin.chain) > Int($1.chain == tx.toCoin.chain)
        })
    }

    // MARK: - Validation

    func isSufficientBalance(tx: SwapTransaction) -> Bool {
        let feeCoin = feeCoin(tx: tx)
        let fromFee = feeCoin.decimal(for: tx.fee)

        let fromBalance = tx.fromCoin.balanceDecimal
        let feeCoinBalance = feeCoin.balanceDecimal

        let amount = tx.fromAmount.toDecimal()

        if feeCoin == tx.fromCoin {
            return fromFee + amount <= fromBalance
        } else {
            return fromFee <= feeCoinBalance && amount <= fromBalance
        }
    }

    func validateForm(tx: SwapTransaction, isLoading: Bool) -> Bool {
        return tx.fromCoin != tx.toCoin
        && tx.fromCoin != .example
        && tx.toCoin != .example
        && !tx.fromAmount.isEmpty
        && !tx.toAmountDecimal.isZero
        && tx.quote != nil
        && tx.gas != .zero
        && isSufficientBalance(tx: tx)
        && !isLoading
    }

    // MARK: - Core Operations (Quotes & Fees)

    func fetchQuote(tx: SwapTransaction, vault: Vault, referredCode: String) async throws -> SwapQuote {
        guard !tx.fromAmountDecimal.isZero, tx.fromCoin != tx.toCoin else {
            throw Errors.unexpectedError // Or just return? Logic upstream handles this check usually
        }

        let vultTier = await VultTierService().fetchDiscountTier(for: vault)
        let quote = try await swapService.fetchQuote(
            amount: tx.fromAmountDecimal,
            fromCoin: tx.fromCoin,
            toCoin: tx.toCoin,
            isAffiliate: tx.isAffiliate,
            referredCode: referredCode,
            vultTierDiscount: vultTier?.bpsDiscount ?? 0
        )

        return quote
    }

    func fetchChainSpecific(tx: SwapTransaction) async throws -> BlockChainSpecific {
        return try await blockchainService.fetchSpecific(tx: tx)
    }

    func thorchainFee(for chainSpecific: BlockChainSpecific, tx: SwapTransaction, vault: Vault) async throws -> BigInt {
        switch chainSpecific {
        case .Ethereum(let maxFeePerGas, let priorityFee, _, let gasLimit):
            return (maxFeePerGas + priorityFee) * gasLimit
        case .UTXO, .Cardano:
            let keysignFactory = KeysignPayloadFactory()
            do {
                let keysignPayload = try await keysignFactory.buildTransfer(
                    coin: tx.fromCoin,
                    toAddress: tx.fromCoin.address,
                    amount: tx.amountInCoinDecimal,
                    memo: nil,
                    chainSpecific: chainSpecific,
                    swapPayload: nil,
                    vault: vault
                )

                let planFee: BigInt
                switch tx.fromCoin.chain {
                case .cardano:
                    let cardanoHelper = CardanoHelper()
                    planFee = try cardanoHelper.calculateDynamicFee(keysignPayload: keysignPayload)

                default: // UTXO chains
                    let utxo = UTXOChainsHelper(coin: tx.fromCoin.coinType)
                    let plan = try utxo.getBitcoinTransactionPlan(keysignPayload: keysignPayload)
                    planFee = BigInt(plan.fee)
                }

                if planFee <= 0 && tx.fromAmountDecimal > 0 {
                    throw Errors.insufficientFunds
                }
                return planFee
            } catch {
                if error is KeysignPayloadFactory.Errors {
                    throw error
                }
                throw Errors.insufficientFunds
            }

        case .Cosmos, .THORChain, .Polkadot, .MayaChain, .Solana, .Sui, .Ton, .Ripple, .Tron:
            return chainSpecific.gas
        }
    }

    func buildApprovePayload(tx: SwapTransaction) -> ERC20ApprovePayload? {
        guard tx.isApproveRequired, let spender = tx.router else {
            return nil
        }
        // Approve exact amount - no buffer needed for KyberSwap precision
        let payload = ERC20ApprovePayload(amount: tx.amountInCoinDecimal, spender: spender)
        return payload
    }

    func buildSwapKeysignPayload(tx: SwapTransaction, vault: Vault) async throws -> KeysignPayload {
        guard let quote = tx.quote else {
            throw Errors.unexpectedError
        }

        let chainSpecific = try await blockchainService.fetchSpecific(tx: tx)
        let keysignFactory = KeysignPayloadFactory()

        switch quote {
        case .mayachain(let quote):
            let toAddress = tx.fromCoin.isNativeToken ? quote.inboundAddress : quote.router
            return try await keysignFactory.buildTransfer(
                coin: tx.fromCoin,
                toAddress: toAddress ?? tx.fromCoin.address,
                amount: tx.amountInCoinDecimal,
                memo: tx.quote?.memo,
                chainSpecific: chainSpecific,
                swapPayload: .mayachain(tx.buildThorchainSwapPayload(
                    quote: quote,
                    provider: .mayachain
                )),
                approvePayload: buildApprovePayload(tx: tx),
                vault: vault
            )

        case .thorchain(let quote):
            let toAddress = quote.router ?? quote.inboundAddress ?? tx.fromCoin.address
            return try await keysignFactory.buildTransfer(
                coin: tx.fromCoin,
                toAddress: toAddress,
                amount: tx.amountInCoinDecimal,
                memo: quote.memo,
                chainSpecific: chainSpecific,
                swapPayload: .thorchain(tx.buildThorchainSwapPayload(
                    quote: quote,
                    provider: .thorchain
                )),
                approvePayload: buildApprovePayload(tx: tx),
                vault: vault
            )

        case .thorchainStagenet(let quote):
            let toAddress = quote.router ?? quote.inboundAddress ?? tx.fromCoin.address
            return try await keysignFactory.buildTransfer(
                coin: tx.fromCoin,
                toAddress: toAddress,
                amount: tx.amountInCoinDecimal,
                memo: quote.memo,
                chainSpecific: chainSpecific,
                swapPayload: .thorchainStagenet(tx.buildThorchainSwapPayload(
                    quote: quote,
                    provider: .thorchainStagenet
                )),
                approvePayload: buildApprovePayload(tx: tx),
                vault: vault
            )

        case .oneinch(let evmQuote, _), .lifi(let evmQuote, _, _), .kyberswap(let evmQuote, _):
            let payload = GenericSwapPayload(
                fromCoin: tx.fromCoin,
                toCoin: tx.toCoin,
                fromAmount: tx.amountInCoinDecimal,
                toAmountDecimal: tx.toAmountDecimal,
                quote: evmQuote,
                provider: quote.swapProviderId ?? .oneInch
            )
            return try await keysignFactory.buildTransfer(
                coin: tx.fromCoin,
                toAddress: evmQuote.tx.to,
                amount: tx.amountInCoinDecimal,
                memo: nil,
                chainSpecific: chainSpecific,
                swapPayload: .generic(payload),
                approvePayload: buildApprovePayload(tx: tx),
                vault: vault
            )
        }
    }
}
