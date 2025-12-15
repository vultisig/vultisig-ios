//
//  ReferralRouteBuilder.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 15/12/2025.
//

import SwiftUI

struct ReferralRouteBuilder {

    @ViewBuilder
    func buildReferredCodeFormScreen(
        referredViewModel: ReferredViewModel,
        referralViewModel: ReferralViewModel
    ) -> some View {
        ReferredCodeFormScreen(
            referredViewModel: referredViewModel,
            referralViewModel: referralViewModel
        )
    }

    @ViewBuilder
    func buildVaultSelectionScreen(selectedVault: Vault?) -> some View {
        ReferralVaultSelectionWrapper(initialVault: selectedVault)
    }
}

// Wrapper to handle the binding requirement
private struct ReferralVaultSelectionWrapper: View {
    let initialVault: Vault?
    @State private var selectedVault: Vault?

    init(initialVault: Vault?) {
        self.initialVault = initialVault
        self._selectedVault = State(initialValue: initialVault)
    }

    var body: some View {
        ReferralVaultSelectionScreen(selectedVault: $selectedVault)
    }
}
