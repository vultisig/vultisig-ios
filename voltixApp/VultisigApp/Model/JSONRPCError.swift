//
//  JSONRPCError.swift
//  VultisigApp
//
//  Created by Johnny Luo on 28/3/2024.
//

import Foundation
struct JSONRPCError: Decodable {
    let code: Int
    let message: String
}
