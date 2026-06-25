//
//  TronResourceTypeToggle.swift
//  VultisigApp
//
//  Created for TRON Freeze/Unfreeze integration
//

import SwiftUI

struct TronResourceTypeToggle: View {
    @Binding var selection: TronResourceType
    var onChange: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("tronResourceType".localized)
                .font(Theme.fonts.bodySMedium)
                .foregroundStyle(Theme.colors.textSecondary)

            FilledSegmentedControl(
                selection: $selection,
                options: TronResourceType.allCases,
                size: .filledPill
            )
        }
        .onChange(of: selection) { _, _ in
            onChange?()
        }
    }
}
