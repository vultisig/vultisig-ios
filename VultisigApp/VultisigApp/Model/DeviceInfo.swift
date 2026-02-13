//
//  File.swift
//  VultisigApp
//
//  Created by Enrique Souza Soares on 10/04/2024.
//

import Foundation
import SwiftUI

struct DeviceInfo: Hashable {
    var Index: Int
    var Signer: String

    static func iconName(for signer: String) -> String {
        let laptopSigners = ["windows", "extension", "mac"]
        let isLaptopSigner = laptopSigners.contains {
            signer.lowercased().contains($0)
        }
        return isLaptopSigner ? "laptop" : "phone"
    }
}
