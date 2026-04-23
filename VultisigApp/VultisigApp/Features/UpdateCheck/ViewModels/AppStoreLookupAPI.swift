//
//  AppStoreLookupAPI.swift
//  VultisigApp
//

import Foundation

enum AppStoreLookupAPI: TargetType {
    case lookup(bundleId: String)

    private static let itunesBaseURL = URL(string: "https://itunes.apple.com")!

    var baseURL: URL { Self.itunesBaseURL }

    var path: String { "/lookup" }

    var method: HTTPMethod { .get }

    var task: HTTPTask {
        switch self {
        case .lookup(let bundleId):
            return .requestParameters(["bundleId": bundleId], .urlEncoding)
        }
    }
}

struct AppStoreLookupResponse: Decodable {
    let results: [Result]

    struct Result: Decodable {
        let version: String?
        let bundleVersion: String?
    }
}
