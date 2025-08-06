//
//  THORName.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 05/08/2025.
//

struct THORName: Codable {
    private enum CodingKeys: String, CodingKey {
        case name
        case expireBlockHeight = "expire_block_height"
        case owner
        case preferredAsset = "preferred_asset"
        case preferredAssetSwapThresholdRune = "preferred_asset_swap_threshold_rune"
        case affiliateCollectorRune = "affiliate_collector_rune"
    }
    
    let name: String
    let expireBlockHeight: UInt64
    let owner: String
    let preferredAsset: String
    let preferredAssetSwapThresholdRune: String
    let affiliateCollectorRune: String
    
    var isDefaultPreferredAsset: Bool {
        preferredAsset == "."
    }
}
