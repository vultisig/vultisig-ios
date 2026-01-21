//
//  JSONRPCResponse.swift
//  VultisigApp
//
//  Created by Johnny Luo on 28/3/2024.
//

import Foundation

struct JSONRPCResponse: Decodable {
    let result: String?
    let error: JSONRPCError?
}
