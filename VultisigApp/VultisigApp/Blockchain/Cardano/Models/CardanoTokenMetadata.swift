//
//  CardanoTokenMetadata.swift
//  VultisigApp
//

import Foundation

struct CardanoTokenMetadata: Hashable {
    let assetId: String
    let policyId: String
    let assetNameHex: String
    let fingerprint: String?
    let ticker: String
    let decimals: Int
    let registryName: String?
    let registryUrl: String?
    let registryLogo: String?
}
