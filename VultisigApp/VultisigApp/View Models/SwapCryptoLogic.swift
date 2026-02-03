//
//  SwapCryptoLogic.swift
//  VultisigApp
//
//  Created by Vultisig on 2025-02-03.
//

import SwiftUI
import BigInt
import WalletCore
import Mediator

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

    func loadFastVault(vault: Vault) async -> Bool {
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

    func baseAffiliateFee(tx: SwapTransaction) -> String {
        guard let quote = tx.quote else { return .empty }
        
        // 1. Get Affiliate Fee directly from quote
        // Determine which quote type we have and extract fee string
        var affiliateFeeString: String?
        var feeDecimals: Int = 8 // Default to 8 (THORChain standard)
        var feeCoin: Coin = tx.toCoin // Assumption based on existing pattern (fees in output asset)
        
        switch quote {
        case .thorchain(let q), .thorchainStagenet(let q), .mayachain(let q):
            affiliateFeeString = q.fees.affiliate
            // Verify if fee asset matches toCoin or fromCoin if needed, currently assuming toCoin as per SwapQuote.swift
        default:
            return .empty // Other providers might not have affiliate fees structured same way
        }
        
        guard let affiliateFeeString = affiliateFeeString,
              let feeAmount = Decimal(string: affiliateFeeString) else {
            return .empty
        }
        
        // 2. Convert to Fiat
        // If fee is in 'toCoin' units (e.g. 1e8)
        let feeDecimal = feeAmount / pow(10, feeDecimals)
        let fiatValue = feeCoin.fiat(decimal: feeDecimal)
        
        return fiatValue.formatToFiat(includeCurrencySymbol: true)
    }
    
    func swapFeeLabel(tx: SwapTransaction) -> String {
        // Calculate effective BPS from the quote vs input?
        // Or simply display the theoretical BPS if we can't reverse math it easily due to price fluctuations?
        // Agent Rule: "Percentage (from quote)"
        // ThorchainQuote doesn't have "affiliate_bps" field explicitly in the struct we saw?
        // Struct: `slippageBps`.
        // If not present, we can calculate: (AffiliateFeeFiat / InputFiat) * 10000
        
        guard let quote = tx.quote else { return "Swap Fee" }
        
        // Get affiliate fee fiat value
        let affiliateFeeString = baseAffiliateFee(tx: tx)
        guard !affiliateFeeString.isEmpty else { return "Swap Fee (0.00%)" }
       
        // We need raw numbers for math, reusing logic for efficiency
        var feeAmt: Decimal = 0
        switch quote {
        case .thorchain(let q), .thorchainStagenet(let q), .mayachain(let q):
            feeAmt = (Decimal(string: q.fees.affiliate) ?? 0) / pow(10, 8)
        default:
             break
        }
        
        // Calculate BPS: (Fee Amt / Expected Output Amount * ?? )
        // Usually Swap Fee is on INPUT.
        // Let's use currency values for comparsion to handle asset mismatch
        let feeFiat = tx.toCoin.fiat(decimal: feeAmt)
        
        let inputFiat = tx.fromCoin.fiat(decimal: tx.fromAmountDecimal)
        
        guard inputFiat > 0 else { return "Swap Fee" }
        
        let rate = (feeFiat / inputFiat)
        let percentage = rate * 100
        
        return "Swap Fee (\(String(format: "%.2f", NSDecimalNumber(decimal: percentage).doubleValue))%)"
    }
    
    func outboundFeeString(tx: SwapTransaction) -> String {
        guard let quote = tx.quote else { return .empty }
        
        var outboundFeeString: String?
        let feeDecimals: Int = 8 // Default to 8 (THORChain standard)
        let feeCoin: Coin = tx.toCoin // Outbound fee is in output asset
        
        switch quote {
        case .thorchain(let q), .thorchainStagenet(let q), .mayachain(let q):
            outboundFeeString = q.fees.outbound
        default:
            return .empty
        }
        
        guard let outboundFeeString = outboundFeeString,
              let feeAmount = Decimal(string: outboundFeeString) else {
            return .empty
        }
        
        let feeDecimal = feeAmount / pow(10, feeDecimals)
        let fiatValue = feeCoin.fiat(decimal: feeDecimal)
        
        return fiatValue.formatToFiat(includeCurrencySymbol: true)
    }

    func vultDiscountLabel(tx: SwapTransaction) -> String {
        return "VULT (-\(tx.vultDiscountBps) bps)"
    }
    
    func referralDiscountLabel(tx: SwapTransaction) -> String {
        return "Referral (-\(tx.referralDiscountBps) bps)"
    }

    func vultDiscount(tx: SwapTransaction) -> String {
        return getDiscountString(tx: tx, shareBps: tx.vultDiscountBps)
    }
    
    func referralDiscount(tx: SwapTransaction) -> String {
        return getDiscountString(tx: tx, shareBps: tx.referralDiscountBps)
    }

    private func getDiscountString(tx: SwapTransaction, shareBps: Int) -> String {
        guard shareBps > 0 else { return .empty }
        
        let totalSaving = calculateTotalSaving(tx: tx)
        
        // If Total Saving is ~0, return empty
        guard totalSaving > 0.01 else { return .empty }
        
        // Split if referral exists
        let totalDiscountBps = Decimal(tx.vultDiscountBps + tx.referralDiscountBps)
        guard totalDiscountBps > 0 else { return .empty }
        
        let share = Decimal(shareBps) / totalDiscountBps
        let saving = totalSaving * share
        
        let formattedCcy = saving.formatToFiat(includeCurrencySymbol: true)
        if saving < 0.01 && saving > 0 {
             return "-< " + "0.01".formatToFiat(includeCurrencySymbol: true) // Approximation
        }
        
        return "-" + formattedCcy
    }

    private func calculateTotalSaving(tx: SwapTransaction) -> Decimal {
        let inputFiat = tx.fromCoin.fiat(decimal: tx.fromAmountDecimal)
        
        // Theoretical Base Fee (0.50%)
        let baseFeeFiat = inputFiat * 0.0050
        
        // Actual Fee from Quote
        // Re-calculate local to avoid string parsing
        var actualFeeFiat: Decimal = 0
         if let quote = tx.quote {
            switch quote {
            case .thorchain(let q), .thorchainStagenet(let q), .mayachain(let q):
                 let feeAmt = (Decimal(string: q.fees.affiliate) ?? 0) / pow(10, 8)
                 actualFeeFiat = tx.toCoin.fiat(decimal: feeAmt)
            default: break
            }
        }
        
        // Total Saving
        return max(baseFeeFiat - actualFeeFiat, 0)
    }
    
    // MARK: - Price Impact
    
    func priceImpactString(tx: SwapTransaction) -> String {
        guard let impact = tx.quote?.priceImpact else { return .empty }
        // Price impact is usually negative (cost), but THORChain returns positive slippage bps.
        // We negate it for consistent display (e.g. -0.19%).
        let displayImpact = -impact
        let percentage = displayImpact * 100
        let formatter = NumberFormatter()
        formatter.numberStyle = .percent
        formatter.maximumFractionDigits = 2
        formatter.minimumFractionDigits = 2
        formatter.positivePrefix = "+"
        formatter.negativePrefix = "-"
        
        guard let string = formatter.string(from: NSDecimalNumber(decimal: percentage)) else { return .empty }
        
        if displayImpact > -0.01 { // Less than 1% slippage is usually considered "Good" or "Neutral"
            return "\(string) (Good)"
        } else {
            return "\(string) (High)"
        }
    }
    
    func priceImpactColor(tx: SwapTransaction) -> Color {
        guard let impact = tx.quote?.priceImpact else { return Theme.colors.textSecondary }
        let displayImpact = -impact
        
        if displayImpact > -0.01 {
            return Theme.colors.alertSuccess
        } else if displayImpact > -0.03 {
            return Theme.colors.alertWarning
        } else {
            return Theme.colors.alertError
        }
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
        
        var vultDiscountBps = vultTier?.bpsDiscount ?? 0
        var referralDiscountBps = THORChainSwaps.referredAffiliateFeeRateBp // Assuming user is referred if code exists, logic can be refined
        
        #if DEBUG
        // Mock values for UI verification in Debug mode
        if vultDiscountBps == 0 { vultDiscountBps = 30 } // Mock Gold Tier
        if referralDiscountBps == 0 { referralDiscountBps = 10 }
        #endif
        
        await MainActor.run {
            tx.vultDiscountBps = vultDiscountBps
            
            #if DEBUG
            // Always show referral discount in DEBUG for verification
            tx.referralDiscountBps = referralDiscountBps
            #else
            tx.referralDiscountBps = referredCode.isEmpty ? 0 : referralDiscountBps
            #endif
        }
        
        let quote = try await swapService.fetchQuote(
            amount: tx.fromAmountDecimal,
            fromCoin: tx.fromCoin,
            toCoin: tx.toCoin,
            isAffiliate: tx.isAffiliate,
            referredCode: referredCode,
            vultTierDiscount: vultDiscountBps
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
