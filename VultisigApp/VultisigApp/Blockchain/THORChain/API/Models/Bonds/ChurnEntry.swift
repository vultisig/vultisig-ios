//
//  ChurnEntry.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 21/10/2025.
//

import Foundation

struct ChurnEntry: Decodable {
    let date: String   // ns since epoch, as string
    let height: String // block height, as string
}
