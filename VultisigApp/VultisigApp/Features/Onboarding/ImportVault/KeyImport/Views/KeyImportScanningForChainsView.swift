//
//  KeyImportScanningForChainsView.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 02/12/2025.
//

import SwiftUI
import RiveRuntime

struct KeyImportScanningForChainsView: View {
    @State var animationVMLoader: RiveViewModel? = nil
    
    var body: some View {
        VStack(spacing: 12) {
            Spacer()
            animationVMLoader?.view()
                .frame(width: 24, height: 24)
            Text("scanningForChains".localized)
                .font(Theme.fonts.title2)
                .foregroundStyle(Theme.colors.textPrimary)
            Text("scanningForChainsSubtitle".localized)
                .font(Theme.fonts.bodySMedium)
                .foregroundStyle(Theme.colors.textExtraLight)
                .frame(maxWidth: 330)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .onAppear {
            animationVMLoader = RiveViewModel(fileName: "ConnectingWithServer", autoPlay: true)
        }
        .onDisappear {
            animationVMLoader?.stop()
            animationVMLoader = nil
        }
    }
}

#Preview {
    KeyImportScanningForChainsView()
}
