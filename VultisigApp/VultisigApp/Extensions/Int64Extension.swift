//
//  Int64Extension.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-03-04.
//

import Foundation

extension Int64 {
    func hexString() -> String {
        var hexStr = String(format: "%02x", self)

        if hexStr.count % 2 != 0 {
            hexStr = "0" + hexStr
        }

        return hexStr
    }
}
