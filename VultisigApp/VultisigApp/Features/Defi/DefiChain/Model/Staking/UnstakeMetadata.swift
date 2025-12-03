//
//  UnstakeMetadata.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 03/12/2025.
//

import Foundation

struct UnstakeMetadata: Hashable, Codable {
    let unstakeAvailableDate: TimeInterval

    var canUnstake: Bool {
        let now = Date().timeIntervalSince1970
        return now >= unstakeAvailableDate
    }

    func unstakeMessage(for coin: CoinMeta) -> String? {
        switch coin {
        case TokensStore.cacao:
            let now = Date().timeIntervalSince1970
            let secondsRemaining = unstakeAvailableDate - now

            // If can already unstake, return nil (no message needed)
            guard secondsRemaining > 0 else {
                return nil
            }

            let formatter = DateComponentsFormatter()
            formatter.allowedUnits = [.day, .hour, .minute]
            formatter.unitsStyle = .short
            formatter.maximumUnitCount = 2

            guard let timeString = formatter.string(from: secondsRemaining) else {
                return nil
            }

            return String(format: "cacaoUnstakeMaturityMessage".localized, timeString)
        default:
            return nil
        }
    }
}
