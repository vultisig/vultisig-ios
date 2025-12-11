//
//  CircleMSCAConfig.swift
//  VultisigApp
//
//  Created by Antigravity on 2025-12-11.
//

import Foundation
import BigInt

enum CircleMSCAConfig {
    static let factoryAddress = "0xf61023061ed45fa9eAC4D2670649cE1FD37ce536"
    static let implementationAddress = "0xD206aC7fEf53d83ED4563E770b28Dba90D0D9eC8"
    
    // Limits and Defaults
    static let gasLimit = BigInt(200000) // Default simplified gas limit for MCSA ops
}
