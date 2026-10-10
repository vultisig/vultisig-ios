//
//  NearAPI.swift
//  VultisigApp
//

import Foundation

/// The NEAR JSON-RPC endpoint: every method is a POST of its envelope to the root path.
struct NearAPI: TargetType {
    let baseURL: URL
    let body: Data

    var path: String { "" }
    var method: HTTPMethod { .post }
    var task: HTTPTask { .requestData(body) }
}
