//
//  JSONRPCResponse.swift
//  VoltixApp
//
//  Created by Johnny Luo on 28/3/2024.
//

import Foundation

struct JSONRPCResponse: Decodable {
    let id: Int
    let jsonrpc: String
    let result: String?
    let error: JSONRPCError?
}

