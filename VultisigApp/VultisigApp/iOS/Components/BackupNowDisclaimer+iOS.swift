//
//  BackupNowDisclaimer+iOS.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-11-13.
//

#if os(iOS)
import SwiftUI

extension BackupNowDisclaimer {
    var container: some View {
        ZStack {
            content
            navigationCell.opacity(0)
        }
    }
}
#endif
