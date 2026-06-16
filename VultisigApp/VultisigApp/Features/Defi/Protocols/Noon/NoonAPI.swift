//
//  NoonAPI.swift
//  VultisigApp
//

import Foundation

/// Off-chain endpoints for Noon APY and Accountable TVL. Both are public (no
/// auth) but reject non-browser User-Agents, so a browser UA is sent.
enum NoonAPI: TargetType {
    case vaults
    case loan(loanAddress: String)

    private static let noonBackBaseURL = makeBaseURL(host: "back.noon.capital")
    private static let accountableBaseURL = makeBaseURL(host: "yield.accountable.capital")

    /// Assembles an `https` base URL from a fixed host. Built via `URLComponents`
    /// so a valid compile-time host can never produce a wrong request; an invalid
    /// host is a programmer error and traps loudly rather than failing silently.
    private static func makeBaseURL(host: String) -> URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = host
        guard let url = components.url else {
            preconditionFailure("Invalid Noon base URL host: \(host)")
        }
        return url
    }

    private static let browserUserAgent =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"

    var baseURL: URL {
        switch self {
        case .vaults:
            return Self.noonBackBaseURL
        case .loan:
            return Self.accountableBaseURL
        }
    }

    var path: String {
        switch self {
        case .vaults:
            return "/api/v1/vaults"
        case .loan(let loanAddress):
            return "/api/loan/address/\(loanAddress)"
        }
    }

    var method: HTTPMethod { .get }

    var task: HTTPTask { .requestPlain }

    var headers: [String: String]? {
        [
            "Content-Type": "application/json",
            "Accept": "application/json",
            "User-Agent": Self.browserUserAgent
        ]
    }
}
