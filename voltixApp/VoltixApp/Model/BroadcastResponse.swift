//
//  BroadcastResponse.swift
//  VoltixApp
//
//  Created by Amol Kumar on 2024-03-04.
//

import Foundation

class BroadcastResponse: Decodable, CustomStringConvertible {
    let id: Int
    let jsonrpc: String
    let result: String // This will hold the transaction hash
    
    var description: String {
        return "BroadcastResponse(id: \(id), jsonrpc: \(jsonrpc), result: \(result))"
    }
}
