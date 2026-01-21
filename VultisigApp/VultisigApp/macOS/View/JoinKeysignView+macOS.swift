//
//  JoinKeysignView+macOS.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-09-19.
//

#if os(macOS)
import SwiftUI

extension JoinKeysignView {
    var content: some View {
        ZStack {
            Background()
            main
        }
    }

    var main: some View {
        VStack {
            headerMac
            Spacer()
            states
            Spacer()
        }
    }

    var headerMac: some View {
        JoinKeygenHeader(title: globalStateViewModel.showKeysignDoneView ? "transactionComplete" : "joinKeysign", hideBackButton: globalStateViewModel.showKeysignDoneView)
    }
}
#endif
