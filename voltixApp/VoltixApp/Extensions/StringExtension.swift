//
//  StringExtensions.swift
//  VoltixApp
//
//  Created by Amol Kumar on 2024-03-04.
//

import SwiftUI

// MARK: - String Extensions for Padding and Hex Processing
extension String {
    func paddingLeft(toLength: Int, withPad character: String) -> String {
        let toPad = toLength - self.count
        
        if toPad < 1 {
            return self
        }
        
        return "".padding(toLength: toPad, withPad: character, startingAt: 0) + self
    }
    
    func stripHexPrefix() -> String {
        
        if self.hasPrefix("0x") {
            return String(self.dropFirst(2))
        }
        
        return self
    }
}
