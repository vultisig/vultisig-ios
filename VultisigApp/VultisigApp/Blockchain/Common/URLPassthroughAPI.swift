//
//  URLPassthroughAPI.swift
//  VultisigApp
//
//  Created by Architecture 3.d on 2026-04-23.
//

import Foundation

/// A narrow-use `TargetType` for chain services whose URL construction is
/// already encapsulated elsewhere (e.g. a `*ServiceConfig` that builds
/// chain-specific endpoints, or a dynamic RPC host). The caller supplies a
/// fully-formed URL; this type just routes the request through `HTTPClient`
/// so SwiftLint's `no_raw_urlsession` rule is satisfied and logging/error
/// handling stays consistent with the rest of the networking layer.
///
/// **Prefer enumerated `TargetType`s for new code.** This passthrough is
/// pragmatic glue for chain services where enumerating every endpoint
/// would reimplement existing URL-building logic without much gain. Use
/// only when the URL space is already well-modelled somewhere else.
enum URLPassthroughAPI: TargetType {
    case get(url: URL)
    case post(url: URL, body: Data)

    private var fullURL: URL {
        switch self {
        case .get(let url), .post(let url, _):
            return url
        }
    }

    var baseURL: URL {
        // Strip path + query from the caller-supplied URL so HTTPClient's
        // `baseURL.appendingPathComponent(path)` doesn't mangle the result.
        // Any scheme-or-host issue in the caller's URL is the caller's bug.
        guard var components = URLComponents(url: fullURL, resolvingAgainstBaseURL: false) else {
            return fullURL
        }
        components.path = ""
        components.query = nil
        components.fragment = nil
        return components.url ?? fullURL
    }

    var path: String {
        // Just the path. Query params aren't supported by this passthrough
        // (none of the callers currently need them); if a future caller does,
        // use `.requestParameters` at the call site instead.
        fullURL.path
    }

    var method: HTTPMethod {
        switch self {
        case .get: return .get
        case .post: return .post
        }
    }

    var task: HTTPTask {
        switch self {
        case .get:
            return .requestPlain
        case .post(_, let body):
            return .requestData(body)
        }
    }

    var headers: [String: String]? {
        ["Content-Type": "application/json"]
    }
}
