//
//  THORChainConstants.swift
//  VultisigApp
//

import Foundation

enum THORChainConstants {
    /// Average THORChain block time in seconds. Constant since launch.
    static let blockTimeSeconds = 6

    /// 3600 / blockTimeSeconds.
    static let blocksPerHour = 3600 / blockTimeSeconds

    /// Convert wall-clock hours to a THORChain block count.
    static func blocks(forHours hours: Int) -> Int {
        hours * blocksPerHour
    }
}
