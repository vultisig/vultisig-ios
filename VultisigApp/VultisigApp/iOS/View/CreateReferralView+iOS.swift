//
//  CreateReferralView+iOS.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2025-06-07.
//

#if os(iOS)
import SwiftUI

extension CreateReferralView {
    var container: some View {
        content
            .navigationTitle(NSLocalizedString("createReferral", comment: ""))
    }
}
#endif
