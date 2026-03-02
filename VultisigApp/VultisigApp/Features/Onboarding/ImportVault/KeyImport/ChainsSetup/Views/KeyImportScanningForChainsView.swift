//
//  KeyImportScanningForChainsView.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 02/12/2025.
//

import SwiftUI
import RiveRuntime

struct KeyImportScanningForChainsView: View {
    let onSelectChainsManually: () -> Void

    @State var animationVMLoader: RiveViewModel? = nil

    var body: some View {
        VStack(spacing: 12) {
            Spacer()
            animationVMLoader?.view()
                .frame(width: 24, height: 24)
            Text("scanningForChains".localized)
                .font(Theme.fonts.title2)
                .foregroundStyle(Theme.colors.textPrimary)
            CustomHighlightText(
                "scanningForChainsSubtitle".localized,
                highlight: "scanningForChainsSubtitleHighlight".localized,
                style: Theme.colors.textPrimary
            )
            .font(Theme.fonts.bodySMedium)
            .foregroundStyle(Theme.colors.textTertiary)
            .frame(maxWidth: 330)
            .multilineTextAlignment(.center)
            Spacer()
            PrimaryButton(
                title: "selectChainsManually",
                type: .secondary,
                action: onSelectChainsManually
            )
        }
        .onAppear {
            animationVMLoader = RiveViewModel(fileName: "connecting_with_server", autoPlay: true)
        }
        .onDisappear {
            animationVMLoader?.stop()
            animationVMLoader = nil
        }
    }
}

#Preview {
    KeyImportScanningForChainsView(onSelectChainsManually: {})
}
