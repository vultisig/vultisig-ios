//
//  ServerBackupVerificationView+iOS.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-11-13.
//

#if os(iOS)
import SwiftUI

extension ServerBackupVerificationView {
    var container: some View {
        content
            .navigationTitle(NSLocalizedString("serverBackupVerification", comment: ""))
            .navigationBarTitleDisplayMode(.inline)
    }
}
#endif
