//
//  CardanoAssetId.swift
//  VultisigApp
//

import Foundation

enum CardanoAssetIdError: Error, Equatable {
    case missingSeparator
    case emptyPolicyId
    case invalidPolicyIdLength(Int)
    case nonHexPolicyId
    case invalidAssetNameLength(Int)
    case oddAssetNameLength(Int)
    case nonHexAssetName
}

enum CardanoAssetId {
    static let policyIdHexLength = 56
    static let maxAssetNameHexLength = 64
    private static let separator: Character = "."

    static func make(policyId: String, assetName: String) -> String {
        "\(policyId.lowercased())\(separator)\(assetName.lowercased())"
    }

    static func parse(_ id: String) throws -> (policyId: String, assetName: String) {
        guard let separatorIndex = id.firstIndex(of: separator) else {
            throw CardanoAssetIdError.missingSeparator
        }

        let policyId = String(id[..<separatorIndex]).lowercased()
        let assetName = String(id[id.index(after: separatorIndex)...]).lowercased()

        guard !policyId.isEmpty else {
            throw CardanoAssetIdError.emptyPolicyId
        }
        guard policyId.count == policyIdHexLength else {
            throw CardanoAssetIdError.invalidPolicyIdLength(policyId.count)
        }
        guard isHex(policyId) else {
            throw CardanoAssetIdError.nonHexPolicyId
        }
        guard assetName.count <= maxAssetNameHexLength else {
            throw CardanoAssetIdError.invalidAssetNameLength(assetName.count)
        }
        // Asset name encodes raw bytes — odd-length hex is malformed.
        guard assetName.count.isMultiple(of: 2) else {
            throw CardanoAssetIdError.oddAssetNameLength(assetName.count)
        }
        guard isHex(assetName) else {
            throw CardanoAssetIdError.nonHexAssetName
        }

        return (policyId, assetName)
    }

    private static func isHex(_ s: String) -> Bool {
        s.allSatisfy { c in
            (c >= "0" && c <= "9") || (c >= "a" && c <= "f")
        }
    }
}
