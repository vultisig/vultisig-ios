//
//  SendRoute.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 13/08/2025.
//

enum SendRoute: Hashable {
    case details(seed: SendDetailsSeed)
    // The review is a sheet over the form (`KeysignReview.send`), and
    // pairing → keysign → done live on the shared `SigningRoute`.
}
