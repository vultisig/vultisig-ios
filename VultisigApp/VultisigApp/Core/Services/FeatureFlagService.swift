//
//  FeatureFlagService.swift
//  VultisigApp
//
//  Created by Johnny Luo on 4/10/2024.
//

import Foundation
enum FeatureFlag: String {
    case EncryptGCM

    var name: String {
        switch self {
        case .EncryptGCM: return "encrypt-gcm"
        }
    }
}

enum FeatureFlagAPI: TargetType {
    case flags

    var baseURL: URL { URL(string: "https://api.vultisig.com")! }

    var path: String {
#if DEBUG
        "/feature/debug.json"
#else
        "/feature/release.json"
#endif
    }

    var method: HTTPMethod { .get }
    var task: HTTPTask { .requestPlain }
}

final class FeatureFlagService {
    private let httpClient: HTTPClientProtocol

    init(httpClient: HTTPClientProtocol = HTTPClient()) {
        self.httpClient = httpClient
    }

    func isFeatureEnabled(feature: FeatureFlag) async -> Bool {
        do {
            let features = try await getFeatureFlagFromServer()
            if let result = features[feature.name] as? Bool {
                return result
            } else {
                print("Feature flag for \(feature) is not a boolean value")
            }

        } catch {
            print("fail to get features \(error)")
        }
        return false
    }

    private func getFeatureFlagFromServer() async throws -> [String: Any] {
        // The server returns a JSON object of arbitrary shape (any value types),
        // so we don't map it to a Codable struct — decode as [String: Any].
        let response = try await httpClient.request(FeatureFlagAPI.flags)
        let jsonObject = try JSONSerialization.jsonObject(with: response.data, options: [])
        guard let jsonDict = jsonObject as? [String: Any] else {
            throw NSError(domain: "FeatureFlagService", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid JSON format"])
        }
        return jsonDict
    }
}
