//
//  HyperliquidInfoModels.swift
//  VultisigApp
//
//  Wire models for https://api.hyperliquid.xyz/info. Hyperliquid
//  sends every number as a decimal string; `HLDecimal` keeps that precision.
//

import Foundation

/// A decimal that Hyperliquid encodes as a JSON string ("71391.0").
struct HLDecimal: Codable, Hashable, Sendable, Comparable {
    let value: Decimal

    init(_ value: Decimal) { self.value = value }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let text = try? container.decode(String.self) {
            guard let parsed = Decimal(string: text, locale: Locale(identifier: "en_US_POSIX")) else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "Not a decimal: \(text)")
            }
            value = parsed
        } else {
            value = Decimal(try container.decode(Double.self))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(HLWireFormat.decimalString(value))
    }

    static func < (lhs: HLDecimal, rhs: HLDecimal) -> Bool { lhs.value < rhs.value }
}

// MARK: - metaAndAssetCtxs

struct HLAssetMeta: Codable, Hashable, Sendable {
    let name: String
    let szDecimals: Int
    let maxLeverage: Int
    let onlyIsolated: Bool?
    let isDelisted: Bool?
    let marginTableId: Int?
}

struct HLMarginTier: Codable, Hashable, Sendable {
    let lowerBound: HLDecimal
    let maxLeverage: Int
}

struct HLMarginTable: Codable, Hashable, Sendable {
    let description: String?
    let marginTiers: [HLMarginTier]
}

/// `meta.marginTables` is a list of `[id, table]` pairs.
struct HLMarginTableEntry: Decodable, Hashable, Sendable {
    let id: Int
    let table: HLMarginTable

    init(id: Int, table: HLMarginTable) {
        self.id = id
        self.table = table
    }

    init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        id = try container.decode(Int.self)
        table = try container.decode(HLMarginTable.self)
    }
}

struct HLMeta: Decodable, Hashable, Sendable {
    let universe: [HLAssetMeta]
    let marginTables: [HLMarginTableEntry]?

    init(universe: [HLAssetMeta], marginTables: [HLMarginTableEntry]? = nil) {
        self.universe = universe
        self.marginTables = marginTables
    }
}

/// `frontendOpenOrders`: open orders with trigger / TP-SL detail.
struct HLFrontendOrder: Codable, Hashable, Sendable, Identifiable {
    let coin: String
    let oid: Int64
    let side: String
    let sz: HLDecimal
    let limitPx: HLDecimal
    let triggerPx: HLDecimal?
    let isTrigger: Bool?
    let isPositionTpsl: Bool?
    let reduceOnly: Bool?
    let orderType: String?
    let timestamp: Int64

    var id: Int64 { oid }
    var isBuy: Bool { side == "B" }
    var isStopLoss: Bool { isTrigger == true && (orderType ?? "").lowercased().contains("stop") }
    var isTakeProfit: Bool { isTrigger == true && (orderType ?? "").lowercased().contains("take profit") }
}

/// `spotClearinghouseState`, read for unified / portfolio-margin accounts.
struct HLSpotBalance: Codable, Hashable, Sendable {
    let coin: String
    let total: HLDecimal
    let hold: HLDecimal
}

struct HLSpotClearinghouseState: Codable, Hashable, Sendable {
    let balances: [HLSpotBalance]
}

struct HLAssetContext: Codable, Hashable, Sendable {
    let funding: HLDecimal
    let openInterest: HLDecimal
    let prevDayPx: HLDecimal
    let dayNtlVlm: HLDecimal
    let markPx: HLDecimal
    let midPx: HLDecimal?
    let oraclePx: HLDecimal
}

/// `[meta, [assetCtx]]`, a heterogeneous JSON array.
struct HLMetaAndAssetContexts: Decodable, Sendable {
    let meta: HLMeta
    let contexts: [HLAssetContext]

    init(meta: HLMeta, contexts: [HLAssetContext]) {
        self.meta = meta
        self.contexts = contexts
    }

    init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        meta = try container.decode(HLMeta.self)
        contexts = try container.decode([HLAssetContext].self)
    }
}

// MARK: - candleSnapshot

