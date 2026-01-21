//
//  UpdateVersion.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-09-11.
//

import SwiftUI

class UpdateVersion: Codable {
    let tagName: String
    let prerelease: Bool

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case prerelease
    }
}
