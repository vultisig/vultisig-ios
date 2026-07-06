//
//  TssType+SuccessTitle.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 06/07/2026.
//

import Foundation

extension TssType {
    /// Localization key for the first line of the keygen success state
    /// ("Vault created" / "Vault reshared" + gradient "successfully").
    var keygenSuccessTitleKey: String {
        switch self {
        case .Reshare:
            return "vaultReshared"
        case .Keygen, .KeyImport, .Migrate, .SingleKeygen:
            return "vaultCreated"
        }
    }
}
