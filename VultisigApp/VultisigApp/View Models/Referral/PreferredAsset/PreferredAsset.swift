//
//  PreferredAsset.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 07/08/2025.
//

struct PreferredAsset: Identifiable, Equatable {
    var id: CoinMeta { asset }
    let thorchainAsset: String
    let asset: CoinMeta
}
