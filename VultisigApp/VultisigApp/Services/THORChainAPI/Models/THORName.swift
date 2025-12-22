//
//  THORName.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 05/08/2025.
//

struct THORName: Decodable, Hashable {
    private enum CodingKeys: String, CodingKey {
        case name
        case expireBlockHeight = "expire_block_height"
        case owner
        case preferredAsset = "preferred_asset"
        case preferredAssetSwapThresholdRune = "preferred_asset_swap_threshold_rune"
        case affiliateCollectorRune = "affiliate_collector_rune"
        case aliases
    }
    
    let name: String
    let expireBlockHeight: UInt64
    let owner: String
    let preferredAsset: String
    let preferredAssetSwapThresholdRune: String
    let affiliateCollectorRune: String
    let aliases: [THORNameAlias]
    
    var isDefaultPreferredAsset: Bool {
        preferredAsset == "."
    }
    
    static let example = THORName(
        name: "",
        expireBlockHeight: 0,
        owner: "",
        preferredAsset: "",
        preferredAssetSwapThresholdRune: "",
        affiliateCollectorRune: "",
        aliases: []
    )
}

struct THORNameAlias: Decodable, Hashable {
    let chain: String
    let address: String?
}
