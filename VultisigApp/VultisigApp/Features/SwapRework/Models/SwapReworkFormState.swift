//
//  SwapReworkFormState.swift
//  VultisigApp
//
//  Everything the reworked swap form renders, as plain values. Built from the
//  live `SwapDetailsViewModel` by `SwapReworkViewModel`, or from a fictional
//  fixture in debug demo mode, so the views never read a quote or a SwiftData
//  model directly.
//

import Foundation

struct SwapReworkAsset: Equatable {
    let coinID: String
    let ticker: String
    let logo: String
    let chainLogo: String?
    let chainName: String
    let isNative: Bool
}

struct SwapReworkRouteSummary: Equatable {
    let providerName: String
    let providerLogo: String?
    let tag: SwapRouteTag?
    /// "8-12 min", empty when the provider gives no time.
    let etaText: String
    /// "$6.63", empty until fees land.
    let feesText: String
    let isSelectable: Bool
}

struct SwapReworkFeeRows: Equatable {
    let breakdown: SwapFeeBreakdown
    /// "Ethereum gas" or "Ethereum gas (allow + swap)".
    let networkLabel: String
    /// "0.00043 ETH"
    let networkCrypto: String
    /// "Approval gas (1 tx)", nil when no approval leg is known to be needed.
    var approvalLabel: String?
    /// "THORChain swap + payout", nil when the route has no protocol fee.
    let protocolLabel: String?
    let tierName: String?
    let minimumReceived: String
    let slippageText: String
    let priceImpactText: String
    /// "0.5 + 0.00043 ETH · $979.04"
    let leavesVaultText: String
}

struct SwapReworkApproval: Equatable {
    let ticker: String
    let amountText: String
    let spenderName: String
    /// Approve transactions ahead of the swap from the allowance check: 1, or
    /// 2 when the token needs its allowance reset first. Nil until it answers.
    var legs: Int?
}

struct SwapReworkQuoteTimer: Equatable {
    let state: SwapQuoteClock.State
    let fraction: Double
}

enum SwapReworkCTA: Equatable {
    case enterAmount
    case loading
    case review
    case reviewWith(providerName: String)
    case confirmNewAmount
    case getNewQuote
    case chooseAnotherCoin
    case insufficient(ticker: String)
    /// Raise the amount to the provider's stated minimum ("Use 0.0035 ETH").
    case useMinimum(amountText: String)
    case fixGas(ticker: String)
}

struct SwapReworkFeeWarning: Equatable {
    /// "7.2%"
    let shareText: String
    let gasPart: Double
    /// The protocol's outbound fee, when the route has one, and its bar part.
    var protocolPart: Double = 0
    var protocolText: String?
    let gasText: String
    let vultisigText: String
    let receiveText: String
    /// "At 200 USDC this would be 1.0%."
    let atScaleText: String?
    let gasLabel: String
}

struct SwapReworkFormState: Equatable {
    var pay: SwapReworkAsset
    var receive: SwapReworkAsset
    /// Raw keypad text, "." decimals.
    var amountText: String
    var payFiatText: String
    var balanceText: String
    /// "0.00043 ETH · $0.84" once Max has kept gas behind.
    var gasReserveText: String?
    var showsMaxChip: Bool

    var receiveAmountText: String
    var receiveFiatText: String
    /// "-0.68% all-in"
    var allInText: String?
    var isReceiveIndicative: Bool
    var isQuoteLoading: Bool
    var highlightsReceive: Bool

    var route: SwapReworkRouteSummary?
    var routes: [SwapRankedRoute]
    /// "Ethereum gas $0.84": the source gas every route pays, for the sheet.
    var routeGasNote: String?
    /// The fee coin, for "Add ETH" and its sheet.
    var feeTicker: String = ""
    /// "0.00088 ETH ($1.72)": what the add-gas sheet asks for.
    var gasToAddText: String?
    var selectedRouteID: String?
    var timer: SwapReworkQuoteTimer
    var fees: SwapReworkFeeRows?
    var approval: SwapReworkApproval?
    var issue: SwapReworkIssue?
    /// "-85.99%": fees and impact take a large share. Shown, never blocking.
    var valueLossText: String?
    /// The provider's minimum when it states one, for the "too small" card.
    var minimumText: String?
    /// The fee warning's numbers (share, gas part, at 10x), when it shows.
    var feeWarning: SwapReworkFeeWarning?
    var cta: SwapReworkCTA
    var isCTAEnabled: Bool

    var isEmpty: Bool { amountText.isEmpty }
}
