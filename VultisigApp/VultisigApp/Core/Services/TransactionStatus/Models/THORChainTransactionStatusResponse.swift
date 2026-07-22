//
//  THORChainTransactionStatusResponse.swift
//  VultisigApp
//
//  Created by Claude on 27/01/2025.
//

import Foundation

// Midgard Actions API Response
struct THORChainActionsResponse: Codable {
    let actions: [MidgardAction]
    let count: String
}

struct MidgardAction: Codable {
    let pools: [String]
    let type: String
    let status: String  // "success", "pending", "refund"
    let `in`: [MidgardTransaction]
    let out: [MidgardTransaction]
    let date: String
    let height: String
    let metadata: MidgardActionMetadata?
}

struct MidgardTransaction: Codable {
    let txID: String
    let address: String?
    let coins: [MidgardCoin]?

    enum CodingKeys: String, CodingKey {
        case txID
        case address
        case coins
    }
}

struct MidgardCoin: Codable {
    let asset: String
    let amount: String
}

struct MidgardActionMetadata: Codable {
    let refund: RefundMetadata?
    let failed: FailedMetadata?
}

struct RefundMetadata: Codable {
    let reason: String?
    /// Quoted on the wire — see `decodeMidgardNumberIfPresent`.
    let code: String?
    let memo: String?
    let networkFees: [MidgardCoin]?

    enum CodingKeys: String, CodingKey {
        case reason
        case code
        case memo
        case networkFees
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        reason = try container.decodeIfPresent(String.self, forKey: .reason)
        code = try container.decodeMidgardNumberIfPresent(forKey: .code)
        memo = try container.decodeIfPresent(String.self, forKey: .memo)
        networkFees = try container.decodeIfPresent([MidgardCoin].self, forKey: .networkFees)
    }
}

struct FailedMetadata: Codable {
    let reason: String?
    /// Quoted on the wire — see `decodeMidgardNumberIfPresent`.
    let code: String?
    let memo: String?

    enum CodingKeys: String, CodingKey {
        case reason
        case code
        case memo
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        reason = try container.decodeIfPresent(String.self, forKey: .reason)
        code = try container.decodeMidgardNumberIfPresent(forKey: .code)
        memo = try container.decodeIfPresent(String.self, forKey: .memo)
    }
}

private extension KeyedDecodingContainer {
    /// ⚠️ Midgard quotes its numerics. Every other number in this payload —
    /// `count`, `height`, `date`, coin `amount` — arrives as a string, and so
    /// does a failure code: `"code": "99"`. Typing it `Int` did not merely lose
    /// one field, it threw, and a throw anywhere aborts the decode of the WHOLE
    /// actions page — so a single failed action stopped status polling for every
    /// transaction in it.
    ///
    /// Kept as a `String` because that is the wire form and the app only ever
    /// displays it. Decoded leniently anyway: Midgard's schema calls these
    /// integers even though it serialises strings, and given what one type
    /// mismatch costs here, accepting a bare number as well is worth four lines.
    func decodeMidgardNumberIfPresent(forKey key: Key) throws -> String? {
        guard contains(key), try !decodeNil(forKey: key) else { return nil }
        if let string = try? decode(String.self, forKey: key) {
            return string
        }
        if let number = try? decode(Int64.self, forKey: key) {
            return String(number)
        }
        throw DecodingError.typeMismatch(
            String.self,
            DecodingError.Context(
                codingPath: codingPath + [key],
                debugDescription: "Expected a quoted or bare number"
            )
        )
    }
}
