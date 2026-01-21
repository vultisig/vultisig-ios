//
//  OneInchQuoteError.swift
//  VultisigApp
//
//  Created by Johnny Luo on 8/8/2025.
//

import Foundation

struct OneInchQuoteError: Codable, Error {
    let error: String
    let description: String
    let statusCode: Int
}
    
