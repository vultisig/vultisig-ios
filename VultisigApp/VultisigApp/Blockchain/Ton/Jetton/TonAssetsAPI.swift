//
//  TonAssetsAPI.swift
//  VultisigApp
//

import Foundation

/// Tonkeeper's community-reviewed jetton whitelist — the list every major TON
/// wallet treats as its verified tier. Compiled from the repo's YAML sources on
/// every merge and served as a static file.
///
/// Host is injectable so tests drive the fetch without reaching the network.
struct TonAssetsAPI: TargetType {
    static let defaultHost = URL(string: "https://raw.githubusercontent.com")!

    let host: URL

    init(host: URL = TonAssetsAPI.defaultHost) {
        self.host = host
    }

    var baseURL: URL { host }
    var path: String { "/tonkeeper/ton-assets/main/jettons.json" }
    var method: HTTPMethod { .get }
    var task: HTTPTask { .requestPlain }
    var headers: [String: String]? { ["Accept": "application/json"] }
}

/// One entry of `jettons.json`, narrowed to the fields the registry uses.
///
/// Everything a jetton can self-assert about its own trustworthiness is
/// deliberately absent: being listed at all is the signal, and the tier is
/// assigned in code (see the trust-boundary note on `TokenVerification`).
struct TonAssetsJetton: Decodable, Sendable {
    let address: String
    let symbol: String?
    let name: String?
    let decimals: Int?
    /// Present but explicitly `null` for the majority of entries.
    let image: String?
    let coingecko: String?
}
