//
//  SwapReworkDemo.swift
//  VultisigApp
//
//  Debug-only fictional fixtures for every reworked swap state, selected with
//  `-swapReworkDemo <scenario>`. Amounts are invented and consistent with each
//  other (the fee rows add up to the total, the total to what leaves the
//  vault). Demo mode never builds a transaction, so nothing here can reach the
//  review sheet or signing.
//

#if DEBUG
import Foundation

enum SwapReworkDemoScenario: String, CaseIterable {
    case empty
    case quote
    case fees
    case routes
    case maxGas
    case picker
    case unverified
    case approval
    case steps
    case overBalance
    case noGas
    case halted
    case noRoute
    case priceMoved
    case expired
    case tracker
    case success
}

enum SwapReworkDemo {
    static let eth = SwapReworkAsset(coinID: "demo-eth", ticker: "ETH", logo: "eth", chainLogo: nil, chainName: "Ethereum", isNative: true)
    static let btc = SwapReworkAsset(coinID: "demo-btc", ticker: "BTC", logo: "btc", chainLogo: nil, chainName: "Bitcoin", isNative: true)
    static let usdc = SwapReworkAsset(coinID: "demo-usdc", ticker: "USDC", logo: "usdc", chainLogo: "eth", chainName: "Ethereum", isNative: false)
    static let rune = SwapReworkAsset(coinID: "demo-rune", ticker: "RUNE", logo: "rune", chainLogo: nil, chainName: "THORChain", isNative: true)
    static let sol = SwapReworkAsset(coinID: "demo-sol", ticker: "SOL", logo: "solana", chainLogo: nil, chainName: "Solana", isNative: true)
    static let usdt = SwapReworkAsset(coinID: "demo-usdt", ticker: "USDT", logo: "usdt", chainLogo: "eth", chainName: "Ethereum", isNative: false)
    static let fakeUSDC = SwapReworkAsset(coinID: "demo-fake-usdc", ticker: "USDC", logo: "usdc", chainLogo: "eth", chainName: "Ethereum", isNative: false)

    static let fakeUSDCContract = "0x9f3a51c0e2b84d7a6f0c3e9d1b2a4c5d6e7fc41b"
    static let realUSDCContract = "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48"

    // MARK: - Form

    /// 0.5 ETH at $1,956.40 = $978.20. Gas 0.00043 ETH = $0.84. THORChain
    /// payout $2.86, Vultisig 0.30% (Gold) $2.93 against $4.89 list.
    /// Fees $0.84 + $2.86 + $2.93 = $6.63. Receive 0.0140218 BTC = $972.41.
    /// All-in: (972.41 - 979.04) / 979.04 = -0.68%.
    static var ethToBtcFees: SwapFeeBreakdown {
        SwapFeeBreakdown(.init(
            networkFiat: dec("0.84"), networkCrypto: "0.00043 ETH",
            protocolFiat: dec("2.86"),
            vultisigNetFiat: dec("2.93"), vultisigListFiat: dec("4.89"),
            listBps: 50, tierDiscountBps: 20, tier: .gold,
            vultisigIncludedInRate: false,
            payFiat: dec("978.20"), receiveFiat: dec("972.41")
        ))
    }

    static var ethToBtcRoutes: [SwapRankedRoute] {
        SwapRouteRanking.rank([
            SwapRouteOption(id: "THORChain", providerName: "THORChain", providerLogo: SwapProviderKind.thorchain.providerLogo, receivedAmount: dec("0.0140218"), receivedFiat: dec("972.41"), feesFiat: dec("5.79"), etaSeconds: 600),
            SwapRouteOption(id: "SwapKit", providerName: "SwapKit", providerLogo: SwapProviderKind.swapkit.providerLogo, receivedAmount: dec("0.013989"), receivedFiat: dec("970.14"), feesFiat: dec("8.06"), etaSeconds: 390),
            SwapRouteOption(id: "LI.FI", providerName: "LI.FI", providerLogo: SwapProviderKind.lifi.providerLogo, receivedAmount: dec("0.0139412"), receivedFiat: dec("966.82"), feesFiat: dec("9.10"), etaSeconds: nil)
        ])
    }

    static func feeRows(_ breakdown: SwapFeeBreakdown, approval: Bool = false) -> SwapReworkFeeRows {
        SwapReworkFeeRows(
            breakdown: breakdown,
            networkLabel: String(format: "swapReworkGas".localized, "Ethereum"),
            networkCrypto: breakdown.input.networkCrypto,
            protocolLabel: breakdown.input.protocolFiat > 0 ? String(format: "swapReworkProtocolFee".localized, "THORChain") : nil,
            tierName: breakdown.input.tier?.name,
            minimumReceived: approval ? "0.504311 ETH" : "0.0138816 BTC",
            slippageText: "1%",
            priceImpactText: "0.15%",
            leavesVaultText: approval ? "1,000 USDC + 0.00108 ETH · $1,002.12" : "0.5 + 0.00043 ETH · $979.04"
        )
    }

