//
//  SwapProviderId.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 12/08/2025.
//

import Foundation

/// Identifier carried in `OneInchSwapPayload.provider` (the wire-format string)
/// and `GenericSwapPayload.provider` (Swift-side enum). Decode is **tolerant**:
/// unknown wire values land in `.unknown(raw)` so a peer device running an
/// older iOS version can still cosign a payload tagged with a provider name it
/// doesn't recognize — the verify screen falls back to the raw provider string
/// instead of throwing during JSON/proto decode.
///
/// `.unknown` carries the original String so re-encoding round-trips
/// losslessly. Treat it as "I don't recognize this provider but I can still
/// display the bytes I received."
enum SwapProviderId: Codable, Hashable {
    case oneInch
    case lifi
    case kyberSwap
    case swapkit
    case jupiter
    case unknown(String)

    /// Wire-format string. Matches the value 1inch / Kyber / LiFi / SwapKit
    /// emit in `OneInchSwapPayload.provider`. Lossless for `.unknown(raw)`.
    var rawValue: String {
        switch self {
        case .oneInch: return "1inch"
        case .lifi: return "li.fi"
        case .kyberSwap: return "kyber"
        case .swapkit: return "swapkit"
        case .jupiter: return "jupiter"
        case .unknown(let raw): return raw
        }
    }

    /// Display name for the verify screen. Unknown providers show their raw
    /// wire value so the user has *something* to identify the swap by.
    var name: String {
        switch self {
        case .oneInch: return "1Inch"
        case .kyberSwap: return "KyberSwap"
        case .lifi: return "LI.FI"
        case .swapkit: return "SwapKit"
        case .jupiter: return "Jupiter"
        case .unknown(let raw): return raw
        }
    }

    /// Tolerant decoder: maps known wire values to typed cases, everything
    /// else lands in `.unknown(raw)`. Never throws on a malformed-provider
    /// string. The cosigning peer keeps signing — only the display tag
    /// degrades to the raw value.
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        self = Self.from(rawValue: raw)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    /// Synchronous tolerant constructor — same logic the proto-mapping path
    /// (`KeysignMessage+ProtoMappable.swift`) uses to bridge the wire
    /// `provider` string into the Swift enum.
    static func from(rawValue: String) -> SwapProviderId {
        switch rawValue {
        case "1inch": return .oneInch
        case "li.fi": return .lifi
        case "kyber": return .kyberSwap
        case "swapkit": return .swapkit
        case "jupiter": return .jupiter
        default: return .unknown(rawValue)
        }
    }
}
