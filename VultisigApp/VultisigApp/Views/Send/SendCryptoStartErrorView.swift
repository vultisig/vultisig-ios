//
//  SendCryptoStartErrorView.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-03-20.
//

import SwiftUI

struct SendCryptoStartErrorView: View {
    let errorText: String

    @EnvironmentObject var appViewModel: AppViewModel

    var body: some View {
        ErrorView(
            type: .warning,
            title: "failToStartKesign".localized,
            description: errorText,
            buttonTitle: "tryAgain".localized
        ) {
            appViewModel.restart()
        }
    }
}

#Preview {
    SendCryptoStartErrorView(errorText: "error")
        .environmentObject(AppViewModel())
}
