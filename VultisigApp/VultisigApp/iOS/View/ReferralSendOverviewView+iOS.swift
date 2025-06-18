//
//  ReferralSendOverviewView+iOS.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2025-06-11.
//

#if os(iOS)
import SwiftUI

extension ReferralSendOverviewView {
    var container: some View {
        content
            .navigationTitle(NSLocalizedString("sendOverview", comment: ""))
    }
}
#endif
