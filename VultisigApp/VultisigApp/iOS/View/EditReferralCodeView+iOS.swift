//
//  EditReferralCodeView+iOS.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2025-06-06.
//

#if os(iOS)
import SwiftUI

extension EditReferredCodeView {
    var container: some View {
        content
            .navigationTitle(NSLocalizedString("editReferred", comment: ""))
    }
}
#endif
