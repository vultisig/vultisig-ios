//
//  EthAddressInfo.swift
//  VoltixApp
//
//  Created by Amol Kumar on 2024-03-04.
//

import SwiftUI

class EthAddressInfo: Codable {
    let address: String
    let ETH: ETHInfo
    let tokens: [EthToken]?
    
    func toString() -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        
        do {
            let jsonData = try encoder.encode(self)
            if let jsonString = String(data: jsonData, encoding: .utf8) {
                return jsonString
            }
        } catch {
            print("Error encoding JSON: \(error)")
            return "Error encoding JSON: \(error)"
        }
        return ""
    }
}
