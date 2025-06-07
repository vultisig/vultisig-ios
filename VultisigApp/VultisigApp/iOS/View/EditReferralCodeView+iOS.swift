//
//  EditReferralCodeView+iOS.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2025-06-06.
//

#if os(iOS)
import SwiftUI

extension EditReferralCodeView {
    var container: some View {
        content
            .navigationTitle(NSLocalizedString("editReferral", comment: ""))
    }
}
#endif
