//
//  THORNameLookup.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 05/08/2025.
//

struct THORNameLookup: Decodable {
    let expire: String
    let owner: String
    let entries: [THORNameAlias]
}
