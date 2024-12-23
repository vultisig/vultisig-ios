//
//  ServerBackupVerificationView+macOS.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-11-13.
//

#if os(macOS)
import SwiftUI

extension ServerBackupVerificationView {
    var container: some View {
        VStack(spacing: 0) {
            header
            content
        }
    }
    
    var header: some View {
        ServerBackupVerificationHeader()
    }
    
    var content: some View {
        VStack(alignment: .leading, spacing: 12) {
            title
            textField
            Spacer()
            disclaimer
            buttons
        }
        .padding(.horizontal, 40)
    }
}
#endif
