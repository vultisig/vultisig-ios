//
//  TonPublicAPI.swift
//  VultisigApp
//

import Foundation

/// Endpoints on the public TonAPI host. Kept separate from `TonAPI`, which
/// targets the Vultisig proxy at `api.vultisig.com`. The emulator endpoint is
/// served exclusively by `tonapi.io` so we hit it directly to mirror the
/// Vultisig Windows client.
enum TonPublicAPI: TargetType {
    case emulateEvent(boc: String)
    /// tonapi.io computed staking-pool info (APY, name, min stake). `address`
    /// is the nominator-pool contract address.
    case stakingPool(address: String)

    private static let host: URL = {
        guard let url = URL(string: "https://tonapi.io") else {
            preconditionFailure("Invalid TonPublicAPI base URL literal")
        }
        return url
    }()

    var baseURL: URL { Self.host }

    var path: String {
        switch self {
        case .emulateEvent:
            return "/v2/events/emulate"
        case .stakingPool(let address):
            return "/v2/staking/pool/\(address)"
        }
    }

    var method: HTTPMethod {
        switch self {
        case .emulateEvent:
            return .post
        case .stakingPool:
            return .get
        }
    }

    var task: HTTPTask {
        switch self {
        case .emulateEvent(let boc):
            // Skip signature verification — we feed in an unsigned BOC built
            // for emulation only (see `TonExternalMessageEmulator`).
            // `TonEmulateRequest` is a single-string struct; encoding a
            // String can never fail, so a thrown error here would signal a
            // programmer error worth crashing on rather than masking with
            // an empty body.
            let body: Data
            do {
                body = try JSONEncoder().encode(TonEmulateRequest(boc: boc))
            } catch {
                preconditionFailure("Failed to encode TonEmulateRequest: \(error)")
            }
            return .requestCompositeData(
                bodyData: body,
                urlParameters: ["ignore_signature_check": "true"]
            )
        case .stakingPool:
            return .requestPlain
        }
    }

    var headers: [String: String]? {
        ["Content-Type": "application/json"]
    }
}

private struct TonEmulateRequest: Encodable {
    let boc: String
}

/// Response from tonapi.io `GET /v2/staking/pool/{address}`. `apy` is a
/// percentage value (e.g. `13.27` means 13.27%); callers divide by 100 to get
/// the fraction the staking UI expects. Fields are optional so a partial /
/// changed response degrades gracefully rather than dropping the position.
struct TonStakingPoolResponse: Decodable {
    let pool: TonStakingPoolInfo?
}

struct TonStakingPoolInfo: Decodable {
    let address: String?
    let name: String?
    let apy: Double?
    let minStake: Int64?

    private enum CodingKeys: String, CodingKey {
        case address, name, apy
        case minStake = "min_stake"
    }
}
