//
//  KeygenView+iOS.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-09-18.
//

#if os(iOS)
import SwiftUI

extension KeygenView {
    var content: some View {
        container
            .navigationTitle(NSLocalizedString(tssType == .Migrate ? "" : "creatingVault", comment: ""))
            .navigationBarTitleDisplayMode(.inline)
            .onLoad {
                Task {
                    await setData()
                    await viewModel.startKeygen(context: context)
                }
            }
            .onAppear {
                UIApplication.shared.isIdleTimerDisabled = true
            }
            .onDisappear {
                UIApplication.shared.isIdleTimerDisabled = false
            }
    }
}
#endif