enum HLCandleInterval: String, CaseIterable, Sendable {
    case oneMinute = "1m"
    case fiveMinutes = "5m"
    case fifteenMinutes = "15m"
    case oneHour = "1h"
    case fourHours = "4h"
    case oneDay = "1d"
}

struct HLCandle: Codable, Hashable, Sendable {
    let openTimeMs: Int64
    let open: HLDecimal
    let close: HLDecimal
    let high: HLDecimal
    let low: HLDecimal
    let volume: HLDecimal

    enum CodingKeys: String, CodingKey {
        case openTimeMs = "t"
        case open = "o"
        case close = "c"
        case high = "h"
        case low = "l"
        case volume = "v"
    }

    var openTime: Date { Date(timeIntervalSince1970: TimeInterval(openTimeMs) / 1000) }
}

// MARK: - clearinghouseState

struct HLMarginSummary: Codable, Hashable, Sendable {
    let accountValue: HLDecimal
    let totalNtlPos: HLDecimal
    let totalRawUsd: HLDecimal
    let totalMarginUsed: HLDecimal
}

struct HLLeverage: Codable, Hashable, Sendable {
    let type: String
    let value: Int

    var isCross: Bool { type == "cross" }
}

struct HLPosition: Codable, Hashable, Sendable {
    let coin: String
    /// Signed size: positive long, negative short.
    let szi: HLDecimal
    let leverage: HLLeverage
    let entryPx: HLDecimal?
    let positionValue: HLDecimal
    let unrealizedPnl: HLDecimal
    let returnOnEquity: HLDecimal
    let liquidationPx: HLDecimal?
    let marginUsed: HLDecimal
    let maxLeverage: Int?
    /// Positive = paid, negative = received.
    let cumFunding: HLCumFunding?

    var isLong: Bool { szi.value > 0 }
}

struct HLCumFunding: Codable, Hashable, Sendable {
    let sinceOpen: HLDecimal
}

struct HLAssetPosition: Codable, Hashable, Sendable {
    let type: String
    let position: HLPosition
}

struct HLClearinghouseState: Codable, Hashable, Sendable {
    let marginSummary: HLMarginSummary
    let crossMarginSummary: HLMarginSummary
    let crossMaintenanceMarginUsed: HLDecimal
    let withdrawable: HLDecimal
    let assetPositions: [HLAssetPosition]
    let time: Int64
}

// MARK: - openOrders / userFills

struct HLOpenOrder: Codable, Hashable, Sendable, Identifiable {
    let coin: String
    let limitPx: HLDecimal
    let oid: Int64
    /// "B" bid (buy) or "A" ask (sell).
    let side: String
    let sz: HLDecimal
    let timestamp: Int64

    var id: Int64 { oid }
    var isBuy: Bool { side == "B" }
}

/// `userNonFundingLedgerUpdates`: deposits, withdrawals and transfers.
struct HLLedgerUpdate: Decodable, Hashable, Sendable {
    struct Delta: Decodable, Hashable, Sendable {
        let type: String
        let usdc: HLDecimal?
        /// Transfers: who sent it and where it went (`internalTransfer`, `send`).
        var user: String?
        var destination: String?
        /// Account-class transfers: true when the USDC moved into perps.
        var toPerp: Bool?
    }

    let time: Int64
    let hash: String
    let delta: Delta

    /// Whether USDC left `account`, from the event fields rather than the type
    /// name: an outgoing internal transfer does not say "withdraw".
    func isOutgoing(from account: String) -> Bool {
        if let toPerp = delta.toPerp { return !toPerp }
        if let user = delta.user, delta.destination != nil { return user.lowercased() == account.lowercased() }
        return delta.type.lowercased().contains("withdraw")
    }
}

/// `userFunding`: one funding payment on one position.
struct HLFundingPayment: Decodable, Hashable, Sendable {
    struct Delta: Decodable, Hashable, Sendable {
        let coin: String
        let usdc: HLDecimal
    }

    let time: Int64
    let delta: Delta
}

struct HLFill: Codable, Hashable, Sendable, Identifiable {
    let coin: String
    let px: HLDecimal
    let sz: HLDecimal
    let side: String
    let time: Int64
    let dir: String
    let closedPnl: HLDecimal
    let fee: HLDecimal
    let tid: Int64
    let oid: Int64

    var id: Int64 { tid }
}