    static var baseQuote: SwapReworkFormState {
        let fees = ethToBtcFees
        let routes = ethToBtcRoutes
        return SwapReworkFormState(
            pay: eth, receive: btc,
            amountText: "0.5",
            payFiatText: "$978.20",
            balanceText: "1.2841 ETH",
            gasReserveText: nil,
            showsMaxChip: true,
            receiveAmountText: "0.0140218",
            receiveFiatText: "≈ $972.41",
            allInText: fees.allInChangeText.map { String(format: "swapReworkAllIn".localized, $0) },
            isReceiveIndicative: false,
            isQuoteLoading: false,
            highlightsReceive: false,
            route: SwapReworkRouteSummary(providerName: "THORChain", providerLogo: SwapProviderKind.thorchain.providerLogo, tag: .bestPrice, etaText: SwapReworkFormat.eta(seconds: 600), feesText: fees.displayTotalFiat.formatToFiat(), isSelectable: true),
            routes: routes,
            selectedRouteID: "THORChain",
            timer: SwapReworkQuoteTimer(state: .live(secondsLeft: 47), fraction: 47.0 / 59),
            fees: feeRows(fees),
            approval: nil,
            issue: nil,
            cta: .review,
            isCTAEnabled: true
        )
    }

    // swiftlint:disable:next cyclomatic_complexity function_body_length
    static func formState(for scenario: SwapReworkDemoScenario) -> SwapReworkFormState {
        var state = baseQuote
        switch scenario {
        case .quote, .fees, .routes, .picker, .unverified, .tracker, .success:
            break
        case .empty:
            state.amountText = ""
            state.payFiatText = "$0.00"
            state.receiveAmountText = "0"
            state.receiveFiatText = ""
            state.allInText = nil
            state.route = nil
            state.routes = []
            state.fees = nil
            state.timer = SwapReworkQuoteTimer(state: .idle, fraction: 0)
            state.cta = .enterAmount
            state.isCTAEnabled = false
        case .maxGas:
            state.amountText = "1.28367"
            state.payFiatText = "$2,511.37"
            state.gasReserveText = "0.00043 ETH · $0.84"
            state.receiveAmountText = "~0.0359"
            state.receiveFiatText = "≈ $2,489.10"
            state.isReceiveIndicative = true
            state.isQuoteLoading = true
            state.allInText = nil
            state.route = nil
            state.fees = nil
            state.timer = SwapReworkQuoteTimer(state: .refreshing, fraction: 0)
            state.cta = .loading
            state.isCTAEnabled = false
        case .approval, .steps:
            let fees = SwapFeeBreakdown(.init(
                networkFiat: dec("2.12"), networkCrypto: "0.00108 ETH",
                protocolFiat: 0,
                vultisigNetFiat: dec("3.00"), vultisigListFiat: dec("5.00"),
                listBps: 50, tierDiscountBps: 20, tier: .gold,
                vultisigIncludedInRate: false,
                payFiat: dec("1000"), receiveFiat: dec("996.60")
            ))
            state.pay = usdc
            state.receive = eth
            state.amountText = "1000"
            state.payFiatText = "$1,000.00"
            state.balanceText = "2,410.55 USDC"
            state.receiveAmountText = "0.509405"
            state.receiveFiatText = "≈ $996.60"
            state.allInText = fees.allInChangeText.map { String(format: "swapReworkAllIn".localized, $0) }
            state.route = SwapReworkRouteSummary(providerName: "1inch", providerLogo: SwapProviderKind.oneInch.providerLogo, tag: .bestPrice, etaText: SwapReworkFormat.eta(seconds: 30), feesText: fees.displayTotalFiat.formatToFiat(), isSelectable: false)
            state.routes = []
            state.fees = feeRows(fees, approval: true)
            state.approval = SwapReworkApproval(ticker: "USDC", amountText: "1,000", spenderName: "1inch")
        case .overBalance:
            state.amountText = "2.5"
            state.payFiatText = "$4,891.00"
            state.receiveAmountText = "0.0701093"
            state.receiveFiatText = "≈ $4,862.05"
            state.allInText = allIn(pay: "4891.00", gas: "0.84", receive: "4862.05")
            state.issue = .overBalance
            state.cta = .insufficient(ticker: "ETH")
            state.isCTAEnabled = false
        case .noGas:
            state = formState(for: .approval)
            state.issue = .notEnoughGas
            state.cta = .fixGas(ticker: "ETH")
            state.isCTAEnabled = false
        case .halted:
            state.issue = .tradingHalted(providerName: "THORChain")
            state.receiveAmountText = "0.013989"
            state.receiveFiatText = "≈ $970.14"
            state.allInText = allIn(pay: "978.20", gas: "0.84", receive: "970.14")
            state.route = SwapReworkRouteSummary(providerName: "SwapKit", providerLogo: SwapProviderKind.swapkit.providerLogo, tag: nil, etaText: SwapReworkFormat.eta(seconds: 390), feesText: "$8.90", isSelectable: false)
            state.cta = .reviewWith(providerName: "SwapKit")
        case .noRoute:
            state.receive = SwapReworkAsset(coinID: "demo-doge", ticker: "DOGE", logo: "doge", chainLogo: nil, chainName: "Dogecoin", isNative: true)
            state.pay = SwapReworkAsset(coinID: "demo-snek", ticker: "SNEK", logo: "snek", chainLogo: "ada", chainName: "Cardano", isNative: false)
            state.amountText = "12000"
            state.payFiatText = "$31.20"
            state.balanceText = "48,200 SNEK"
            state.receiveAmountText = "0"
            state.receiveFiatText = ""
            state.allInText = nil
            state.route = nil
            state.routes = []
            state.fees = nil
            state.timer = SwapReworkQuoteTimer(state: .idle, fraction: 0)
            state.issue = .noRoute
            state.cta = .chooseAnotherCoin
        case .priceMoved:
            state.receiveAmountText = "0.0139657"
            state.receiveFiatText = "≈ $968.52"
            state.allInText = allIn(pay: "978.20", gas: "0.84", receive: "968.52")
            state.highlightsReceive = true
            state.issue = .priceMoved(.worsened(change: dec("0.004")))
            state.cta = .confirmNewAmount
        case .expired:
            state.timer = SwapReworkQuoteTimer(state: .expired, fraction: 0)
            state.issue = .quoteExpired
            state.cta = .getNewQuote
        }
        return state
    }

