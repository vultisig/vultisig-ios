//
//  FeatureFlagService.swift
//  VultisigApp
//
//  Created by Johnny Luo on 4/10/2024.
//

import Foundation
enum FeatureFlag: String {
    case EncryptGCM
    case TssBatch

    var name: String {
        switch self {
        case .EncryptGCM: return "encrypt-gcm"
        case .TssBatch: return "tss-batch"
        }
    }
}

final class FeatureFlagService {
    /// Local override keys for feature flags (set via Advanced Settings).
    private static let localOverrideKeys: [FeatureFlag: String] = [
        .TssBatch: "tssBatchEnabled"
    ]

    func isFeatureEnabled(feature: FeatureFlag) async -> Bool {
        // Check local override first (OR logic: local OR remote).
        if let localKey = Self.localOverrideKeys[feature],
           UserDefaults.standard.bool(forKey: localKey) {
            return true
        }

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
#if DEBUG
        let url =  URL(string: "https://api.vultisig.com/feature/debug.json")!
#else
        let url = URL(string: "https://api.vultisig.com/feature/release.json")!
#endif
        let (jsonData, _) = try await URLSession.shared.data(from: url)
        // Decode JSON data into a dictionary
        let jsonObject = try JSONSerialization.jsonObject(with: jsonData, options: [])
        guard let jsonDict = jsonObject as? [String: Any] else {
            throw NSError(domain: "FeatureFlagService", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid JSON format"])
        }
        return jsonDict
    }
}