    static func gasShortfallText(for scenario: SwapReworkDemoScenario) -> String? {
        guard scenario == .noGas else { return nil }
        return String(format: "swapReworkGasShortfall".localized, "0.0002 ETH", "0.00088 ETH", "$1.72")
    }

    // MARK: - Picker

    static var pickerRows: [SwapReworkPickerRow] {
        [
            row(eth, balance: "1.2841", fiat: "2512.21"),
            row(usdc, contract: realUSDCContract, balance: "2,410.55", fiat: "2410.55"),
            row(btc, balance: "0.0213", fiat: "1477.16"),
            row(rune, balance: "312.4", fiat: "443.61"),
            row(usdt, contract: "0xdAC17F958D2ee523a2206206994597C13D831ec7", balance: "120", fiat: "120.00"),
            SwapReworkPickerRow(
                asset: fakeUSDC, contract: fakeUSDCContract, balanceText: "5,000", fiatText: "",
                fiatValue: 0, trust: .unverified(genuineContract: realUSDCContract)
            )
        ]
    }

    static let recentIDs = ["demo-eth", "demo-btc", "demo-usdc", "demo-rune"]

    private static func row(_ asset: SwapReworkAsset, contract: String = "", balance: String, fiat: String) -> SwapReworkPickerRow {
        let value = dec(fiat)
        return SwapReworkPickerRow(
            asset: asset, contract: contract, balanceText: balance,
            fiatText: value.formatToFiat(), fiatValue: value, trust: .verified
        )
    }

    // MARK: - Tracker / success

    static var tracker: SwapReworkTrackerState {
        SwapReworkTrackerState(
            pay: eth, receive: btc,
            receiveAmountText: "0.0140218 BTC",
            providerName: "THORChain",
            stages: SwapTrackerModel.stages(status: .pending, isCrossChain: true),
            phase: .inProgress,
            remainingText: SwapTrackerModel.remainingRange(elapsed: 120, estimate: 600)
                .map { String(format: "swapReworkUsuallyMore".localized, $0.lowerBound, $0.upperBound) },
            sentDetail: "0.5 ETH · 0x8a1f…07c3",
            swappedDetail: "ETH → BTC",
            receivedDetail: "0.0140218 BTC → bc1q…7xk9",
            isCrossChain: true
        )
    }

    static var success: SwapReworkSuccessState {
        let outcome = SwapOutcome(quoted: dec("0.0140218"), delivered: dec("0.0140237"))
        let sats = NSDecimalNumber(decimal: outcome.differenceInBaseUnits(decimals: 8)).intValue
        return SwapReworkSuccessState(
            receive: btc,
            vaultName: "Main vault",
            isDeliveredKnown: true,
            deliveredText: "+0.0140237 BTC",
            deliveredFiatText: "≈ $972.54",
            quotedText: "0.0140218 BTC",
            outcome: outcome,
            differenceText: "\(sats > 0 ? "+" : "")\(sats) sats · \(outcome.differenceShareText ?? "")",
            tookText: "11 min",
            feesText: "$6.63",
            tierName: "Gold",
            tierSavedText: "$1.96"
        )
    }

    /// The all-in caption for a fixture, from the same breakdown math the live
    /// form uses, so every demo number is consistent with its amounts.
    private static func allIn(pay: String, gas: String, receive: String) -> String? {
        SwapFeeBreakdown(.init(
            networkFiat: dec(gas), networkCrypto: "", protocolFiat: 0,
            vultisigNetFiat: 0, vultisigListFiat: 0, listBps: 50, tierDiscountBps: 0, tier: nil,
            vultisigIncludedInRate: false, payFiat: dec(pay), receiveFiat: dec(receive)
        )).allInChangeText.map { String(format: "swapReworkAllIn".localized, $0) }
    }

    private static func dec(_ value: String) -> Decimal {
        Decimal(string: value, locale: Locale(identifier: "en_US_POSIX")) ?? 0
    }
}
#endif
